#!/usr/bin/env bash
# ============================================================
# Application Health Checker
# Checks HTTP status of an application to determine if it is
# up or down. Supports retries, timeouts, and detailed logging.
# ============================================================
set -euo pipefail

# ============================================================
# Defaults
# ============================================================
URL="${URL:-http://wisecow-service:80}"
RETRIES="${RETRIES:-3}"
TIMEOUT="${TIMEOUT:-5}"
RETRY_DELAY="${RETRY_DELAY:-2}"
EXPECTED_CODE="${EXPECTED_CODE:-200}"
LOG_FILE="${LOG_FILE:-}"
VERBOSE="${VERBOSE:-true}"
TIMESTAMP_FORMAT="%Y-%m-%d %H:%M:%S"

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

# ============================================================
# Helpers
# ============================================================
timestamp() { date +"${TIMESTAMP_FORMAT}"; }

log() {
    local level="$1" msg="$2"
    local ts entry
    ts=$(timestamp)
    entry="[${ts}] [${level}] ${msg}"
    [[ -n "${LOG_FILE}" ]] && echo "${entry}" >> "${LOG_FILE}" 2>/dev/null || true
    if [[ "${VERBOSE}" == "true" ]]; then
        case "${level}" in
            "ERROR"|"DOWN")   echo -e "${RED}${BOLD}${entry}${NC}" ;;
            "WARN")           echo -e "${YELLOW}${entry}${NC}" ;;
            "OK"|"UP")        echo -e "${GREEN}${entry}${NC}" ;;
            *)                echo -e "${entry}" ;;
        esac
    fi
}

usage() {
    cat << 'EOF'
Application Health Checker
==========================
Checks if a web application is running and responding correctly.

Usage: ./app_health_checker.sh [OPTIONS]

Options:
  -u, --url URL              Application URL (default: http://wisecow-service:80)
  -r, --retries NUM          Number of retry attempts (default: 3)
  -t, --timeout SECONDS      HTTP request timeout (default: 5)
  -d, --retry-delay SECONDS  Delay between retries (default: 2)
  -e, --expected-code CODE   Expected HTTP status code (default: 200)
  -l, --log-file PATH        Path to log file (optional)
  -q, --quiet                Suppress console output
  -h, --help                 Show this help

Exit Codes:
  0 = Application is UP and healthy
  1 = Application is DOWN or unhealthy
  2 = Application is UNREACHABLE

Examples:
  ./app_health_checker.sh -u http://wisecow-service:80
  ./app_health_checker.sh -u https://wisecow.local -e 200 -r 5
  URL=http://localhost:8888 ./app_health_checker.sh --timeout 10
EOF
}

# ============================================================
# Argument Parsing
# ============================================================
QUIET=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -u|--url)          URL="$2"; shift 2 ;;
        -r|--retries)      RETRIES="$2"; shift 2 ;;
        -t|--timeout)      TIMEOUT="$2"; shift 2 ;;
        -d|--retry-delay)  RETRY_DELAY="$2"; shift 2 ;;
        -e|--expected-code) EXPECTED_CODE="$2"; shift 2 ;;
        -l|--log-file)     LOG_FILE="$2"; shift 2 ;;
        -q|--quiet)        QUIET=true; VERBOSE=false; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) echo "Unknown option: $1 (use -h for help)"; exit 1 ;;
    esac
done

# ============================================================
# Health Check Logic
# ============================================================
check_app() {
    local url="$1" attempt=1 http_code="" response_time="" body=""

    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════╗"
    echo -e "║          Application Health Check                ║"
    echo -e "╚══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  URL:            ${url}"
    echo -e "  Expected Code:  ${EXPECTED_CODE}"
    echo -e "  Max Retries:    ${RETRIES}"
    echo -e "  Timeout:        ${TIMEOUT}s"
    echo -e "  Retry Delay:    ${RETRY_DELAY}s"
    echo ""

    while (( attempt <= RETRIES )); do
        echo -e "${BOLD}Attempt ${attempt}/${RETRIES}:${NC}"

        # Make HTTP request
        local tmp_body
        tmp_body=$(mktemp)
        
        http_code=$(curl \
            --silent \
            --output "${tmp_body}" \
            --write-out "%{http_code}" \
            --max-time "${TIMEOUT}" \
            --connect-timeout "${TIMEOUT}" \
            "${url}" 2>/dev/null) || http_code="000"

        response_time=$(curl \
            --silent \
            --output /dev/null \
            --write-out "%{time_total}" \
            --max-time "${TIMEOUT}" \
            --connect-timeout "${TIMEOUT}" \
            "${url}" 2>/dev/null) || response_time="N/A"

        body=$(head -c 500 "${tmp_body}" 2>/dev/null || echo "")
        rm -f "${tmp_body}"

        # Evaluate result
        case "${http_code}" in
            "${EXPECTED_CODE}")
                echo -e "  ${GREEN}✅ Status: UP${NC}"
                echo -e "  HTTP Code:    ${GREEN}${http_code}${NC}"
                echo -e "  Response Time: ${response_time}s"
                log "UP" "Application is UP | URL=${url} | HTTP=${http_code} | Time=${response_time}s"
                return 0
                ;;
            "000")
                echo -e "  ${RED}❌ Status: UNREACHABLE${NC}"
                echo -e "  HTTP Code:    ${RED}000 (connection failed/timeout)${NC}"
                log "DOWN" "Application UNREACHABLE | URL=${url} | Attempt=${attempt}/${RETRIES}"
                ;;
            "4[0-9][0-9]"|"5[0-9][0-9]")
                echo -e "  ${RED}❌ Status: DOWN${NC}"
                echo -e "  HTTP Code:    ${RED}${http_code}${NC}"
                echo -e "  Response Time: ${response_time}s"
                log "DOWN" "Application DOWN | URL=${url} | HTTP=${http_code} | Attempt=${attempt}/${RETRIES}"
                ;;
            *)
                if [[ "${http_code}" == "${EXPECTED_CODE}" ]]; then
                    echo -e "  ${GREEN}✅ Status: UP${NC}"
                    log "UP" "Application is UP | HTTP=${http_code}"
                    return 0
                fi
                echo -e "  ${YELLOW}⚠️  Status: UNEXPECTED${NC}"
                echo -e "  HTTP Code:    ${YELLOW}${http_code}${NC} (expected: ${EXPECTED_CODE})"
                log "WARN" "Unexpected HTTP code | HTTP=${http_code} | Expected=${EXPECTED_CODE}"
                ;;
        esac

        # Retry if not the last attempt
        if (( attempt < RETRIES )); then
            echo -e "  ${YELLOW}Retrying in ${RETRY_DELAY}s...${NC}"
            sleep "${RETRY_DELAY}"
        fi
        ((attempt++))
    done

    # All retries exhausted
    echo ""
    echo -e "${RED}${BOLD}🚨 RESULT: Application is DOWN after ${RETRIES} attempts${NC}"
    log "DOWN" "Application FAILED health check | URL=${url} | All ${RETRIES} attempts failed"
    return 1
}
# ============================================================
# Main
# ============================================================
check_app "${URL}"
exit $?
