#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_OSSUPPORT_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _OSSUPPORT_FUNCTIONS_SH_=1

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

ask_for_continue() {
    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode active - continuing automatically"
        return 0
    fi

    local response
    while true; do
        read -rp "Do you want to continue? [y/N] " response
        case ${response,,} in
            y|yes) return 0;;
            n|no|"") return 1;;
            *) log_error "Please enter 'y' for yes or 'n' for no";;
        esac
    done
}

read_with_timeout() {
    local prompt="$1" 
    local default="$2" 
    local timeout="${3:-10}"

    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode active - using default: ${default}"
        echo "${default}"
        return 0
    fi

    if read -rt "${timeout}" -p "${prompt}" response; then
        echo "${response:-$default}"
    else
        log_warn "Input timeout after ${timeout}s - using default: ${default}"
        echo "${default}"
    fi
}

validate_input() {
    local prompt="$1"
    local default="$2"
    local validator="$3"
    local error_msg="${4:-Input validation failed - please try again}"
    local response
    
    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode active - using default: ${default}"
        echo "${default}"
        return 0
    fi
    
    while true; do
        read -rp "${prompt} [default: ${default}] " response
        response="${response:-$default}"
        
        if [[ -z "${validator}" ]] || eval "${validator} '${response}'"; then
            echo "${response}"
            return 0
        else
            log_error "${error_msg}"
        fi
    done
}

get_distro_type() {
    local distro_type="unknown"

    if [[ -f /etc/os-release ]]; then
        source <(grep -E "^(ID|VERSION_ID)=" /etc/os-release)
        distro_type="${ID:-unknown}"
        export DISTRO_VERSION="${VERSION_ID:-unknown}"
    elif [[ -f /etc/redhat-release ]]; then
        distro_type="redhat"
    elif [[ -f /etc/debian_version ]]; then
        distro_type="debian"
    elif [[ -f /etc/arch-release ]]; then
        distro_type="arch"
    elif [[ -f /etc/alpine-release ]]; then
        distro_type="alpine"
    fi

    echo "${distro_type}"
}

get_os_name() {
    uname -s | tr '[:upper:]' '[:lower:]'
}

get_cpu_count() {
    local cpu_count
    
    if command -v nproc &>/dev/null; then
        cpu_count=$(nproc)
    elif [[ "$(get_os_name)" == "darwin" ]]; then
        cpu_count=$(sysctl -n hw.ncpu)
    else
        cpu_count=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo 4)
    fi
    
    echo "${cpu_count:-4}"
}

execute_with_sudo() {
    if [[ "$(get_os_name)" == "linux" ]] && [[ "$(id -u)" -ne 0 ]]; then
        if ! command -v sudo &>/dev/null; then
            log_error "sudo command not found and not running as root - cannot execute privileged command"
            return 1
        fi
        command sudo "$@"
    else
        command "$@"
    fi
}

execute_with_ksu() {
    if [[ "$(get_os_name)" == "linux" ]] && [[ "$(id -u)" -ne 0 ]]; then
        if ! command -v ksu &>/dev/null; then
            log_error "ksu command not found and not running as root - cannot execute privileged command"
            return 1
        fi
        command ksu "$@"
    else
        command "$@"
    fi
}


is_user_allowed() {
    local current_user=$(whoami)
    
    if [[ -z "${ALLOW_USERS}" ]]; then
        return 1
    fi
    
    IFS=',' read -ra user_list <<< "${ALLOW_USERS}"
    for user in "${user_list[@]}"; do
        if [[ "${current_user}" == "${user}" ]]; then
            return 0
        fi
    done
    return 1
}

is_host_allowed() {
    local current_host=$(hostname -s)
    
    if [[ -z "${ALLOW_HOSTS}" ]]; then
        return 1
    fi

    IFS=',' read -ra host_list <<< "${ALLOW_HOSTS}"
    for host in "${host_list[@]}"; do
        if [[ "${current_host}" == "${host}" ]]; then
            return 0
        fi
    done
    return 1
}


# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides common utility functions."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi
