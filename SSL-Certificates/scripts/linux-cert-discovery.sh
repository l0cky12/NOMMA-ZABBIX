#!/usr/bin/env bash
#===============================================================================
# linux-cert-discovery.sh - Zabbix LLD and expiry reporter for on-disk certs
#===============================================================================
# Usage:
#   linux-cert-discovery.sh discover ["<comma,separated,paths>"]
#   linux-cert-discovery.sh expiry   "<cert file>" ["<comma,separated,paths>"]
#
# discover  Prints Zabbix LLD JSON, one row per certificate found.
# expiry    Prints the whole number of days until that certificate expires
#           (negative once expired).
#
# The script is strictly read-only. It never writes a file, never restarts a
# service and never modifies configuration. The only file it reads outside the
# configured certificate paths is the root-guarded PKCS#12 password file
# /etc/zabbix/tls_check.env, and that file is parsed rather than sourced so it
# cannot execute anything.
#
# /etc/ssl/certs (the system trust store) is always excluded.
#===============================================================================

set -o nounset

ENV_FILE="/etc/zabbix/tls_check.env"
DEFAULT_PATHS="/etc/pki,/etc/nginx,/etc/apache2,/etc/httpd,/etc/ssl/private,/home/papercut/server/custom"
MAX_DEPTH=4

#-------------------------------------------------------------------------------
# Generic helpers
#-------------------------------------------------------------------------------

usage() {
    cat >&2 <<'USAGE'
Usage:
  linux-cert-discovery.sh discover ["<comma,separated,paths>"]
  linux-cert-discovery.sh expiry   "<cert file>" ["<comma,separated,paths>"]
USAGE
}

trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

json_escape() {
    printf '%s' "$1" \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/ /g' \
        | tr -d '\r\n'
}

# Fall back to the built-in list when the macro is empty or was not expanded.
resolve_paths() {
    case "$1" in
        ''|'{$TLS.STORE.PATHS}') printf '%s' "$DEFAULT_PATHS" ;;
        *)                       printf '%s' "$1" ;;
    esac
}

#-------------------------------------------------------------------------------
# PKCS#12 password: parsed (never sourced) from the root-guarded env file.
# Returns 1 when the file is absent or holds no password, so .p12/.pfx files
# are skipped silently and the endpoint check still covers PaperCut.
#-------------------------------------------------------------------------------

read_p12_password() {
    TLS_P12_PASSWORD=""

    [ -f "$ENV_FILE" ] || return 1
    [ -r "$ENV_FILE" ] || return 1

    line=$(grep -E '^[[:space:]]*TLS_P12_PASSWORD[[:space:]]*=' "$ENV_FILE" 2>/dev/null | tail -n 1)
    [ -n "$line" ] || return 1

    value=$(printf '%s' "$line" | sed -e 's/^[^=]*=//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    value=$(printf '%s' "$value" | sed -e 's/^"\(.*\)"$/\1/' -e "s/^'\(.*\)'\$/\1/")
    [ -n "$value" ] || return 1

    TLS_P12_PASSWORD="$value"
    export TLS_P12_PASSWORD
    return 0
}

#-------------------------------------------------------------------------------
# Certificate reading
#-------------------------------------------------------------------------------

# Prints the openssl subject=/issuer=/notAfter= lines for one file.
extract_cert_text() {
    file="$1"
    out=""

    case "$file" in
        *.p12|*.P12|*.pfx|*.PFX)
            read_p12_password || return 1

            # -passin env: keeps the password out of the process list.
            out=$(openssl pkcs12 -in "$file" -nokeys -clcerts -passin env:TLS_P12_PASSWORD 2>/dev/null \
                | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)

            # OpenSSL 3.x needs -legacy for RC2/3DES keystores.
            if [ -z "$out" ]; then
                out=$(openssl pkcs12 -legacy -in "$file" -nokeys -clcerts -passin env:TLS_P12_PASSWORD 2>/dev/null \
                    | openssl x509 -noout -subject -issuer -enddate 2>/dev/null)
            fi

            unset TLS_P12_PASSWORD
            ;;
        *)
            out=$(openssl x509 -in "$file" -noout -subject -issuer -enddate 2>/dev/null)

            if [ -z "$out" ]; then
                out=$(openssl x509 -inform DER -in "$file" -noout -subject -issuer -enddate 2>/dev/null)
            fi
            ;;
    esac

    [ -n "$out" ] || return 1

    printf '%s\n' "$out"
    return 0
}

# field_value "<openssl output>" "<prefix>"
field_value() {
    printf '%s\n' "$1" \
        | grep -m 1 "^$2" \
        | sed -e "s/^$2//" -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Takes the first CN= component of a subject DN, in either RFC2253
# ("CN = host, O = NOMMA") or legacy ("/CN=host/O=NOMMA") form.
cn_from_subject() {
    printf '%s' "$1" \
        | tr ',/' '\n\n' \
        | sed -n 's/^[[:space:]]*CN[[:space:]]*=[[:space:]]*//p' \
        | head -n 1 \
        | sed -e 's/[[:space:]]*$//'
}

normalise_date() {
    normalised=$(date -u -d "$1" '+%Y-%m-%d %H:%M:%S' 2>/dev/null)

    if [ -z "$normalised" ]; then
        normalised="$1"
    fi

    printf '%s' "$normalised"
}

days_remaining() {
    expires_at=$(date -u -d "$1" '+%s' 2>/dev/null)
    [ -n "$expires_at" ] || return 1

    now_at=$(date -u '+%s')

    awk -v e="$expires_at" -v n="$now_at" 'BEGIN {
        d = (e - n) / 86400
        i = int(d)
        if (d < 0 && d != i) { i = i - 1 }
        printf "%d\n", i
    }'

    return 0
}

#-------------------------------------------------------------------------------
# Path handling
#-------------------------------------------------------------------------------

list_cert_files() {
    csv="$1"
    old_ifs="$IFS"

    set -f
    IFS=','
    set -- $csv
    IFS="$old_ifs"
    set +f

    for entry in "$@"; do
        candidate=$(trim "$entry")
        [ -n "$candidate" ] || continue

        case "$candidate" in
            /etc/ssl/certs|/etc/ssl/certs/*) continue ;;
        esac

        if [ -f "$candidate" ]; then
            printf '%s\n' "$candidate"
        elif [ -d "$candidate" ]; then
            find "$candidate" -maxdepth "$MAX_DEPTH" -type f \
                \( -iname '*.pem' -o -iname '*.crt' -o -iname '*.cer' \
                   -o -iname '*.der' -o -iname '*.p12' -o -iname '*.pfx' \) \
                2>/dev/null
        fi
    done
}

# Only report on files that live under one of the configured roots, so an
# arbitrary path cannot be probed through the item key.
is_allowed_path() {
    file="$1"
    csv="$2"

    [ -n "$file" ] || return 1
    [ -f "$file" ] || return 1

    case "$file" in
        *..*)                            return 1 ;;
        /etc/ssl/certs|/etc/ssl/certs/*) return 1 ;;
    esac

    old_ifs="$IFS"

    set -f
    IFS=','
    set -- $csv
    IFS="$old_ifs"
    set +f

    for entry in "$@"; do
        root=$(trim "$entry")
        [ -n "$root" ] || continue

        case "$file" in
            "$root")   return 0 ;;
            "$root"/*) return 0 ;;
        esac
    done

    return 1
}

#-------------------------------------------------------------------------------
# Modes
#-------------------------------------------------------------------------------

do_discover() {
    paths=$(resolve_paths "$1")
    first=1

    printf '['

    list_cert_files "$paths" | sort -u | while IFS= read -r file; do
        text=$(extract_cert_text "$file") || continue

        subject=$(field_value "$text" 'subject=')
        issuer=$(field_value "$text" 'issuer=')
        notafter_raw=$(field_value "$text" 'notAfter=')

        [ -n "$notafter_raw" ] || continue

        cn=$(cn_from_subject "$subject")
        [ -n "$cn" ] || cn="$file"

        notafter=$(normalise_date "$notafter_raw")

        case "$file" in
            *.p12|*.P12|*.pfx|*.PFX) cert_type="pkcs12" ;;
            *)                       cert_type="pem" ;;
        esac

        if [ "$first" -eq 0 ]; then
            printf ','
        fi
        first=0

        printf '{"{#TLS.CERT.FILE}":"%s","{#TLS.CERT.CN}":"%s","{#TLS.CERT.SUBJECT}":"%s","{#TLS.CERT.ISSUER}":"%s","{#TLS.CERT.NOTAFTER}":"%s","{#TLS.CERT.TYPE}":"%s"}' \
            "$(json_escape "$file")" \
            "$(json_escape "$cn")" \
            "$(json_escape "$subject")" \
            "$(json_escape "$issuer")" \
            "$(json_escape "$notafter")" \
            "$cert_type"
    done

    printf ']\n'
}

do_expiry() {
    file="$1"
    paths=$(resolve_paths "$2")

    if ! is_allowed_path "$file" "$paths"; then
        printf 'linux-cert-discovery.sh expiry: %s is not a readable file under the configured paths\n' "$file" >&2
        exit 1
    fi

    text=$(extract_cert_text "$file") || exit 1

    notafter_raw=$(field_value "$text" 'notAfter=')
    [ -n "$notafter_raw" ] || exit 1

    days=$(days_remaining "$notafter_raw") || exit 1
    [ -n "$days" ] || exit 1

    printf '%s\n' "$days"
}

#-------------------------------------------------------------------------------
# Dispatch
#-------------------------------------------------------------------------------

if ! command -v openssl >/dev/null 2>&1; then
    printf 'linux-cert-discovery.sh: openssl is not installed\n' >&2
    exit 1
fi

action="${1:-}"

case "$action" in
    discover) do_discover "${2:-}" ;;
    expiry)   do_expiry "${2:-}" "${3:-}" ;;
    *)        usage; exit 1 ;;
esac

exit 0
