#!/bin/bash
#===============================================================================
# PaperCut NG Print Activity Monitor — Zabbix UserParameter Script
#===============================================================================
# Checks recent print activity to detect stale queues.
#
# Usage: papercut_activity.sh <check_type>
#===============================================================================

PAPERCUT_HOME="/home/papercut"
SERVER_COMMAND="$PAPERCUT_HOME/server/bin/linux/server-command"
LOG_DIR="$PAPERCUT_HOME/server/data/logs"

usage() {
    echo "Usage: $0 <check_type>"
    echo ""
    echo "Check types:"
    echo "  minutes_since    — Minutes since the last completed print job"
    echo "  jobs_last_hour   — Number of print jobs in the last 60 minutes"
    echo "  jobs_last_day    — Number of print jobs in the last 24 hours"
    echo "  all              — JSON summary of all activity stats"
    exit 1
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Minutes Since Last Print Job
# ═══════════════════════════════════════════════════════════════════════════════
check_minutes_since() {
    if [ -x "$SERVER_COMMAND" ]; then
        local recent
        recent=$("$SERVER_COMMAND" get-recent-print-jobs 2>/dev/null | head -20)
        if [ -z "$recent" ]; then
            echo "9999"
            return
        fi
        # Try to find a timestamp in the output
        local timestamp
        timestamp=$(echo "$recent" | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?' | head -1)
        if [ -n "$timestamp" ]; then
            local job_epoch
            job_epoch=$(date -d "$timestamp" +%s 2>/dev/null)
            local now_epoch
            now_epoch=$(date +%s)
            local diff_min=$(( (now_epoch - job_epoch) / 60 ))
            echo "$diff_min"
        else
            echo "9999"
        fi
    else
        # Fallback: check server log for recent activity
        if [ -d "$LOG_DIR" ]; then
            local log_file
            log_file=$(find "$LOG_DIR" -name "server.log*" -type f 2>/dev/null | sort | tail -1)
            if [ -n "$log_file" ]; then
                local last_job_time
                last_job_time=$(grep -i "print" "$log_file" 2>/dev/null | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?' | tail -1)
                if [ -n "$last_job_time" ]; then
                    local job_epoch
                    job_epoch=$(date -d "$last_job_time" +%s 2>/dev/null)
                    local now_epoch
                    now_epoch=$(date +%s)
                    local diff_min=$(( (now_epoch - job_epoch) / 60 ))
                    echo "$diff_min"
                else
                    echo "9999"
                fi
            else
                echo "9999"
            fi
        else
            echo "9999"
        fi
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Jobs in Last Hour
# ═══════════════════════════════════════════════════════════════════════════════
check_jobs_last_hour() {
    if [ -x "$SERVER_COMMAND" ]; then
        local recent
        recent=$("$SERVER_COMMAND" get-recent-print-jobs 2>/dev/null)
        if [ -z "$recent" ]; then
            echo "0"
            return
        fi
        local now_epoch
        now_epoch=$(date +%s)
        local one_hour_ago=$((now_epoch - 3600))
        local count=0
        while IFS= read -r line; do
            local timestamp
            timestamp=$(echo "$line" | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?' | head -1)
            if [ -n "$timestamp" ]; then
                local line_epoch
                line_epoch=$(date -d "$timestamp" +%s 2>/dev/null)
                if [ -n "$line_epoch" ] && [ "$line_epoch" -ge "$one_hour_ago" ]; then
                    count=$((count + 1))
                fi
            fi
        done <<< "$recent"
        echo "$count"
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: Jobs in Last 24 Hours
# ═══════════════════════════════════════════════════════════════════════════════
check_jobs_last_day() {
    if [ -x "$SERVER_COMMAND" ]; then
        local recent
        recent=$("$SERVER_COMMAND" get-recent-print-jobs 2>/dev/null)
        if [ -z "$recent" ]; then
            echo "0"
            return
        fi
        local now_epoch
        now_epoch=$(date +%s)
        local one_day_ago=$((now_epoch - 86400))
        local count=0
        while IFS= read -r line; do
            local timestamp
            timestamp=$(echo "$line" | grep -oP '[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}(:[0-9]{2})?' | head -1)
            if [ -n "$timestamp" ]; then
                local line_epoch
                line_epoch=$(date -d "$timestamp" +%s 2>/dev/null)
                if [ -n "$line_epoch" ] && [ "$line_epoch" -ge "$one_day_ago" ]; then
                    count=$((count + 1))
                fi
            fi
        done <<< "$recent"
        echo "$count"
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# CHECK: All (JSON)
# ═══════════════════════════════════════════════════════════════════════════════
check_all() {
    cat <<EOJSON
{
  "minutes_since_last_job": $(check_minutes_since),
  "jobs_last_hour": $(check_jobs_last_hour),
  "jobs_last_day": $(check_jobs_last_day)
}
EOJSON
}

# ═══════════════════════════════════════════════════════════════════════════════
# Main Dispatch
# ═══════════════════════════════════════════════════════════════════════════════
case "${1:-help}" in
    minutes_since)  check_minutes_since ;;
    jobs_last_hour) check_jobs_last_hour ;;
    jobs_last_day)  check_jobs_last_day ;;
    all)            check_all ;;
    help|--help|-h) usage ;;
    *)
        echo "UNKNOWN_CHECK: $1"
        exit 1
        ;;
esac