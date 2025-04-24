#!/usr/bin/env bash

#set -o errexit
#set -o nounset
#set -o pipefail

[[ "${_RSYNC_SH_:-0}" -eq 1 ]] && return 0
declare -r _RSYNC_SH_=1

readonly COMMON_ENVFILE=${COMMON_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}
readonly COMMON_CONFFILE=${COMMON_CONFFILE:-"$(dirname "${BASH_SOURCE[0]}")/${COMMON_ENVFILE}"}

export NON_INTERACTIVE=${NON_INTERACTIVE:-false}
export VERBOSE=${VERBOSE:-true}
export WITH_CLEANUP=${WITH_CLEANUP:-true}
export LOGS_DIR=${LOGS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/logs"}
export CMDS_FILE=${CMDS_FILE:-"${LOGS_DIR}/rsync-commands.log"}
export MAX_LOGS=${MAX_LOGS:-10}
export DRY_RUN=${DRY_RUN:-0}

#export SSH_CONTROL_PATH=${SSH_CONTROL_PATH:-"~/.ssh/control-%r@%h:%p"}
#export SSH_OPTIONS=${SSH_OPTIONS:-" -T -o ControlMaster=auto -o ControlPath=${SSH_CONTROL_PATH} -o ControlPersist=30m -o ServerAliveInterval=60 -o ServerAliveCountMax=5 "}

export SSH_OPTIONS=""

declare -a remaining_args=()
declare -a ___cleanup_functions=(
    remove_temp_files
    close_open_handles
    reset_signal_handlers
    cleanup_logs
    rotate_logs
)

declare -r RED='\033[38;2;243;139;168m'
declare -r YELLOW='\033[38;2;249;226;175m'
declare -r BLUE='\033[38;2;137;180;250m'
declare -r GREEN='\033[38;2;166;227;161m'
declare -r RESET='\033[0m'
declare -r GREY='\033[38;2;186;194;222m'

log_info() { printf "${BLUE}[INFO]${RESET} %s\n" "$*" >&2; }
log_error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }
log_warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*" >&2; }
log_debug() { [[ "${VERBOSE}" == true ]] && printf "${GREY}[DEBUG]${RESET} %s\n" "$*" >&2; }
log_command() {
    printf "${GREEN}[CMD]${RESET} %s\n" "$*" >&2
    mkdir -p "$(dirname "${CMDS_FILE}")" || {
        log_warn "Failed to create directory for commands file"
        return 0
    }
    printf '%s\n' "$*" >> "${CMDS_FILE}" || log_warn "Failed to write to commands file"
}

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Mirror directories and files listed in rsync list file to a remote host over SSH using rsync.
This utility securely synchronizes files and directories between systems using the SSH protocol as a transport.
It reads paths from a configured list file, creates necessary directories on the target host,
and performs incremental transfers that minimize bandwidth usage. The script supports SSH jump hosts
for reaching hosts behind firewalls, handles both files and directories appropriately,
logs all operations for audit purposes, and provides detailed progress statistics.

Options:
    -h, --help          Show this help message
    --non-interactive   Run in non-interactive mode
    --verbose           Enable verbose output
    --with-cleanup      Enable cleanup on exit
    -l, --list FILE     Specify a custom list file
    -g, --gateway HOST  Specify SSH gateway host
    -t, --target HOST   Specify SSH target host
    -u, --user USER     Specify SSH username
    --dry-run           Show what would be transferred without actually doing it

Environment Variables:
    SSH_GATEWAY_HOST    Gateway host to use for SSH jump
    SSH_TARGET_HOST     Target host to rsync files to
    SSH_USER            SSH username for connections
    RSYNC_LIST          Path to the list file containing paths to sync
    LOGS_DIR            Directory to store logs
    MAX_LOGS            Maximum number of log files to keep
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -n "${1:-}" ]] && [[ "$1" =~ ^(-h|--help)$ ]] && { print_usage; exit 0; }
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && log_info "$(basename "${BASH_SOURCE[0]}") is being sourced..."

load_build_config() {
    if [[ ! -f "${COMMON_CONFFILE}" ]]; then
        log_error "Configuration file not found: ${COMMON_CONFFILE}"
        return 1
    fi

    local required_vars=(
        "SSH_GATEWAY_HOST"
        "SSH_TARGET_HOST"
        "SSH_USER"
        "RSYNC_LIST"
    )

    for var in "${required_vars[@]}"; do
        if ! declare -p "$var" &>/dev/null; then
            continue
        fi
        if [[ -z "${!var}" ]]; then
            log_warn "Required configuration variable not set: ${var}"
        fi
    done

    log_info "Loading configuration from ${COMMON_CONFFILE}"
    source "${COMMON_CONFFILE}"

    for var in "${required_vars[@]}"; do
        if ! declare -p "$var" &>/dev/null; then
            log_error "Required configuration variable not declared: ${var}"
            continue
        fi
        if [[ -z "${!var}" ]]; then
            log_error "Required configuration variable not set: ${var}"
            return 1
        fi
    done

    for var in "${required_vars[@]}"; do
        export "${var}"
        readonly "${var}"
    done
}

handle_error() {
    local exit_code="$1" line_no="$2" command="$3"
    log_error "Error occurred:"
    log_error "Command: ${command}"
    log_error "Line number: ${line_no}"
    log_error "Exit code: ${exit_code}"
    cleanup_on_exit
    exit "${exit_code}"
}

setup_signal_handlers() {
    log_debug "Setting up signal handlers..."
    trap 'handle_sigint' SIGINT
    trap 'handle_sigterm' SIGTERM
    trap 'handle_sigquit' SIGQUIT
    trap 'handle_sighup' SIGHUP
    trap 'handle_sigchild' SIGCHLD
    trap 'cleanup_on_exit' EXIT
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
}

handle_sigint() {
    log_warn "Caught SIGINT (Ctrl+C)"
    cleanup_on_exit
    exit 130
}

handle_sigterm() {
    log_warn "Caught SIGTERM"
    cleanup_on_exit
    exit 143
}

handle_sigquit() {
    log_warn "Caught SIGQUIT"
    cleanup_on_exit
    exit 131
}

handle_sighup() {
    log_warn "Caught SIGHUP - connection may have been closed"
    return 0
}

handle_sigchild() {
    log_warn "Caught SIGCHLD - connection may have been closed"
    return 0
}

cleanup_on_exit() {
    [[ "${WITH_CLEANUP}" == true ]] || return 0
    log_debug "Performing cleanup..."
    for func in "${___cleanup_functions[@]}"; do
        if ! "$func"; then
            log_warn "Cleanup function $func failed"
        fi
    done
}

remove_temp_files() {
    log_debug "Removing temporary files..."
    [[ -f "${CMDS_FILE}" ]] && rm -f "${CMDS_FILE}" || log_warn "Failed to remove commands file"
    return 0
}

close_open_handles() {
    log_debug "Closing open file handles..."
    exec 3>&- 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
    return 0
}

reset_signal_handlers() {
    log_debug "Resetting signal handlers..."
    trap - SIGINT SIGTERM SIGQUIT EXIT ERR
    return 0
}

cleanup_logs() {
    log_debug "Cleaning up logs..."
    if [[ -f "${CMDS_FILE}" ]] && [[ -s "${CMDS_FILE}" ]]; then
        mkdir -p "${LOGS_DIR}" || {
            log_warn "Failed to create logs directory: ${LOGS_DIR}"
            return 0
        }
        mv "${CMDS_FILE}" "${LOGS_DIR}/commands.$(date +%Y%m%d_%H%M%S).log" || {
            log_warn "Failed to move commands file to logs directory"
            return 0
        }
    fi
    return 0
}

rotate_logs() {
    log_debug "Rotating logs to keep only ${MAX_LOGS} recent logs..."
    [[ -d "${LOGS_DIR}" ]] || return 0

    local pattern file_count
    for pattern in "*-rsync.log" "commands.*.log" "sync.*-rsync.log"; do
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

ensure_log_directory() {
    if [[ ! -d "${LOGS_DIR}" ]]; then
        mkdir -p "${LOGS_DIR}" || {
            log_warn "Failed to create logs directory: ${LOGS_DIR}"
            return 1
        }
    fi
    return 0
}

ask_for_continue() {
    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode, continuing automatically"
        return 0
    fi

    local response
    while true; do
        read -rp "Do you want to continue? [y/N] " response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) log_error "Please answer y or n.";;
        esac
    done
}

parse_arguments() {
    remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --with-cleanup) WITH_CLEANUP=true; shift ;;
            -l|--list)
                shift
                RSYNC_LIST="$1"; shift ;;
            -g|--gateway)
                shift
                SSH_GATEWAY_HOST="$1"; shift ;;
            -t|--target)
                shift
                SSH_TARGET_HOST="$1"; shift ;;
            -u|--user)
                shift
                SSH_USER="$1"; shift ;;
            --dry-run) DRY_RUN=1; shift ;;
            -h|--help) print_usage; exit 0 ;;
            *) remaining_args+=("$1"); shift ;;
        esac
    done
}

test_ssh_connection() {
    local ssh_gateway="$1"
    local ssh_target="$2"
    local ssh_user="$3"

    local ssh_cmd="ssh ${SSH_OPTIONS} -A -J ${ssh_user}@${ssh_gateway} ${ssh_user}@${ssh_target}"

    log_info "Testing SSH connection to ${ssh_target} via ${ssh_gateway}"
    log_command "${ssh_cmd} \"echo 'Connection test'\""

    if ! ${ssh_cmd} "echo 'Connection test'" &>/dev/null; then
        log_error "Cannot establish SSH connection through gateway to target host"
        return 1
    fi

    log_info "SSH connection successful"
    return 0
}

ensure_target_directory() {
    local dir_path="$1"
    local ssh_gateway="$2"
    local ssh_target="$3"
    local ssh_user="$4"

    local ssh_cmd="ssh ${SSH_OPTIONS} -A -J ${ssh_user}@${ssh_gateway} ${ssh_user}@${ssh_target}"

    log_debug "Ensuring directory exists on target: ${dir_path}"

    local mkdir_cmd="${ssh_cmd} \"mkdir -p \\\"${dir_path}\\\"\""
    log_command "${mkdir_cmd}"

    if ! eval "${mkdir_cmd}" 2>/dev/null; then
        log_error "Failed to create directory on target: ${dir_path}"
        return 1
    fi

    return 0
}

process_directory() {
    local entry="$1"
    local ssh_gateway="$2"
    local ssh_target="$3"
    local ssh_user="$4"

    log_info "Processing directory: ${entry}"
    #if ! ensure_target_directory "${entry}" "${ssh_gateway}" "${ssh_target}" "${ssh_user}"; then
    #    return 1
    #fi

    local rsync_options=" -avh"
    [[ "${DRY_RUN}" -eq 1 ]] && rsync_options+=" --dry-run"
    rsync_options+=" -e"

    local rsync_cmd="rsync ${rsync_options} \"ssh ${SSH_OPTIONS} -A -J ${ssh_user}@${ssh_gateway}\" \"${entry}/\" \"${ssh_user}@${ssh_target}:${entry}/\" "
    log_command "${rsync_cmd}"
    
    if ! output=$(eval "${rsync_cmd}" 2>&1) || [[ $output =~ "error" && ! $output =~ "Killed by signal 1" ]]; then
        log_error "Failed to rsync directory: ${entry}"
        log_error "Output: ${output}"
        return 1
    fi

    log_info "Successfully synced directory: ${entry}"
    return 0
}

process_file() {
    local entry="$1"
    local ssh_gateway="$2"
    local ssh_target="$3"
    local ssh_user="$4"

    log_info "Processing file: ${entry}"

    local parent_dir=$(dirname "${entry}")
    if ! ensure_target_directory "${parent_dir}" "${ssh_gateway}" "${ssh_target}" "${ssh_user}"; then
        return 1
    fi

    local rsync_options="-ah"
    [[ "${DRY_RUN}" -eq 1 ]] && rsync_options+=" --dry-run"
    rsync_options+=" -e "

    local rsync_cmd="rsync ${rsync_options} \"ssh ${SSH_OPTIONS} -A -J ${ssh_user}@${ssh_gateway}\" \"${entry}\" \"${ssh_user}@${ssh_target}:${entry}\" "
    log_command "${rsync_cmd}"

    if ! output=$(eval "${rsync_cmd}" 2>&1) || [[ $output =~ "error" && ! $output =~ "Killed by signal 1" ]]; then
        log_error "Failed to rsync file: ${entry}"
        log_error "Output: ${output}"
        return 1
    fi

    log_info "Successfully synced file: ${entry}"
    return 0
}

process_rsync_list() {
    local list_file="$1"
    local ssh_gateway="$2"
    local ssh_target="$3"
    local ssh_user="$4"

    if [[ ! -f "${list_file}" ]]; then
        log_error "File ${list_file} does not exist"
        return 1
    fi

    local success_count=0
    local error_count=0
    local skipped_count=0

    while IFS= read -r entry || [[ -n "${entry}" ]]; do
        [[ -z "${entry}" || "${entry}" =~ ^[[:space:]]*# ]] && continue
        entry=$(echo "${entry}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        entry="${entry%/}"

        if [[ -d "${entry}" ]]; then
            if process_directory "${entry}" "${ssh_gateway}" "${ssh_target}" "${ssh_user}"; then
                ((success_count++))
            else
                ((error_count++))
            fi
        elif [[ -f "${entry}" ]]; then
            if process_file "${entry}" "${ssh_gateway}" "${ssh_target}" "${ssh_user}"; then
                ((success_count++))
            else
                ((error_count++))
            fi
        else
            log_warn "Entry does not exist locally: ${entry}"
            ((skipped_count++))
        fi

    done < "${list_file}"

    log_info "Rsync process completed"
    log_info "Summary: ${success_count} successful, ${error_count} failed, ${skipped_count} skipped"

    [[ "${error_count}" -gt 0 ]] && return 1 || return 0
}

main() {
    if [[ ! -f "${COMMON_CONFFILE}" ]]; then
        log_info "Creating example configuration file: ${COMMON_CONFFILE}..."
        cat > "${COMMON_CONFFILE}" << EOF
SSH_GATEWAY_HOST=gateway.example.com
SSH_TARGET_HOST=target.example.com
SSH_USER="artdaq"
RSYNC_LIST="sync-list.txt"
EOF
        log_info "A new configuration file has been created at ${COMMON_CONFFILE}"
        log_info "Please edit this file with your actual configuration values."

        if [[ "${NON_INTERACTIVE}" == false ]]; then
            if ask_for_continue; then
                log_info "Continuing with example configuration (will likely fail without editing)"
            else
                log_info "Exiting to allow configuration file editing"
                return 1
            fi
        else
            log_warn "Non-interactive mode enabled, but configuration needs to be set up"
            return 1
        fi
    fi

    parse_arguments "$@"
    setup_signal_handlers

    log_debug "Loading ${COMMON_CONFFILE}"
    if ! load_build_config; then
        log_error "Failed to load ${COMMON_CONFFILE}"
        return 1
    fi

    if ! ensure_log_directory; then
        log_warn "Failed to create log directory, continuing anyway"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local rsync_log="${LOGS_DIR}/sync.${timestamp}-rsync.log"
    exec > >(tee -a "${rsync_log}") 2>&1

    log_info "Starting rsync mirroring process, logging to ${rsync_log}"
    log_info "Using gateway: ${SSH_GATEWAY_HOST} and target: ${SSH_TARGET_HOST}"

    if ! test_ssh_connection "${SSH_GATEWAY_HOST}" "${SSH_TARGET_HOST}" "${SSH_USER}"; then
        log_error "SSH connection test failed"
        return 1
    fi

    if ! process_rsync_list "${RSYNC_LIST}" "${SSH_GATEWAY_HOST}" "${SSH_TARGET_HOST}" "${SSH_USER}"; then
        log_warn "Some files or directories failed to sync"
        return 1
    fi

    log_info "Rsync mirroring completed successfully"
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    parse_arguments "$@"
    log_debug "Finished sourcing $(basename "${BASH_SOURCE[0]}")..."
fi

