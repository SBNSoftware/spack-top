#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_COMMON_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
_COMMON_FUNCTIONS_SH_=1

NON_INTERACTIVE=${NON_INTERACTIVE:-false}
VERBOSE=${VERBOSE:-true}
WITH_CLEANUP=${WITH_CLEANUP:-true}
LOGS_DIR=${LOGS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/logs"}
CMDS_FILE=${CMDS_FILE:-"${LOGS_DIR}/commands.log"}
MAX_LOGS=${MAX_LOGS:-10}
LOG_LEVEL=${LOG_LEVEL:-"DEBUG"} # DEBUG, INFO, WARN, ERROR
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

if ! readonly -p | grep -q "declare -r COMMON_ENVFILE="; then
    readonly COMMON_ENVFILE=${COMMON_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}
fi

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
    
    if [[ "$(get_log_level_value)" -le $LOG_LEVEL_DEBUG ]]; then
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
    
    if [[ -d "${LOGS_DIR}" ]] && [[ -w "${LOGS_DIR}" ]]; then
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local error_log="${LOGS_DIR}/error_${timestamp}.log"
        
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

declare -a __cleanup_functions=(
    remove_temp_files
    close_open_handles
    reset_signal_handlers
    cleanup_logs
    rotate_logs
)

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
            if ! "$func"; then
                log_warn "Cleanup function $func failed"
            fi
        done
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

load_build_config() {
    local config_file="$1"
    local var_list="$2"
    local -a required_vars=()
    
    if [[ -n "${var_list}" ]]; then
        IFS=':' read -ra required_vars <<< "${var_list}"
    else
        required_vars=("${@:2}")
    fi

    if [[ ! -f "${config_file}" ]]; then
        log_error "Config file not found: ${config_file}"
        return 1
    fi

    log_info "Loading configuration from ${config_file}"
    source "${config_file}"

    local missing_vars=0
    for var in "${required_vars[@]}"; do
        if ! declare -p "${var}" &>/dev/null; then
            log_error "Required variable '${var}' not defined in config file"
            missing_vars=$((missing_vars + 1))
            continue
        fi
        
        local value
        eval "value=\${${var}}"
        
        if [[ -z "${value}" ]]; then
            log_error "Required variable '${var}' is empty in config file"
            missing_vars=$((missing_vars + 1))
        else
            export "${var}"
            readonly "${var}" 2>/dev/null || true
        fi
    done

    if [[ ${missing_vars} -gt 0 ]]; then
        return 1
    fi
    
    return 0
}

get_qualifier_e_version() {
    local gcc_version="$1"

    case "$gcc_version" in
        13.1.0|13.1.*) echo "e28" ;;
        12.1.0|12.1.*) echo "e26" ;;
        *)
            log_warn "Unknown GCC version: ${gcc_version}, defaulting to e28"
            log_debug "Supported GCC versions: 13.1.0 (e28), 12.1.0 (e26)"
            echo "e28" ;;
    esac
}

get_version() {
    local package="$1"
    local quals="$2"
    local gcc_version="$3"
    local default_version="$4"

    if [[ -z "${default_version}" ]]; then
        local cmd="spack find --no-groups ${package} ${quals} %gcc@${gcc_version} arch=${SPACK_ARCH}"
        log_command "${cmd}"
        
        local find_output
        if ! find_output=$(eval "${cmd}" 2>/dev/null); then
            log_warn "No versions found for ${package} - using empty default"
            default_version=""
        else
            default_version=$(echo "${find_output}" | grep -o '@[0-9a-z._-]*' | 
                              sed 's/^@//' | sort -rV | head -1)
            
            if [[ -z "${default_version}" ]]; then
                log_warn "No versions found for ${package} - using empty default"
            else
                log_debug "Found default version ${default_version} for ${package}"
            fi
        fi
    fi
    
    read_with_timeout "Enter version for ${package} (default: ${default_version:-none}): " "${default_version}"
}

parse_arguments() {
    remaining_args=()
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)
                NON_INTERACTIVE=true
                log_debug "Non-interactive mode enabled"
                shift
                ;;
            --verbose)
                VERBOSE=true
                LOG_LEVEL="DEBUG"
                log_debug "Verbose logging enabled"
                shift
                ;;
            --quiet)
                VERBOSE=false
                LOG_LEVEL="WARN"
                shift
                ;;
            --with-cleanup)
                WITH_CLEANUP=true
                log_debug "Cleanup enabled"
                shift
                ;;
            --no-cleanup)
                WITH_CLEANUP=false
                log_debug "Cleanup disabled"
                shift
                ;;
            --log-dir=*)
                LOGS_DIR="${1#*=}"
                log_debug "Log directory set to ${LOGS_DIR}"
                shift
                ;;
            --config=*)
                if ! readonly -p | grep -q "declare -r COMMON_ENVFILE="; then
                    COMMON_ENVFILE="${1#*=}"
                    log_debug "Config file set to ${COMMON_ENVFILE}"
                else
                    log_warn "Cannot change COMMON_ENVFILE - variable is readonly"
                fi
                shift
                ;;
            --test)
                RUN_TESTS=true
                log_debug "Test mode enabled"
                shift
                ;;
            -h|--help)
                print_usage "$(basename "$0")" "" "" "" ""
                exit 0
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage "$(basename "$0")" "" "" "" ""
                exit 1
                ;;
            *)
                remaining_args+=("$1")
                shift
                ;;
        esac
    done
    
    log_debug "Remaining arguments: ${remaining_args[*]:-none}"
}

print_usage() {
    local script_name="${1:-$(basename "$0")}"
    local description="${2:-"Build and publish packages to buildcache"}"
    local custom_options="${3:-""}"
    local custom_args="${4:-""}"
    local custom_env="${5:-""}"
    
    cat << EOF
${BOLD}Usage:${RESET} ${script_name} [OPTIONS] [GCC_VERSION] [VERSIONS...]

${description}

${BOLD}Options:${RESET}
    -h, --help          Show this help message and exit
    --non-interactive   Run in non-interactive mode (use defaults for all prompts)
    --verbose           Enable verbose output (debug level logging)
    --quiet             Reduce logging output (warnings and errors only)
    --with-cleanup      Enable cleanup on exit (default)
    --no-cleanup        Disable cleanup on exit
    --log-dir=DIR       Specify log directory path
    --config=FILE       Specify configuration file path
    --test              Run script test suite
${custom_options}

${BOLD}Arguments:${RESET}
    GCC_VERSION         GCC version to use (12.1.0 or 13.1.0, default: 13.1.0)
${custom_args}

${BOLD}Environment Variables:${RESET}
    SOFTWARE_BASE       Base directory for software (default: /daq/software)
    SPACK_DIR           Spack directory (default: \$SOFTWARE_BASE/spack_packages/spack)
    SPACK_VERSION       Spack version (default: v1.0.1.sbnd)
    SPACK_MIRROR_BASE   Mirror base directory (default: \$SOFTWARE_BASE/spack_mirrors/sbndaq-suite)
    VERBOSE             Set to true for verbose output
    LOG_LEVEL           Set to DEBUG, INFO, WARN, or ERROR (default: INFO)
    NON_INTERACTIVE     Set to true for non-interactive mode
    WITH_CLEANUP        Set to true to enable cleanup on exit
${custom_env}

${BOLD}Examples:${RESET}
    ${script_name} --verbose
    ${script_name} --non-interactive 12.1.0
    ${script_name} --config=/path/to/custom.env
    ${script_name} --test
EOF
}

test_common_functions_main() {
    trap 'echo "ERROR: Line $LINENO: Command \"$BASH_COMMAND\" failed with exit code $?"; exit 1' ERR
    NON_INTERACTIVE=true
    log_info "Testing common-functions.sh functionality"
    local test_dir=$(mktemp -d "/tmp/common-functions-test-XXXXXX")
    
    log_info "== Testing Logging Functions =="
    log_debug "Debug message test"
    log_info "Info message test"
    log_warn "Warning message test"
    log_error "Error message test (not a real error)"
    log_success "Success message test"
    log_command "echo 'Test command'"
    
    log_info "== Testing Directory and Log Management =="
    LOGS_DIR="${test_dir}/logs"
    CMDS_FILE="${LOGS_DIR}/commands.log"
    ensure_log_directory
    
    log_info "== Testing System Detection Functions =="
    local os_name=$(get_os_name)
    local distro_type=$(get_distro_type)
    local cpu_count=$(get_cpu_count)
    log_info "OS: ${os_name}, Distribution: ${distro_type}, CPU count: ${cpu_count}"
    
    log_info "== Testing User Interaction Functions =="
    if [[ "${NON_INTERACTIVE}" != "true" ]]; then
        is_number() { [[ "$1" =~ ^[0-9]+$ ]]; }
        local user_input=$(validate_input "Enter a number" "42" "is_number")
        if ask_for_continue; then
            log_info "User chose to continue"
        fi
        local timeout_input=$(read_with_timeout "Enter something (5s timeout)" "default" 5)
    else
        log_info "Skipping interactive tests in non-interactive mode"
    fi
    
    log_info "== Testing Configuration Loading =="
    local test_config_file="${test_dir}/test_config.env"
    cat > "${test_config_file}" << EOF
TEST_VAR1="Value 1"
TEST_VAR2="Value 2"
TEST_VAR3=""
TEST_VAR4="Value 4"
TEST_VAR5="Value 5"
EOF
    
    log_info "== Testing Version Functions =="
    local qualifier_e28=$(get_qualifier_e_version "13.1.0")
    local qualifier_e26=$(get_qualifier_e_version "12.1.0")
    
    rm -rf "${test_dir}"
    log_success "All tests completed successfully"
    trap - ERR
}

main() {
    parse_arguments "$@"
    
    if [[ "${RUN_TESTS:-false}" == "true" ]]; then
        test_common_functions_main
        exit $?
    fi
    
    log_info "This script provides common functions and should be sourced, not executed directly"
    log_info "Run with --test flag to execute tests"
    exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    parse_arguments "$@"
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi
