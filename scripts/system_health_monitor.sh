#!/usr/bin/env bash
# ============================================================
# System Health Monitoring Script
# Monitors CPU, memory, disk usage, and running processes
# Alerts when metrics exceed configurable thresholds
# ============================================================
set -euo pipefail

CPU_THRESHOLD="${CPU_THRESHOLD:-80}"
MEMORY_THRESHOLD="${MEMORY_THRESHOLD:-80}"
DISK_THRESHOLD="${DISK_THRESHOLD:-80}"
LOAD_THRESHOLD="${LOAD_THRESHOLD:-2.0}"
ZOMBIE_THRESHOLD="${ZOMBIE_THRESHOLD:-5}"
LOG_FILE="${LOG_FILE:-/var/log/system_health.log}"
INTERVAL="${INTERVAL:-0}"
LOG_ONLY="${LOG_ONLY:-false}"
TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

timestamp() { date +"${TIMESTAMP_FORMAT}"; }

log_message() {
    local level="$1" message="$2" ts
    ts=$(timestamp)
    local entry="[${ts}] [${level}] ${message}"
    if [[ -w "$(dirname "${LOG_FILE}")" ]] || [[ -w "${LOG_FILE}" ]]; then
        echo "${entry}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
    if [[ "${LOG_ONLY}" != "true" ]]; then
        case "${level}" in
            "CRITICAL"|"ALERT") echo -e "${RED}${BOLD}${entry}${NC}" ;;
            "WARNING") echo -e "${YELLOW}${entry}${NC}" ;;
            *) echo -e "${GREEN}${entry}${NC}" ;;
        esac
    fi
}

print_header() {
    [[ "${LOG_ONLY}" == "true" ]] && return
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║        System Health Monitoring Report           ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo "Host:       $(hostname)"
    echo "Date:       $(timestamp)"
    echo "Uptime:     $(uptime -p 2>/dev/null || uptime 2>/dev/null || echo 'N/A')"
    echo "Kernel:     $(uname -r)"
    echo ""
}

check_cpu() {
    echo -e "${BOLD}📊 CPU Usage:${NC}"
    local cpu_usage cpu_int
    cpu_usage=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print $2 + $4}' 2>/dev/null || grep -m1 'cpu ' /proc/stat 2>/dev/null | awk '{usage=($2+$4)*100/($2+$4+$5); printf "%.1f", usage}' 2>/dev/null || echo "0")
    cpu_int=$(echo "${cpu_usage}" | cut -d. -f1)
    if (( cpu_int >= CPU_THRESHOLD )); then
        log_message "CRITICAL" "CPU: ${cpu_usage}% (threshold: ${CPU_THRESHOLD}%)"
        return 1
    elif (( cpu_int >= CPU_THRESHOLD - 10 )); then
        log_message "WARNING" "CPU: ${cpu_usage}% (approaching ${CPU_THRESHOLD}%)"
    else
        log_message "OK" "CPU: ${cpu_usage}%"
    fi
    return 0
}

check_memory() {
    echo -e "${BOLD}💾 Memory Usage:${NC}"
    if ! command -v free &>/dev/null; then
        log_message "WARNING" "'free' not available"; return 0
    fi
    local mem_info total used available mem_usage mem_int
    mem_info=$(free | grep Mem)
    total=$(echo "${mem_info}" | awk '{print $2}')
    used=$(echo "${mem_info}" | awk '{print $3}')
    available=$(echo "${mem_info}" | awk '{print $7}')
    mem_usage=$(awk "BEGIN {printf \"%.1f\", (${used}/${total})*100}")
    mem_int=$(echo "${mem_usage}" | cut -d. -f1)
    local total_mb used_mb avail_mb
    total_mb=$(awk "BEGIN {printf \"%.0f\", ${total}/1024}")
    used_mb=$(awk "BEGIN {printf \"%.0f\", ${used}/1024}")
    avail_mb=$(awk "BEGIN {printf \"%.0f\", ${available}/1024}")
    echo "  Total: ${total_mb} MB | Used: ${used_mb} MB | Available: ${avail_mb} MB | Usage: ${mem_usage}%"
    if (( mem_int >= MEMORY_THRESHOLD )); then
        log_message "CRITICAL" "Memory: ${mem_usage}% (threshold: ${MEMORY_THRESHOLD}%)"
        return 1
    elif (( mem_int >= MEMORY_THRESHOLD - 10 )); then
        log_message "WARNING" "Memory: ${mem_usage}% (approaching ${MEMORY_THRESHOLD}%)"
    else
        log_message "OK" "Memory: ${mem_usage}%"
    fi
    return 0
}

check_disk() {
    echo -e "${BOLD}💿 Disk Usage:${NC}"
    local alerts=0
    while IFS= read -r line; do
        local mount usage size used avail
        mount=$(echo "${line}" | awk '{print $6}')
        usage=$(echo "${line}" | awk '{print $5}' | tr -d '%')
        size=$(echo "${line}" | awk '{print $2}')
        used=$(echo "${line}" | awk '{print $3}')
        avail=$(echo "${line}" | awk '{print $4}')
        if (( usage >= DISK_THRESHOLD )); then
            echo -e "  ${RED}⚠️  ${mount}: ${usage}% [${used}/${size}]${NC}"
            log_message "CRITICAL" "Disk ${mount}: ${usage}% (threshold: ${DISK_THRESHOLD}%)"
            alerts=$((alerts+1))
        elif (( usage >= DISK_THRESHOLD - 10 )); then
            echo -e "  ${YELLOW}⚡ ${mount}: ${usage}% [${used}/${size}]${NC}"
            log_message "WARNING" "Disk ${mount}: ${usage}%"
        else
            echo -e "  ${GREEN}✅ ${mount}: ${usage}% [${used}/${size}]${NC}"
        fi
    done < <(df -h --output=source,size,used,avail,pcent,target -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | tail -n +2 || df -h 2>/dev/null | grep -vE '^Filesystem|tmpfs|devtmpfs')
    (( alerts > 0 )) && return 1
    return 0
}

check_processes() {
    echo -e "${BOLD}⚙️  Processes:${NC}"
    local total_procs zombie_count
    total_procs=$(ps aux | wc -l)
    total_procs=$((total_procs - 1))
    zombie_count=$(ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}')
    echo "  Total: ${total_procs} | Zombies: ${zombie_count}"
    if (( zombie_count >= ZOMBIE_THRESHOLD )); then
        log_message "CRITICAL" "${zombie_count} zombie processes (threshold: ${ZOMBIE_THRESHOLD})"
        return 1
    elif (( zombie_count > 0 )); then
        log_message "WARNING" "${zombie_count} zombie process(es)"
    else
        log_message "OK" "No zombies"
    fi
    return 0
}

check_load() {
    echo -e "${BOLD}📈 Load Average:${NC}"
    local load_1 load_5 load_15 cpu_count threshold_scaled
    read -r load_1 load_5 load_15 _ < /proc/loadavg
    cpu_count=$(nproc 2>/dev/null || echo 1)
    threshold_scaled=$(awk "BEGIN {printf \"%.2f\", ${LOAD_THRESHOLD} * ${cpu_count}}")
    echo "  Load: ${load_1}/${load_5}/${load_15} | Cores: ${cpu_count} | Threshold: ${threshold_scaled}"
    if awk "BEGIN {exit !(${load_1} > ${threshold_scaled})}"; then
        log_message "CRITICAL" "Load ${load_1} > threshold ${threshold_scaled}"
        return 1
    elif awk "BEGIN {exit !(${load_1} > ${threshold_scaled} * 0.8)}"; then
        log_message "WARNING" "Load ${load_1} approaching threshold"
    else
        log_message "OK" "Load ${load_1} normal"
    fi
    return 0
}

check_network() {
    echo -e "${BOLD}🌐 Network:${NC}"
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        echo -e "  ${GREEN}✅ Connectivity: OK${NC}"
        log_message "OK" "Network healthy"
    else
        echo -e "  ${YELLOW}⚠️  Connectivity: UNREACHABLE${NC}"
        log_message "WARNING" "Cannot reach 8.8.8.8"
    fi
    return 0
}

print_summary() {
    local total=$1 passed=$2 failed=$3 warnings=$4
    [[ "${LOG_ONLY}" == "true" ]] && return
    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
    echo -e "${BOLD}📋 Summary: ${total} checks | ${GREEN}Passed: ${passed}${NC}"
    (( warnings > 0 )) && echo -e "  ${YELLOW}Warnings: ${warnings}${NC}"
    (( failed > 0 )) && echo -e "  ${RED}Failed: ${failed}${NC}"
    echo ""
    if (( failed > 0 )); then
        echo -e "${RED}${BOLD}🚨 CRITICAL — Attention required!${NC}"
    elif (( warnings > 0 )); then
        echo -e "${YELLOW}${BOLD}⚠️  WARNING — Monitor closely${NC}"
    else
        echo -e "${GREEN}${BOLD}✅ GOOD — All systems operational${NC}"
    fi
    echo -e "${CYAN}────────────────────────────────────────────────────${NC}"
}

run_health_check() {
    local tc=0 p=0 f=0 w=0
    print_header
    tc=$((tc+1)); check_cpu && p=$((p+1)) || f=$((f+1))
    echo ""
    tc=$((tc+1)); check_memory && p=$((p+1)) || f=$((f+1))
    echo ""
    tc=$((tc+1)); check_disk && p=$((p+1)) || f=$((f+1))
    echo ""
    tc=$((tc+1)); check_processes && p=$((p+1)) || f=$((f+1))
    echo ""
    tc=$((tc+1)); check_load && p=$((p+1)) || f=$((f+1))
    echo ""
    tc=$((tc+1)); check_network && p=$((p+1)) || w=$((w+1))
    echo ""
    print_summary "${tc}" "${p}" "${f}" "${w}"
    [[ $f -gt 0 ]] && return 2
    [[ $w -gt 0 ]] && return 1
    return 0
}
# ============================================================
# Argument parsing
# ============================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --log-file) LOG_FILE="$2"; shift 2 ;;
        --interval) INTERVAL="$2"; shift 2 ;;
        --log-only) LOG_ONLY="true"; shift ;;
        --cpu-threshold) CPU_THRESHOLD="$2"; shift 2 ;;
        --mem-threshold) MEMORY_THRESHOLD="$2"; shift 2 ;;
        --disk-threshold) DISK_THRESHOLD="$2"; shift 2 ;;
        --help|-h)
            echo "System Health Monitor"
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --log-file PATH       Log file path (default: /var/log/system_health.log)"
            echo "  --interval SECONDS    Run every N seconds (0=once)"
            echo "  --log-only            Log only, no console output"
            echo "  --cpu-threshold NUM   CPU threshold (default: 80)"
            echo "  --mem-threshold NUM   Memory threshold (default: 80)"
            echo "  --disk-threshold NUM  Disk threshold (default: 80)"
            echo "  -h, --help            Show this help"
            exit 0 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# ============================================================
# Main
# ============================================================
if (( INTERVAL > 0 )); then
    echo "Starting continuous monitoring (interval: ${INTERVAL}s)"
    while true; do
        run_health_check
        echo "Next check in ${INTERVAL}s..."
        sleep "${INTERVAL}"
    done
else
    run_health_check
fi
