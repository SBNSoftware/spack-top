#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_LOGGING_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _LOGGING_FUNCTIONS_SH_=1

NON_INTERACTIVE=${NON_INTERACTIVE:-false}
VERBOSE=${VERBOSE:-true}
LOGS_DIR=${LOGS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/logs"}
CMDS_FILE=${CMDS_FILE:-"${LOGS_DIR}/commands.log"}
MAX_LOGS=${MAX_LOGS:-10}
LOG_LEVEL=${LOG_LEVEL:-"DEBUG"} # DEBUG, INFO, WARN, ERROR

if ! readonly -p | grep -q "declare -r LOG_LEVEL_TRACE="; then
    declare -r LOG_LEVEL_TRACE=-1
    declare -r LOG_LEVEL_DEBUG=0
    declare -r LOG_LEVEL_INFO=1
    declare -r LOG_LEVEL_WARN=2
    declare -r LOG_LEVEL_ERROR=3
fi

has_24bit_color_support() {
    [[ "${COLORTERM:-}" == "truecolor" || "${COLORTERM:-}" == "24bit" ]] || 
        [[ "${TERM:-}" == *-direct ]] || [[ "${TERM:-}" == *-24bit ]]
}

if has_24bit_color_support; then
    if ! readonly -p | grep -q "declare -r RED="; then
        declare -r RED='\033[38;2;243;139;168m'
        declare -r YELLOW='\033[38;2;249;226;175m'
        declare -r BLUE='\033[38;2;137;180;250m'
        declare -r GREEN='\033[38;2;166;227;161m'
        declare -r RESET='\033[0m'
        declare -r GREY='\033[38;2;186;194;222m'
        declare -r PURPLE='\033[38;2;203;166;247m'
    fi
else
    if ! readonly -p | grep -q "declare -r RED="; then
        declare -r RED='\033[0;31m'
        declare -r YELLOW='\033[0;33m'
        declare -r BLUE='\033[0;34m'
        declare -r GREEN='\033[0;32m'
        declare -r RESET='\033[0m'
        declare -r GREY='\033[0;37m'
        declare -r PURPLE='\033[0;35m'
    fi
fi

if ! readonly -p | grep -q "declare -r BOLD="; then
    declare -r BOLD='\033[1m'
    declare -r UNDERLINE='\033[4m'
fi

to_uppercase() {
    echo "$1" | tr '[:lower:]' '[:upper:]'
}

get_log_level_value() {
    local log_level_upper
    log_level_upper=$(to_uppercase "${LOG_LEVEL}")
    
    case "${log_level_upper}" in
        TRACE) echo $LOG_LEVEL_TRACE ;;
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

log_trace() { 
    local level_value=$(get_log_level_value)
    if [[ -n "$level_value" && "$level_value" -le "$LOG_LEVEL_TRACE" ]]; then
        printf "${PURPLE}[TRACE]${RESET} %s\n" "$*" >&2
    fi
}

log_info() { 
    local level_value=$(get_log_level_value)
    if [[ -n "$level_value" && "$level_value" -le "$LOG_LEVEL_INFO" ]]; then
        printf "${BLUE}[INFO]${RESET} %s\n" "$*" >&2
    fi
}

log_error() { 
    local level_value=$(get_log_level_value)
    if [[ -n "$level_value" && "$level_value" -le "$LOG_LEVEL_ERROR" ]]; then
        printf "${RED}${BOLD}[ERROR]${RESET} %s\n" "$*" >&2
    fi
}

log_warn() { 
    local level_value=$(get_log_level_value)
    if [[ -n "$level_value" && "$level_value" -le "$LOG_LEVEL_WARN" ]]; then
        printf "${YELLOW}[WARN]${RESET} %s\n" "$*" >&2
    fi
}

log_debug() { 
    local level_value=$(get_log_level_value)
    if [[ -n "$level_value" && "$level_value" -le "$LOG_LEVEL_DEBUG" ]]; then
        printf "${GREY}[DEBUG]${RESET} %s\n" "$*" >&2
    fi
}

log_success() {
    printf "${GREEN}${BOLD}[SUCCESS]${RESET} %s\n" "$*" >&2
}

log_command() {
    printf "${GREEN}[CMD]${RESET} %s\n" "$*" >&2
    
    local cmds_dir
    cmds_dir="$(dirname "${CMDS_FILE}")"
    
    if ! mkdir -p "${cmds_dir}" 2>/dev/null; then
        log_warn "Cannot create command log directory: ${cmds_dir}"
        return 0
    fi
    
    if ! printf '%s\n' "$*" >> "${CMDS_FILE}" 2>/dev/null; then
        log_warn "Cannot write to command log file: ${CMDS_FILE}"
    fi
}

ensure_log_directory() {
    if [[ ! -d "${LOGS_DIR}" ]]; then
        if ! mkdir -p "${LOGS_DIR}" 2>/dev/null; then
            log_warn "Cannot create logs directory: ${LOGS_DIR}"
            return 1
        fi
    fi
    return 0
}

cleanup_logs() {
    log_debug "Cleaning up log files"
    if [[ -f "${CMDS_FILE}" ]] && [[ -s "${CMDS_FILE}" ]]; then
        if ! mkdir -p "${LOGS_DIR}" 2>/dev/null; then
            log_warn "Cannot create logs directory: ${LOGS_DIR}"
            return 0
        fi
        
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        
        if ! mv "${CMDS_FILE}" "${LOGS_DIR}/commands.${timestamp}.log" 2>/dev/null; then
            log_warn "Cannot move commands file to logs directory"
        fi
    fi
    return 0
}

rotate_logs() {
    log_debug "Rotating logs (keeping ${MAX_LOGS} most recent)"
    [[ -d "${LOGS_DIR}" ]] || return 0

    local pattern file_count
    for pattern in "*-install.log" "*-process.log" "commands.*.log" "build.*.log"; do
        file_count=$(find "${LOGS_DIR}" -name "${pattern}" 2>/dev/null | wc -l) || continue
        if [[ ${file_count} -gt ${MAX_LOGS} ]]; then
            log_debug "Removing old ${pattern} logs (keeping ${MAX_LOGS} of ${file_count})"
            find "${LOGS_DIR}" -name "${pattern}" -printf "%T@ %p\n" 2>/dev/null |
                sort -n |
                head -n "$(( file_count - MAX_LOGS ))" |
                cut -d' ' -f2- |
                xargs -r rm -f
        fi
    done
    return 0
}

remove_temp_files() {
    log_debug "Removing temporary files"
    if [[ -f "${CMDS_FILE}" ]]; then
        rm -f "${CMDS_FILE}" 2>/dev/null || log_warn "Cannot remove commands file: ${CMDS_FILE}"
    fi
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides logging utility functions."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 