#!/bin/bash
#===============================================================================
# PaperCut NG Health Check — Zabbix UserParameter Script
# Designed for Debian 12 Bookworm, PaperCut NG, Zabbix Agent 2
#===============================================================================
# This script is called by Zabbix Agent 2 via UserParameter entries.
# It returns a single value per invocation, keyed by the first argument.
#
# Usage: papercut_health.sh <check_type>
#===============================================================================

PAPERCUT_HOME="/home/papercut"
SERVER_COMMAND="$PAPERCUT_HOME/server/bin/linux/server-command"
API_BASE="http://localhost:9191"

# ─── Help / Usage ────────────────────────────────────────────────────────────
usage() {
    echo "Usage: $0 <check_type>"
    echo ""
    echo "Check types:"
    echo "  appserver       — Application Server status (0=down, 1=up)"
    echo "  db_connection   — Database connection (0=fail, 1=ok)"
    echo "  db_pool         — Database connection pool utilisation (%)"
    echo "  license         — License validity (0=invalid, 1=valid)"
    echo "  license_expiry  — Days until license expiry"
    echo "  siteservers_off — Count of offline site servers"
    echo "  disk_root       — Root partition free space (%)"
    echo "  disk_home       — /home partition free space (%)"
    echo "  all             — Return all checks as JSON (for debugging)"
    exit 1
}

# ─── Check if PaperCut is reachable ──────────────────────────────────────────
papercut_reachable() {
    curl -sf "$API_BASE/api/health" > /dev/null 2>&1
    return $?
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Application Server Status
# ═══════════════════════════════════════════════════════════════════════════════
check_appserver() {
    if systemctl is-active --quiet papercut 2>/dev/null; then
        echo "1"
    elif systemctl is-active --quiet papercut.service 2>/dev/null; then
        echo "1"
    elif pgrep -f "PaperCut.ApplicationServer" > /dev/null 2>&1; then
        echo "1"
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Database Connection
# ═══════════════════════════════════════════════════════════════════════════════
check_db_connection() {
    if papercut_reachable; then
        local db_health
        db_health=$(curl -sf "$API_BASE/api/health/database" 2>/dev/null)
        if echo "$db_health" | grep -qi '"status"\s*:\s*"ok"\|"healthy"\s*:\s*true\|"connected"\s*:\s*true'; then
            echo "1"
        elif echo "$db_health" | grep -qi '"status"\s*:\s*"ok"'; then
            echo "1"
        else
            # Fallback: try server-command
            if [ -x "$SERVER_COMMAND" ]; then
                local result
                result=$("$SERVER_COMMAND" health-check 2>/dev/null)
                if echo "$result" | grep -qi "ok\|healthy\|pass"; then
                    echo "1"
                else
                    echo "0"
                fi
            else
                echo "0"
            fi
        fi
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Database Connection Pool Utilisation (%)
# ═══════════════════════════════════════════════════════════════════════════════
check_db_pool() {
    if papercut_reachable; then
        local pool_data
        pool_data=$(curl -sf "$API_BASE/api/health/database?detail=true" 2>/dev/null)
        # Try to extract pool utilisation
        local pool_pct
        pool_pct=$(echo "$pool_data" | grep -oP '"connectionPoolUtilization"\s*:\s*([0-9.]+)' | grep -oP '[0-9.]+')
        if [ -n "$pool_pct" ]; then
            printf "%.0f\n" "$pool_pct"
        else
            # Fallback: try to get from server-command
            if [ -x "$SERVER_COMMAND" ]; then
                local status
                status=$("$SERVER_COMMAND" get-system-status 2>/dev/null)
                local pool
                pool=$(echo "$status" | grep -i "pool" | grep -oP '[0-9]+' | head -1)
                echo "${pool:-0}"
            else
                echo "0"
            fi
        fi
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: License Validity
# ═══════════════════════════════════════════════════════════════════════════════
check_license() {
    local license_file="$PAPERCUT_HOME/server/data/license.dat"
    if [ -f "$license_file" ]; then
        if [ -x "$SERVER_COMMAND" ]; then
            local lic_info
            lic_info=$("$SERVER_COMMAND" get-license-info 2>/dev/null)
            if echo "$lic_info" | grep -qi "invalid\|expired\|trial" && ! echo "$lic_info" | grep -qi "valid"; then
                echo "0"
            else
                echo "1"
            fi
        else
            # File exists, assume valid (can't verify without server-command)
            echo "1"
        fi
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: License Expiry (days remaining)
# ═══════════════════════════════════════════════════════════════════════════════
check_license_expiry() {
    if [ -x "$SERVER_COMMAND" ]; then
        local lic_info
        lic_info=$("$SERVER_COMMAND" get-license-info 2>/dev/null)
        local expiry_date
        expiry_date=$(echo "$lic_info" | grep -i "expir\|expir" | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}')
        if [ -n "$expiry_date" ]; then
            local expiry_epoch
            expiry_epoch=$(date -d "$expiry_date" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            echo "$days_left"
        else
            echo "365"  # No expiry date found — assume perpetual
        fi
    else
        echo "365"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Offline Site Servers
# ═══════════════════════════════════════════════════════════════════════════════
check_siteservers_offline() {
    if [ -x "$SERVER_COMMAND" ]; then
        local sites
        sites=$("$SERVER_COMMAND" list-site-servers 2>/dev/null)
        if [ -z "$sites" ] || echo "$sites" | grep -qi "no site\|none\|error"; then
            echo "0"
        else
            local offline
            offline=$(echo "$sites" | grep -ci "offline\|down\|disconnect")
            echo "${offline:-0}"
        fi
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Root Partition Free Space (%)
# ═══════════════════════════════════════════════════════════════════════════════
check_disk_root() {
    df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %'
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: /home Partition Free Space (%)
# ═══════════════════════════════════════════════════════════════════════════════
check_disk_home() {
    if mountpoint -q /home 2>/dev/null; then
        df /home --output=pcent 2>/dev/null | tail -1 | tr -d ' %'
    else
        # Same partition as root
        df / --output=pcent 2>/dev/null | tail -1 | tr -d ' %'
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: All (Debug / JSON)
# ═══════════════════════════════════════════════════════════════════════════════
check_all() {
    cat <<EOJSON
{
  "appserver": $(check_appserver),
  "db_connection": $(check_db_connection),
  "db_pool": $(check_db_pool),
  "license": $(check_license),
  "license_expiry_days": $(check_license_expiry),
  "siteservers_offline": $(check_siteservers_offline),
  "disk_root_used_pct": $(check_disk_root),
  "disk_home_used_pct": $(check_disk_home)
}
EOJSON
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Dispatch
# ═══════════════════════════════════════════════════════════════════════════════
case "${1:-help}" in
    appserver)          check_appserver ;;
    db_connection)      check_db_connection ;;
    db_pool)            check_db_pool ;;
    license)            check_license ;;
    license_expiry)     check_license_expiry ;;
    siteservers_off)    check_siteservers_offline ;;
    disk_root)          check_disk_root ;;
    disk_home)          check_disk_home ;;
    all)                check_all ;;
    help|--help|-h)     usage ;;
    *)
        echo "UNKNOWN_CHECK: $1"
        exit 1
        ;;
esac