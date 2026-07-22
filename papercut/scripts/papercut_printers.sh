#!/bin/bash
#===============================================================================
# PaperCut NG Printer Health — Zabbix UserParameter Script
#===============================================================================
# Checks printer status: online/offline, toner levels, errors.
# Returns a single value per invocation keyed by check_type.
#
# Usage: papercut_printers.sh <check_type>
#===============================================================================

PAPERCUT_HOME="/home/papercut"
SERVER_COMMAND="$PAPERCUT_HOME/server/bin/linux/server-command"

usage() {
    echo "Usage: $0 <check_type>"
    echo ""
    echo "Check types:"
    echo "  total          — Total number of printers"
    echo "  online         — Count of online printers"
    echo "  offline        — Count of offline printers"
    echo "  toner_low      — Count of printers with low/empty toner"
    echo "  errors         — Count of printers with errors"
    echo "  all            — JSON summary of all printer stats"
    exit 1
}

# ─── Get raw printer list ────────────────────────────────────────────────────
get_printers_raw() {
    if [ -x "$SERVER_COMMAND" ]; then
        "$SERVER_COMMAND" list-printers 2>/dev/null
    fi
}

# ─── Get printer details ─────────────────────────────────────────────────────
get_printer_detail() {
    local printer="$1"
    if [ -x "$SERVER_COMMAND" ]; then
        "$SERVER_COMMAND" get-printer-details "$printer" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Total Printers
# ═══════════════════════════════════════════════════════════════════════════════
check_total() {
    local raw
    raw=$(get_printers_raw)
    if [ -z "$raw" ]; then
        echo "0"
    else
        echo "$raw" | wc -l
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Online Printers
# ═══════════════════════════════════════════════════════════════════════════════
check_online() {
    local raw
    raw=$(get_printers_raw)
    if [ -z "$raw" ]; then
        echo "0"
    else
        local count=0
        while IFS= read -r printer; do
            [ -z "$printer" ] && continue
            local details
            details=$(get_printer_detail "$printer" 2>/dev/null)
            if echo "$details" | grep -qi "status.*online\|isOnline.*true\|PrinterStatus.*ONLINE"; then
                count=$((count + 1))
            fi
        done <<< "$raw"
        echo "$count"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Offline Printers
# ═══════════════════════════════════════════════════════════════════════════════
check_offline() {
    local raw
    raw=$(get_printers_raw)
    if [ -z "$raw" ]; then
        echo "0"
    else
        local count=0
        while IFS= read -r printer; do
            [ -z "$printer" ] && continue
            local details
            details=$(get_printer_detail "$printer" 2>/dev/null)
            if echo "$details" | grep -qi "status.*offline\|isOnline.*false\|PrinterStatus.*OFFLINE\|PrinterStatus.*PAUSED\|PrinterStatus.*ERROR"; then
                count=$((count + 1))
            fi
        done <<< "$raw"
        echo "$count"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Low Toner Printers
# ═══════════════════════════════════════════════════════════════════════════════
check_toner_low() {
    local raw
    raw=$(get_printers_raw)
    if [ -z "$raw" ]; then
        echo "0"
    else
        local count=0
        while IFS= read -r printer; do
            [ -z "$printer" ] && continue
            local details
            details=$(get_printer_detail "$printer" 2>/dev/null)
            if echo "$details" | grep -qi "toner.*low\|toner.*empty\|low.*ink\|supply.*low\|cartridge.*low"; then
                count=$((count + 1))
            fi
        done <<< "$raw"
        echo "$count"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Printers with Errors
# ═══════════════════════════════════════════════════════════════════════════════
check_errors() {
    local raw
    raw=$(get_printers_raw)
    if [ -z "$raw" ]; then
        echo "0"
    else
        local count=0
        while IFS= read -r printer; do
            [ -z "$printer" ] && continue
            local details
            details=$(get_printer_detail "$printer" 2>/dev/null)
            if echo "$details" | grep -qi "error\|jam\|paper.*jam\|door.*open\|service.*required\|fault\|offline"; then
                count=$((count + 1))
            fi
        done <<< "$raw"
        echo "$count"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: All (JSON)
# ═══════════════════════════════════════════════════════════════════════════════
check_all() {
    cat <<EOJSON
{
  "total": $(check_total),
  "online": $(check_online),
  "offline": $(check_offline),
  "toner_low": $(check_toner_low),
  "errors": $(check_errors)
}
EOJSON
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Dispatch
# ═══════════════════════════════════════════════════════════════════════════════
case "${1:-help}" in
    total)      check_total ;;
    online)     check_online ;;
    offline)    check_offline ;;
    toner_low)  check_toner_low ;;
    errors)     check_errors ;;
    all)        check_all ;;
    help|--help|-h) usage ;;
    *)
        echo "UNKNOWN_CHECK: $1"
        exit 1
        ;;
esac