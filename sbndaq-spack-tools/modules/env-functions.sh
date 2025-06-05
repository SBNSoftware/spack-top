#!/usr/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_ENV_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _ENV_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"

# Initialize the Spack environment with the specified compiler version
# and other parameters.
initialize_spack_environment() {
    #if less than 4 arguments are provided, then complain
    if [[ $# -lt 4 ]]; then
        log_error "Missing required parameters for initialize_spack_environment"
        log_debug "Args: $*"
        log_error "Usage: initialize_spack_environment spack_install_root spack_release_version gcc_version spack_micro_arch build_threads debug_build"
        return 1
    fi
    local spack_install_root="${1:-${SPACK_INSTALL_ROOT:-"${HOME}/spack"}}"
    local spack_release_version="${2:-${SPACK_RELEASE_VERSION:-"current"}}"
    local gcc_version="${3:-${GCC_VERSION:-"13.1.0"}}"
    local spack_micro_arch="${4:-${SPACK_MICRO_ARCH:-"v2"}}"
    local build_threads="${5:-${BUILD_THREADS:-8}}"
    local debug_build="${6:-${DEBUG_BUILD:-false}}"
        

    
    # Validate Spack installation
    local spack_path="${spack_install_root}/${spack_release_version}"
    if [[ ! -d "${spack_path}" ]]; then
        log_error "Spack installation not found at: ${spack_path}"
        return 1
    fi
    
    if ! cd "${spack_path}"; then
        log_error "Cannot change directory to: ${spack_path}"
        return 1
    fi
    
    export SPACK_DISABLE_LOCAL_CONFIG=true
    
    if [[ ! -f "${spack_path}/setup-env.sh" ]]; then
        log_error "Spack setup script not found at: ${spack_path}/setup-env.sh"
        return 1
    fi
    
    if ! source "${spack_path}/setup-env.sh"; then
        log_error "Failed to source Spack setup script"
        return 1
    fi
    
    if ! command -v spack &>/dev/null; then
        log_error "Spack command not available after initialization"
        return 1
    fi
    



    # Set up build options
    local install_options="-y -j${build_threads} --deprecated --fresh --no-cache --source"
    
    # Add debug flag if requested
    if [[ "${debug_build}" == true ]]; then
        install_options+=" --debug"
    fi
    
    # Set up core environment variables
    export SPACK_HOME_DIR="${spack_path}"
    export SPACK_DISTRO_NAME="${SPACK_DISTRO_NAME:-$(spack arch -o 2>/dev/null)}"
    export SPACK_ARCH="linux-${SPACK_DISTRO_NAME}-x86_64_${spack_micro_arch}"
    export SPACK_BUILD_THREADS=${build_threads:-$(($(get_cpu_count) / 2))}
    export SPACK_GCC_VERSION="${gcc_version}"    
    export SPACK_INSTALL_OPTIONS="${install_options}"

    log_debug "Spack environment configured:"
    log_debug "  SPACK_HOME_DIR: ${SPACK_HOME_DIR}"
    log_debug "  SPACK_DISTRO_NAME: ${SPACK_DISTRO_NAME}"
    log_debug "  SPACK_ARCH: ${SPACK_ARCH}"
    log_debug "  SPACK_BUILD_THREADS: ${SPACK_BUILD_THREADS}"
    log_debug "  SPACK_GCC_VERSION: ${SPACK_GCC_VERSION}"
    log_debug "  SPACK_INSTALL_OPTIONS: ${SPACK_INSTALL_OPTIONS}"
    
    return 0
}

# Set up a development environment with the specified parameters
setup_development_environment() {
    if [[ $# -lt 7 ]]; then
        log_error "Missing required parameters for setup_development_environment"
        log_debug "Args: $*"
        log_error "Usage: setup_development_environment package_name version version gcc_version qualifiers arch checkout_packages spack_dev_top_dir"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local checkout_packages="$6"
    local spack_dev_top_dir="$7"
    

    log_debug "package_name: ${package_name}, version: ${version}, qualifiers: ${qualifiers}, gcc: ${gcc_version}, arch: ${arch}"
    log_debug "spack_dev_top_dir: ${spack_dev_top_dir}"
    log_debug "checkout_packages: ${checkout_packages}"
    
    local spack_dev_env_dir="$(format_path_name "${spack_dev_top_dir}" "${gcc_version}" "${qualifiers}" "${arch}")"

    log_info "Creating new Spack environment in ${spack_dev_env_dir}"
    log_debug "package: ${package_name}, version: ${version}, qualifiers: ${qualifiers}, gcc: ${gcc_version}"
    log_command "spack env create --dir ${spack_dev_env_dir}"
    if ! spack env create --dir "${spack_dev_env_dir}"; then
        log_error "Cannot create Spack environment: ${spack_dev_env_dir}"
        exit 1
    fi

    # Configure local settings if requested
    if [[ "${SPACK_USE_USER_CONFIG}" == true ]]; then
        if ! create_config_files "${spack_dev_top_dir}"; then
            log_error "Failed to create configuration files"
            exit 1
        fi
        
        log_command "unset SPACK_DISABLE_LOCAL_CONFIG"
        unset SPACK_DISABLE_LOCAL_CONFIG
        
        log_command "export SPACK_USER_CONFIG_PATH=${PWD}/${spack_dev_top_dir}/spack"
        export SPACK_USER_CONFIG_PATH="${PWD}/${spack_dev_top_dir}/spack"
    fi

    log_info "Activating Spack environment... in ${spack_dev_env_dir}"
    log_command "spack env activate --prompt --dir ${spack_dev_env_dir}"
    if ! spack env activate --prompt --dir "${spack_dev_env_dir}"; then
        log_error "Cannot activate Spack environment: ${spack_dev_env_dir}"
        exit 1
    fi

    if ! cd "${spack_dev_top_dir}"; then
        log_error "Cannot access directory: ${spack_dev_top_dir}"
        exit 1
    fi

    # Add package to environment with appropriate parameters
    log_info "Adding ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} to environment..."

    local spack_cmd="spack add ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    
    log_command "${spack_cmd}"
    if ! eval "${spack_cmd}"; then
        log_error "Cannot add ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} to environment"
        exit 1
    fi

    # Set up development packages
    if ! setup_development_packages "${package_name}" "${version}"  "${gcc_version}" "${qualifiers}" "${arch}" "${checkout_packages}" "${spack_dev_top_dir}"; then
        log_error "Failed to download package source"
        exit 1
    fi

    # Create DAQInterface symbolic link if it exists and DAQ_PKG_SBNENV is defined
    if [[ -n "${DAQ_PKG_SBNENV:-}" && -d "./srcs/sbndaq/${DAQ_PKG_SBNENV}/DAQInterface2" ]]; then
        ln -s "./srcs/sbndaq/${DAQ_PKG_SBNENV}/DAQInterface2" DAQInterface
        log_debug "Created DAQInterface symbolic link"
    fi

    # Deactivate the environment temporarily
    log_command "spack env deactivate"
    if ! spack env deactivate; then
        log_error "Cannot deactivate Spack environment"
        exit 1
    fi
    
    return 0
}

# Ensure mirror directories exist and are valid
ensure_mirror_directories() {
    local spack_dir="$1"
    local spack_version="$2"
    local spack_mirror_base="$3"

    if [[ ! -d "${spack_dir}" ]]; then
        log_error "Spack base directory not found: ${spack_dir}"
        log_error "Please install Spack before running this script"
        return 1
    fi

    if [[ ! -d "${spack_dir}/${spack_version}" ]]; then
        log_error "Spack version directory not found: ${spack_dir}/${spack_version}"
        log_error "Please install the required Spack version first"
        return 1
    fi

    if [[ ! -d "${spack_mirror_base}" ]]; then
        log_warn "Mirror base directory not found: ${spack_mirror_base}"
        
        if [[ "${NON_INTERACTIVE:-false}" == true ]]; then
            log_info "Non-interactive mode - creating mirror directory automatically"
            
            if ! mkdir -p "${spack_mirror_base}" 2>/dev/null; then
                log_error "Failed to create mirror directory: ${spack_mirror_base}"
                return 1
            fi
            
            log_success "Created mirror directory: ${spack_mirror_base}"
        else
            log_info "Mirror directory does not exist: ${spack_mirror_base}"
            
            if ask_for_continue; then
                log_info "Creating mirror directory: ${spack_mirror_base}"
                
                if ! mkdir -p "${spack_mirror_base}" 2>/dev/null; then
                    log_error "Failed to create mirror directory: ${spack_mirror_base}"
                    return 1
                fi
                
                log_success "Created mirror directory: ${spack_mirror_base}"
            else
                log_error "Cannot continue without mirror directory"
                return 1
            fi
        fi
    else
        log_debug "Using existing mirror directory: ${spack_mirror_base}"
    fi

    log_success "Mirror directories verified successfully"
    return 0
}

# Reindex the Spack database
reindex_spack_database() {
    log_info "Reindexing Spack database"
    log_command "spack reindex"

    if ! command -v spack &>/dev/null; then
        log_error "Spack command not available - cannot reindex"
        return 1
    fi

    if ! spack reindex; then
        log_error "Spack database reindex operation failed"
        return 1
    fi

    log_success "Spack database reindexed successfully"
    return 0
}

# Parse command line arguments for environment setup
if declare -f parse_arguments &>/dev/null; then
    unset -f parse_arguments
fi

parse_arguments() {
    # Initialize default values for arguments
    NON_INTERACTIVE=${NON_INTERACTIVE:-false}
    DEVNAME=${DEVNAME:-"NOTSET"}
    DEFAULT_VERSION=${DEFAULT_VERSION:-""}
    SPACK_USE_USER_CONFIG=${SPACK_USE_USER_CONFIG:-true}
    RUN_BUILD=${RUN_BUILD:-true}
    SPACK_MICRO_ARCH=${SPACK_MICRO_ARCH:-"v2"}
    
    local default_config_file
    
    if default_config_file=$(find_default_config_file); then
        SPACK_ENVFILE="${default_config_file}"
    fi

    # check if MY_CONFIG_FILE is set and if it is, use it
    if [[ -n "${MY_CONFIG_FILE:-}" ]]; then
        SPACK_ENVFILE="${MY_CONFIG_FILE}"
    fi

    local i=0
    while [[ $# -gt 0 ]]; do
        i=$((i+1))
        case $1 in
            -h|--help|/?)
                print_usage
                exit 0
                ;;
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --dev-name|--dev-name=*)
                if [[ "$1" == *"="* ]]; then
                    DEVNAME="${1#*=}"
                    shift
                elif [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    DEVNAME="$2"
                    shift 2
                else
                    log_error "Missing argument for --dev-name"
                    print_usage
                    exit 1
                fi
                ;;
            --default-version|--default-version=*)
                if [[ "$1" == *"="* ]]; then
                    DEFAULT_VERSION="${1#*=}"
                    shift
                elif [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    DEFAULT_VERSION="$2"
                    shift 2
                else
                    log_error "Missing argument for --default-version"
                    print_usage
                    exit 1
                fi
                ;;
            --no-build)
                RUN_BUILD=false
                shift
                ;;
            --config|--config=*)
                if [[ "$1" == *"="* ]]; then
                    SPACK_ENVFILE="${1#*=}"
                    readonly SPACK_ENVFILE
                    shift
                elif [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    SPACK_ENVFILE="$2"
                    readonly SPACK_ENVFILE
                    shift 2
                else
                    log_error "Missing argument for --config"
                    print_usage
                    exit 1
                fi
                ;;
            --micro-arch=*)
                SPACK_MICRO_ARCH="${1#*=}"
                shift
                ;;
            --micro-arch)
                if [[ -n "${2:-}" && "${2:0:1}" != "-" ]]; then
                    SPACK_MICRO_ARCH="$2"
                    shift 2
                else
                    log_error "Missing argument for --micro-arch"
                    print_usage
                    exit 1
                fi
                ;;
            -*)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
            *)
                log_warn "Ignoring unexpected argument: $1"
                shift
                ;;
        esac
        
        if [[ $i -gt 100 ]]; then
            log_error "Too many arguments or possible infinite loop in argument parsing"
            exit 1
        fi
    done
    
    export NON_INTERACTIVE DEVNAME DEFAULT_VERSION SPACK_USE_USER_CONFIG RUN_BUILD SPACK_MICRO_ARCH SPACK_ENVFILE    
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides environment setup functions for Spack development."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi

# Add a package to the environment with specific parameters
add_package_to_environment() {
    if [[ $# -lt 5 ]]; then
        log_error "Missing required parameters for add_package_to_environment"
        log_debug "Args: $*"
        log_error "Usage: add_package_to_environment pkg_name version qualifiers compiler_version arch"
        return 1
    fi
    
    local pkg_name="$1"
    local version="$2"
    local qualifiers="$3"
    local gcc_version="$4"
    local arch="${5:-"${SPACK_ARCH:-linux-almalinux9-x86_64_v2}"}"
    
    log_info "Adding ${pkg_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} to environment..."
    
    # Build the spack add command
    local spack_cmd="spack add ${pkg_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    log_command "${spack_cmd}"
    
    if ! eval "${spack_cmd}"; then
        log_error "Cannot add ${pkg_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} to environment"
        return 1
    fi
    
    return 0
}

# Find the default configuration file
find_default_config_file() {
    local config_name="${1:-${SPACK_ENVFILE:-}}"
    
    
    local search_paths=(
        "./${config_name}"
        "${HOME}/DAQ_SPACK_DevAreas/${config_name}"
        "${HOME}/${config_name}"
        "$(dirname "${SCRIPT_DIR}")/${config_name}"
    )

    # First try exact filename match
    for path in "${search_paths[@]}"; do
        if [[ -f "${path}" ]]; then
            log_debug "Found default config file: ${path}"
            echo "${path}"
            return 0
        fi
    done
            
    return 1
}