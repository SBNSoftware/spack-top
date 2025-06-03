#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_SIGNAL_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _SIGNAL_FUNCTIONS_SH_=1

# Source logging functions if they exist
if [[ -f "$(dirname "${BASH_SOURCE[0]}")/logging-functions.sh" ]]; then
    source "$(dirname "${BASH_SOURCE[0]}")/logging-functions.sh"
else
    echo "WARNING: logging-functions.sh not found, using basic logging" >&2
    log_debug() { echo "[DEBUG] $*" >&2; }
    log_info() { echo "[INFO] $*" >&2; }
    log_warn() { echo "[WARN] $*" >&2; }
    log_error() { echo "[ERROR] $*" >&2; }
fi

WITH_CLEANUP=${WITH_CLEANUP:-true}

declare -a __cleanup_functions=(
    remove_temp_files
    close_open_handles
    reset_signal_handlers
    cleanup_logs
    rotate_logs
)

setup_signal_handlers() {
    log_debug "Setting up signal handlers"
    trap 'handle_sigint' SIGINT
    trap 'handle_sigterm' SIGTERM
    trap 'handle_sigquit' SIGQUIT
    trap 'cleanup_on_exit' EXIT
    trap 'handle_error $? $LINENO "$BASH_COMMAND" "${FUNCNAME[0]:-main}"' ERR
}

handle_sigint() {
    log_warn "Received SIGINT (Ctrl+C)"
    cleanup_on_exit
    exit 130
}

handle_sigterm() {
    log_warn "Received SIGTERM"
    cleanup_on_exit
    exit 143
}

handle_sigquit() {
    log_warn "Received SIGQUIT"
    cleanup_on_exit
    exit 131
}

handle_error() {
    local exit_code="$1" 
    local line_no="$2" 
    local command="$3"
    local func_name="${4:-unknown}"
    
    log_error "Error in ${func_name}() at line ${line_no}"
    log_error "Failed command: ${command}"
    log_error "Exit code: ${exit_code}"
    
    if [[ "$(get_log_level_value 2>/dev/null || echo 1)" -le 0 ]]; then
        log_debug "--- System Information ---"
        log_debug "User: $(whoami)"
        log_debug "Host: $(hostname -f 2>/dev/null || hostname)"
        log_debug "Working directory: $(pwd)"
        log_debug "OS: $(uname -a)"
        
        if command -v free &>/dev/null; then
            log_debug "Memory: $(free -h | grep Mem | awk '{print "Total: "$2", Used: "$3", Free: "$4}')"
        fi
        
        log_debug "Disk space: $(df -h . | tail -n1 | awk '{print $4}') free"
        
        if [[ -n "${SPACK_DIR:-}" ]] && [[ -d "${SPACK_DIR}" ]]; then
            log_debug "Spack directory size: $(du -sh "${SPACK_DIR}" 2>/dev/null | cut -f1)"
        fi
    fi
    
    local i=0
    local -a stack_frames=()
    
    while caller $i > /dev/null 2>&1; do
        local frame=$(caller $i)
        stack_frames+=("  ${frame}")
        ((i++))
    done
    
    if [[ ${#stack_frames[@]} -gt 0 ]]; then
        log_error "Stack trace:"
        for frame in "${stack_frames[@]}"; do
            log_error "${frame}"
        done
    fi
    
    if type -t custom_error_handler &>/dev/null; then
        log_debug "Executing custom error handler"
        custom_error_handler "${exit_code}" "${line_no}" "${command}" "${func_name}"
    fi
    
    if [[ -d "${LOGS_DIR:-./logs}" ]] && [[ -w "${LOGS_DIR:-./logs}" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local error_log="${LOGS_DIR:-./logs}/error_${timestamp}.log"
        
        {
            echo "=== ERROR REPORT ==="
            echo "Timestamp: $(date)"
            echo "Error code: ${exit_code}"
            echo "Error location: ${func_name}() at line ${line_no}"
            echo "Command: ${command}"
            echo "Stack trace:"
            for frame in "${stack_frames[@]}"; do
                echo "  ${frame}"
            done
            echo "Environment variables:"
            env | sort | grep -v -i password | grep -v -i key | grep -v -i secret
            echo "=== END ERROR REPORT ==="
        } > "${error_log}" 2>/dev/null
        
        log_info "Error details saved to ${error_log}"
    fi
    
    cleanup_on_exit
    exit "${exit_code}"
}

add_cleanup_function() {
    local func_name="$1"
    
    if [[ "$(type -t "${func_name}")" != "function" ]]; then
        log_error "Cannot add '${func_name}' to cleanup - function does not exist"
        return 1
    fi
    
    __cleanup_functions+=("${func_name}")
    log_debug "Added ${func_name} to cleanup functions"
    return 0
}

cleanup_on_exit() {
    [[ "${WITH_CLEANUP}" == true ]] || return 0
    log_debug "Running cleanup functions"
    
    if declare -p __cleanup_functions &>/dev/null; then
        for func in "${__cleanup_functions[@]}"; do
            if type -t "${func}" &>/dev/null; then
                if ! "${func}"; then
                    log_warn "Cleanup function $func failed"
                fi
            else
                log_warn "Cleanup function $func not found"
            fi
        done
    fi
}

close_open_handles() {
    log_debug "Closing open file handles"
    for fd in {3..9}; do
        exec {fd}>&- 2>/dev/null || true
    done
    return 0
}

reset_signal_handlers() {
    log_debug "Resetting signal handlers"
    trap - SIGINT SIGTERM SIGQUIT EXIT ERR
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides signal handling utility functions."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 