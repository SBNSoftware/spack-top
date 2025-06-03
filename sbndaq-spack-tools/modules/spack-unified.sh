#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_SPACK_UNIFIED_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _SPACK_UNIFIED_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/config-functions.sh"
source "${SCRIPT_DIR}/env-functions.sh"
source "${SCRIPT_DIR}/pkg-functions.sh"

# Print usage information for the script
if declare -f print_usage &>/dev/null; then
    unset -f print_usage
fi



print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Sets up a Spack development area for DAQ software development.
Creates a new directory with custom Spack environment, checks out specified
packages for development, and builds them.

Options:
    --dev-name NAME       Set developer name for directory naming (default: XYZ)
    --default-version VER Set specific version instead of latest available
    --non-interactive     Run without user prompts (default: false)
    -h, --help            Display this help message and exit

Examples:
    $(basename "$0") --dev-name ALICE --default-version v1_10_07
EOF
}

# Main function for setting up a development environment
setup_daq_development_area() {
    local pkg_type="${1:-suite}"  # 'suite' or 'proj'
    local config_file="${2:-$(basename "${BASH_SOURCE[0]%.*}").env}"
    shift 2

    # Initialize log directory
    LOGS_DIR="${SPACK_DAQ_AREAS:-${HOME}/DAQ_SPACK_DevAreas}/logs"
    ensure_log_directory
    CMDS_FILE="${LOGS_DIR}/spack_commands.txt"
    
    # Set up signal handlers
    setup_signal_handlers
    
    # Create or verify configuration file
    if ! create_default_config "${config_file}" "${pkg_type}"; then
        log_error "Failed to create or verify configuration file"
        exit 1
    fi
    
    # Set the default value for ACTIVATE_DAQ_DEVELOPMENT_AREA
    export ACTIVATE_DAQ_DEVELOPMENT_AREA=false

    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration from file
    local required_vars="DEVNAME:DAQ_PKG_NAME:DAQ_PKG_VERSIONS:DAQ_PKG_CHECKOUT_PACKAGES:SPACK_SOFTWARE_BASE:SPACK_DIR:SPACK_VERSION:SPACK_MIRROR_BASE:SPACK_DAQ_AREAS:SPACK_PACKAGES_TOP:SPACK_USE_USER_CONFIG:RUN_BUILD:BUILD_THREADS:DEBUG_BUILD:ENABLE_TESTS:ENABLE_GIT_PUSH:ALLOW_HOSTS:ALLOW_USERS"
    if ! load_build_config "${config_file}" "${required_vars}"; then
        log_warn "Using default values due to configuration load failure"
    fi

    # Check if the user is in the ALLOW_USERS list
    if ! is_user_allowed; then
        log_error "User not in ALLOW_USERS list"
        exit 1
    fi

    # Check if the host is in the ALLOW_HOSTS list
    if ! is_host_allowed; then
        log_error "Host not in ALLOW_HOSTS list"
        exit 1
    fi

    # Parse the first element of DAQ_PKG_VERSIONS to get version, qualifier, gcc_version, and cxxstd
    if [[ -z "${DAQ_PKG_VERSIONS}" ]]; then
        log_error "DAQ_PKG_VERSIONS is not defined in configuration"
        exit 1
    fi
    
    IFS=':' read -r VERSION QUALIFIER COMPILER CXXSTD <<< "${DAQ_PKG_VERSIONS%%,*}"
    
    # Set default qualifier to "none" if empty (for proj type)
    if [[ "${pkg_type}" == "proj" && -z "${QUALIFIER}" ]]; then
        QUALIFIER="none"
    fi
    
    # Validate components
    if [[ -z "${VERSION}" || -z "${COMPILER}" || -z "${CXXSTD}" ]]; then
        log_error "Invalid DAQ_PKG_VERSIONS format. Expected: version:qualifier:compiler:standard"
        log_error "Got: VERSION=${VERSION}, QUALIFIER=${QUALIFIER}, COMPILER=${COMPILER}, CXXSTD=${CXXSTD}"
        exit 1
    fi
    
    # Use DEFAULT_VERSION if specified via command line, otherwise use VERSION from DAQ_PKG_VERSIONS
    if [[ -n "${DEFAULT_VERSION}" ]]; then
        VERSION="${DEFAULT_VERSION}"
        log_debug "Using command-line specified version: ${VERSION}"
    else
        log_debug "Using version from DAQ_PKG_VERSIONS: ${VERSION}"
    fi
    
    # Extract GCC version from compiler string (removing "gcc" prefix)
    GCC_VERSION="${COMPILER#gcc}"
    
    # Format C++ standard with c++ prefix if needed
    if [[ ! "${CXXSTD}" == c++* ]]; then
        CXXSTD="c++${CXXSTD}"
    fi
    
    # Format qualifiers for spack commands
    local QUALIFIERS=$(format_spack_qualifiers "${QUALIFIER}" "${CXXSTD}")
    
    log_debug "Parsed values: VERSION=${VERSION}, QUALIFIERS=${QUALIFIERS}, GCC_VERSION=${GCC_VERSION}"
    
    log_debug "Setting up Spack environment with GCC ${GCC_VERSION}"
    echo "# Spack commands executed:" > "${CMDS_FILE}"
    
    # Initialize Spack environment with explicit parameters
    if ! initialize_spack_environment "${SPACK_DIR}" "${SPACK_VERSION}" "${GCC_VERSION}" "${SPACK_MICRO_ARCH}" "${BUILD_THREADS}" "${DEBUG_BUILD}"; then
        log_error "Cannot initialize Spack environment - check Spack installation"
        exit 1
    fi

    # Select package version with explicit parameters
    local version
    version=$(select_package_version "${DAQ_PKG_NAME}" "${QUALIFIER}" "${GCC_VERSION}" "${VERSION}" "${CXXSTD}")
    if [[ -z "${version}" ]]; then
        log_error "Failed to determine package version"
        exit 1
    fi
    
    echo
    log_info "Selected ${DAQ_PKG_NAME} version: ${version}"
    
    # Create directory with date, developer name, and version information
    local date_str
    date_str=$(date +%Y-%m-%d)
    local spack_env_top_dir="DAQ_${date_str}_${DEVNAME}"
    
    # Add package name to directory for 'proj' type
    if [[ "${pkg_type}" == "proj" ]]; then
        spack_env_top_dir="${spack_env_top_dir}_${DAQ_PKG_NAME}"
    fi
    
    # Add version to directory name
    spack_env_top_dir="${spack_env_top_dir}_${version}"

    # Create DAQ areas directory and navigate to it
    if ! mkdir -p "${SPACK_DAQ_AREAS}/"; then
        log_error "Cannot create directory: ${SPACK_DAQ_AREAS}"
        exit 1
    fi
    
    if ! cd "${SPACK_DAQ_AREAS}/"; then
        log_error "Cannot access directory: ${SPACK_DAQ_AREAS}"
        exit 1
    fi

    # Handle existing directory case
    if [[ -d "${spack_env_top_dir}" ]]; then
        local delete_response
        delete_response=$(read_with_timeout "Directory ${spack_env_top_dir} exists. Delete it? [y/N]: " "N")
        
        if [[ ${delete_response,,} == "y" ]]; then
            log_info "Removing existing directory: ${spack_env_top_dir}"
            log_warn "This step may take several minutes depending on NFS system speed"
            
            if ! rm -rf "${SPACK_DAQ_AREAS}/${spack_env_top_dir}"; then
                log_error "Failed to remove directory: ${spack_env_top_dir}"
                exit 1
            fi
            
            if ! setup_development_environment  "${DAQ_PKG_NAME}" "${version}" "${GCC_VERSION}" "${QUALIFIERS}" "${SPACK_ARCH}" "${DAQ_PKG_CHECKOUT_PACKAGES}" "${spack_env_top_dir}"; then
                log_error "Failed to set up development environment"
                exit 1
            fi
        else
            echo
            log_info "Using existing directory: ${spack_env_top_dir}"
        fi
    else
        if ! setup_development_environment  "${DAQ_PKG_NAME}" "${version}" "${GCC_VERSION}" "${QUALIFIERS}" "${SPACK_ARCH}" "${DAQ_PKG_CHECKOUT_PACKAGES}" "${spack_env_top_dir}"; then
            log_error "Failed to set up development environment"
            exit 1
        fi
    fi

    # Return to the DAQ areas directory
    if ! cd "${SPACK_DAQ_AREAS}"; then
        log_error "Cannot access directory: ${SPACK_DAQ_AREAS}"
        exit 1
    fi

    # Configure local Spack settings if requested
    if [[ "${SPACK_USE_USER_CONFIG}" == true ]]; then
        log_command "unset SPACK_DISABLE_LOCAL_CONFIG"
        unset SPACK_DISABLE_LOCAL_CONFIG
        
        log_command "export SPACK_USER_CONFIG_PATH=${PWD}/${spack_env_top_dir}/spack"
        export SPACK_USER_CONFIG_PATH="${PWD}/${spack_env_top_dir}/spack"
    fi

    # Activate the Spack environment

    local spack_env_dir=$(format_path_name "${SPACK_DAQ_AREAS}/${spack_env_top_dir}" "${GCC_VERSION}" "${QUALIFIERS}" "${SPACK_ARCH}")
    
    log_command "spack env activate --prompt --dir ${spack_env_dir}"
    if ! spack env activate --prompt --dir "${spack_env_dir}"; then
        log_error "Cannot activate Spack environment: ${spack_env_dir}"
        exit 1
    fi

    # Handle environment concretization
    if [[ -f ${spack_env_dir}/spack.lock ]]; then
        log_info "Regenerating view..."
        log_command "spack env view regenerate"
        
        if ! spack env view regenerate; then
            log_error "Cannot regenerate Spack view"
            spack env deactivate || true
            exit 1
        fi
    else
        log_info "Concretizing environment..."
        log_warn "This step may take several minutes depending on NFS system speed"
        log_command "spack concretize --quiet --force"
        
        if ! spack concretize --quiet --force; then
            log_error "Cannot concretize Spack environment"
            spack env deactivate || true
            exit 1
        fi
    fi

    # Build packages if requested
    if [[ "${RUN_BUILD}" == true ]]; then
        if ! build_packages  "${DAQ_PKG_NAME}" "${version}" "${GCC_VERSION}" "${QUALIFIERS}"  "${SPACK_ARCH}" "${DAQ_PKG_CHECKOUT_PACKAGES}" "${BUILD_THREADS}" "${DEBUG_BUILD}" "${spack_env_top_dir}"; then
            log_error "Build process failed"
            spack env deactivate || true
            exit 1
        fi
    fi

    # Save command log with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local new_cmds_file="${spack_env_dir}/spack_commands-${timestamp}.txt"
    
    if ! mv "${CMDS_FILE}" "${new_cmds_file}"; then
        log_warn "Failed to save commands log to: ${new_cmds_file}"
    else
        log_info "Commands log saved to: ${new_cmds_file}"
    fi
    
    log_success "Setup completed successfully"
    return 0
}

activate_daq_development_area() {
    #if less than 4 arguments, complain
    if [[ $# -lt 4 ]]; then
        log_error "Not enough arguments"
        log_debug "Args: $*"
        log_error "Usage: activate_daq_development_area spack_env_top_dir gcc_version qualifiers arch"
        return 1
    fi

    local spack_env_top_dir="$1"
    local gcc_version="$2"
    local qualifiers="$3"
    local arch="$4"
    
    local spack_env_dir=$(format_path_name "${spack_env_top_dir}" "${gcc_version}" "${qualifiers}" "${arch}")
    
    log_command "spack env activate --prompt --dir ${spack_env_dir}"
    if ! spack env activate --prompt --dir "${spack_env_dir}"; then
        log_error "Cannot activate Spack environment: ${spack_env_dir}"
        exit 1
    fi
}


# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides unified functions for Spack development environments."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 