#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_COMMON_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _COMMON_FUNCTIONS_SH_=1

# Source the logging and signal handling functions
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/logging-functions.sh"
source "${SCRIPT_DIR}/signal-functions.sh"
source "${SCRIPT_DIR}/ossupport-functions.sh"
NON_INTERACTIVE=${NON_INTERACTIVE:-false}
VERBOSE=${VERBOSE:-true}
WITH_CLEANUP=${WITH_CLEANUP:-true}
LOGS_DIR=${LOGS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/logs"}
CMDS_FILE=${CMDS_FILE:-"${LOGS_DIR}/commands.log"}
MAX_LOGS=${MAX_LOGS:-10}
LOG_LEVEL=${LOG_LEVEL:-"DEBUG"} # DEBUG, INFO, WARN, ERROR

if ! readonly -p | grep -q "declare -r COMMON_ENVFILE="; then
    readonly COMMON_ENVFILE=${COMMON_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}
fi

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
            #exclude SPACK_ENVFILE, DEVNAME, and DEFAULT_VERSION from being set as readonly   
            if [[ "${var}" != "SPACK_ENVFILE" && "${var}" != "DEVNAME" && "${var}" != "DEFAULT_VERSION" ]]; then
                readonly "${var}" 2>/dev/null || true
            fi
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

get_s_qualifier() {
    local qualifiers="$1"
    local s_qualifier=$(echo "${qualifiers}" | grep -oP 's=\d+' | cut -d'=' -f2)
    echo "${s_qualifier}"
}

get_cxxstd_qualifier() {
    local qualifiers="$1"
    local cxxstd_qualifier=$(echo "${qualifiers}" | grep -oP 'cxxstd=\d+' | cut -d'=' -f2)
    echo "${cxxstd_qualifier}"
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
            --no-build)
                RUN_BUILD=false
                log_debug "Build disabled"
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
            --activate)
                export ACTIVATE_DAQ_DEVELOPMENT_AREA=true
                log_debug "DAQ development area activation enabled"
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

    export TMPDIR="${TMP:-${HOME}/DAQ_SPACK_DevAreasRAM/tmp}"
    export TMP="${TMPDIR}"
    export TEMP="${TMPDIR}"

    log_debug "Remaining arguments: ${remaining_args[*]:-none}"
}

print_usage() {
    local script_name="${1:-$(basename "$0")}"
    local description="${2:-"Runs common functions"}"
    local custom_options="${3:-""}"
    local custom_args="${4:-""}"
    local custom_env="${5:-""}"
    
    cat << EOF
Usage: ${script_name} [OPTIONS] [GCC_VERSION] [VERSIONS...]

${description}

Options:
    -h, --help          Show this help message and exit
    --non-interactive   Run in non-interactive mode (use defaults for all prompts)
    --verbose           Enable verbose output (debug level logging)
    --quiet             Reduce logging output (warnings and errors only)
    --no-build          Skip package building step
    --config=FILE       Specify configuration file path
${custom_options}


Environment Variables:
    SOFTWARE_BASE       Base directory for software (default: /daq/software)
    SPACK_DIR           Spack directory (default: \$SOFTWARE_BASE/spack_packages/spack)
    SPACK_VERSION       Spack version (default: v1.0.1.sbnd)
    SPACK_MIRROR_BASE   Mirror base directory (default: \$SOFTWARE_BASE/spack_mirrors/sbndaq-suite)
    VERBOSE             Set to true for verbose output
    LOG_LEVEL           Set to DEBUG, INFO, WARN, or ERROR (default: INFO)
    NON_INTERACTIVE     Set to true for non-interactive mode
${custom_env}

Examples:
    ${script_name} --verbose
    ${script_name} --non-interactive
    ${script_name} --config=/path/to/custom.env
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

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi

# Format qualifiers for spack commands
format_spack_qualifiers() {
    local qualifier="$1"
    local cxxstd="$2"
    local result=""
    
    # Handle qualifier
    if [[ -n "${qualifier}" && "${qualifier}" != "none" ]]; then
        # Strip any 's' or 's=' prefix to standardize
        local clean_qualifier="${qualifier#s=}"
        clean_qualifier="${clean_qualifier#s}"
        
        # If it still starts with 's', it might be like 's132'
        if [[ "${clean_qualifier}" == s* ]]; then
            clean_qualifier="${clean_qualifier#s}"
        fi
        
        # Only add the qualifier if it's not empty after cleaning
        if [[ -n "${clean_qualifier}" ]]; then
            result+="s=${clean_qualifier}"
        fi
    fi
    
    # Handle C++ standard
    if [[ -n "${cxxstd}" ]]; then
        # Extract just the number if in c++XX format
        local cxxstd_num="${cxxstd#c++}"
        
        # Add space if we already have a qualifier
        [[ -n "${result}" ]] && result+=" "
        
        result+="cxxstd=${cxxstd_num}"
    fi
    
    echo "${result}"
}

format_path_name() {    
    local path_name="$1"
    local gcc_version="$2"
    local qualifiers="${3:-"s=132 cxxstd=20"}"
    local arch="${4:-"${SPACK_ARCH:-linux-almalinux9-x86_64_v2}"}"
    local delimiter="${5:-"/"}"
    local result="$(echo "${arch}" | cut -d'-' -f2)"

    #if the gcc_version is not empty, then add it to the result
    if [[ -n "${gcc_version}" ]]; then
        result="${result}-gcc${gcc_version}"           
    fi

    #if cxxstd qualifier is not empty, then add it to the rest
    if [[ -n "${qualifiers}" && "${qualifiers}" =~ cxxstd=([^ ]+) ]]; then
        result="${result}-c++${BASH_REMATCH[1]}"
    fi
    #if s qualifier is not empty, then add it to the rest
    if [[ -n "${qualifiers}" && "${qualifiers}" =~ s=([^ ]+) ]]; then
        result="${result}-s${BASH_REMATCH[1]}"
    fi

    #if the result is not empty, then add the file_name to the result
    if [[ -n "${result}" ]]; then
        result="${path_name}${delimiter}${result}"
    fi

    echo "${result}"
}

# Parse qualifiers string into components
parse_spack_qualifiers() {
    local qualifiers_str="$1"
    local -n qual_ref="$2"
    local -n cxx_ref="$3"
    
    # Initialize with empty values
    qual_ref=""
    cxx_ref=""
    
    # Parse qualifier (s=XXX)
    if [[ "${qualifiers_str}" =~ s=([^ ]+) ]]; then
        qual_ref="${BASH_REMATCH[1]}"
    fi
    
    # Parse C++ standard (cxxstd=XX)
    if [[ "${qualifiers_str}" =~ cxxstd=([^ ]+) ]]; then
        cxx_ref="${BASH_REMATCH[1]}"
    fi
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
