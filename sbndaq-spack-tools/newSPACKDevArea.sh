#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Script configuration
declare -r SPACK_ENVFILE="$(basename "${BASH_SOURCE[0]%.*}").env"

# Ensure script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Error: This script should be executed, not sourced."
    return 1
fi

# Source required scripts
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/spack-functions.sh"
source "${SCRIPT_DIR}/spack-setup-environment.sh"

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Sets up a Spack development area for SBND DAQ software development.
Creates a new directory with custom Spack environment, checks out specified
packages for development, and optionally builds them.

Options:
    --non-interactive     Run without user prompts (default: false)
    --dev-name NAME       Set developer name for directory naming (default: GAL)
    --default-version VER Set specific version instead of latest available
    --global-config       Use global Spack config instead of local
    --no-build            Skip package building step
    --config=FILE         Specify configuration file path
    -h, --help            Display this help message and exit

Examples:
    $(basename "$0") --dev-name JOHN --default-version v1_10_07
    $(basename "$0") --non-interactive --no-build
EOF
}

# Display help if requested
if [[ $# -gt 0 && ("$1" == "-h" || "$1" == "/?" || "$1" == "--help") ]]; then
    print_usage
    exit 0
fi

create_default_config() {
    local config_file="$1"
    
    if [[ -f "${config_file}" ]]; then
        log_debug "Using existing configuration file: ${config_file}"
        return 0
    fi
    
    log_info "Creating default configuration file: ${config_file}"
    
    local config_dir
    config_dir=$(dirname "${config_file}")
    
    if [[ ! -d "${config_dir}" ]]; then
        if ! mkdir -p "${config_dir}" 2>/dev/null; then
            log_error "Cannot create config directory: ${config_dir}"
            return 1
        fi
    fi
    
    # Create the default configuration file
    cat > "${config_file}" << EOF || {
# Default configuration generated on $(date)

DEVNAME=EFG
# DAQ suite configuration
DAQ_SUITE_NAME=sbndaq-suite

# Format: version:qualifier:compiler:standard,\\
#         version:qualifier:compiler:standard
DAQ_SUITE_VERSIONS=migration_artdaqv3_13_02:s131:gcc13.1.0:c++20,\\
migration_artdaqv3_13_02:s132:gcc13.1.0:c++20
DAQ_SUITE_SBNENV=sbn-fd
DAQ_SUITE_CHECKOUT_PACKAGES=sbndaq@upgrade_gcc13.1.0,sbndaq-artdaq@upgrade_gcc13.1.0,\\
sbndaq-artdaq-core@upgrade_gcc13.1.0,wibtools@upgrade_gcc13.1.0


# Spack configuration
SPACK_SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SPACK_SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SPACK_SOFTWARE_BASE}/spack_mirrors/\${DAQ_SUITE_NAME}
SPACK_DAQ_AREAS=\${HOME}/DAQ_SPACK_DevAreas
SPACK_PACKAGES_TOP=\${SPACK_SOFTWARE_BASE}/spack_packages
SPACK_USE_USER_CONFIG=true

# Uncomment to customize build options
RUN_BUILD=true
BUILD_THREADS=8
DEBUG_BUILD=false
ENABLE_TESTS=true
ENABLE_GIT_PUSH=true
ALLOW_HOSTS=vm-60,vm-51
ALLOW_USERS=artdaq,icarus,sbnd
EOF
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    }
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    fi
    
    log_success "Default configuration file created at: ${config_file}"
    log_info "Please review the configuration file before continuing"
    return 0
}

parse_arguments() {
    # Initialize default values for arguments
    NON_INTERACTIVE=${NON_INTERACTIVE:-false}
    DEVNAME=${DEVNAME:-"XYZ"}
    DEFAULT_VERSION=${DEFAULT_VERSION:-""}
    SPACK_USE_USER_CONFIG=${SPACK_USE_USER_CONFIG:-true}
    RUN_BUILD=${RUN_BUILD:-true}
    SPACK_MICRO_ARCH=${SPACK_MICRO_ARCH:-"v2"}
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive)
                NON_INTERACTIVE=true
                shift
                ;;
            --dev-name)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing argument for --dev-name"
                    print_usage
                    exit 1
                fi
                DEVNAME="$2"
                shift 2
                ;;
            --default-version)
                if [[ -z "${2:-}" ]]; then
                    log_error "Missing argument for --default-version"
                    print_usage
                    exit 1
                fi
                # Override the first element of DAQ_SUITE_VERSIONS with this version
                # We'll only need to extract and use this value, not modify DAQ_SUITE_VERSIONS itself
                DEFAULT_VERSION="$2"
                shift 2
                ;;
            --global-config)
                SPACK_USE_USER_CONFIG=false
                shift
                ;;
            --no-build)
                RUN_BUILD=false
                shift
                ;;
            --config=*)
                SPACK_ENVFILE="${1#*=}"
                if [[ ! -f "${SPACK_ENVFILE}" && ! -w "$(dirname "${SPACK_ENVFILE}")" ]]; then
                    log_error "Cannot write to config file location: ${SPACK_ENVFILE}"
                    exit 1
                fi
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
    
    # Export arguments for use in other functions
    export NON_INTERACTIVE DEVNAME DEFAULT_VERSION SPACK_USE_USER_CONFIG RUN_BUILD ALLOW_USERS ALLOW_HOSTS SPACK_MICRO_ARCH
}



setup_mdp_environment() {
    local dir_name="$1"
    local suite_name="$2"
    local version="$3"
    local qualifier="$4"
    local gcc_version="$5"
    local cxxstd="${6:-}"
    local arch="${7:-${SPACK_ARCH}}"
    
    # Format for logging
    local build_qualifier="s=${qualifier#s}"
    local cxxstd_param=""
    if [[ -n "${cxxstd}" ]]; then
        cxxstd_param="cxxstd=${cxxstd#c++}"
    fi

    log_info "Creating new Spack environment in ${dir_name}"
    log_debug "version: ${version}, qualifier: ${build_qualifier}, gcc_version: ${gcc_version}, cxxstd: ${cxxstd_param}"
    
    return 0
}

setup_development_environment() {
    local dir_name="$1"
    local suite_name="$2"
    local version="$3"
    local qualifier="$4"
    local gcc_version="$5"
    local cxxstd="${6:-}"
    local arch="${7:-${SPACK_TARGET_PLATFORM}}"
    local checkout_packages="${8:-${DAQ_SUITE_CHECKOUT_PACKAGES}}"
    
    # Fall back to environment variables if not provided
    suite_name="${suite_name:-${DAQ_SUITE_NAME}}"
    
    # Format qualifier and cxxstd for display and commands
    local build_qualifier="s=${qualifier#s}"
    local cxxstd_param=""
    if [[ -n "${cxxstd}" ]]; then
        cxxstd_param="cxxstd=${cxxstd#c++}"
    fi

    # Validate required parameters
    if [[ -z "$dir_name" || -z "$suite_name" || -z "$version" || -z "$qualifier" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for setup_development_environment"
        log_error "Usage: setup_development_environment dir_name suite_name version qualifier gcc_version [cxxstd] [arch] [checkout_packages]"
        return 1
    fi

    log_info "Creating new Spack environment in ${dir_name}"
    log_debug "version: ${version}, qualifier: ${build_qualifier}, gcc_version: ${gcc_version}, cxxstd: ${cxxstd_param}"
    log_command "spack env create --dir ${dir_name}"
    if ! spack env create --dir "${dir_name}"; then
        log_error "Cannot create Spack environment: ${dir_name}"
        exit 1
    fi

    # Configure local settings if requested
    if [[ "${SPACK_USE_USER_CONFIG}" == true ]]; then
        if ! create_config_files "${dir_name}"; then
            log_error "Failed to create configuration files"
            exit 1
        fi
        
        log_command "unset SPACK_DISABLE_LOCAL_CONFIG"
        unset SPACK_DISABLE_LOCAL_CONFIG
        
        log_command "export SPACK_USER_CONFIG_PATH=${PWD}/${dir_name}/spack"
        export SPACK_USER_CONFIG_PATH="${PWD}/${dir_name}/spack"
    fi

    log_info "Activating Spack environment..."
    log_command "spack env activate --prompt --dir ${dir_name}"
    if ! spack env activate --prompt --dir "${dir_name}"; then
        log_error "Cannot activate Spack environment: ${dir_name}"
        exit 1
    fi

    if ! cd "${dir_name}"; then
        log_error "Cannot access directory: ${dir_name}"
        exit 1
    fi

    if [[ -n "${cxxstd_param}" ]]; then
        log_info "Adding ${suite_name} @${version} ${build_qualifier} ${cxxstd_param} to environment..."
        log_command "spack add ${suite_name}@${version} ${build_qualifier} ${cxxstd_param} %gcc@${gcc_version} arch=${arch}"
        if ! spack add "${suite_name}@${version}" "${build_qualifier}" "${cxxstd_param}" "%gcc@${gcc_version}" "arch=${arch}"; then
            log_error "Cannot add ${suite_name} to environment"
            exit 1
        fi
    else
        log_info "Adding ${suite_name} @${version} ${build_qualifier} to environment..."
        log_command "spack add ${suite_name}@${version} ${build_qualifier} %gcc@${gcc_version} arch=${arch}"
        if ! spack add "${suite_name}@${version}" "${build_qualifier}" "%gcc@${gcc_version}" "arch=${arch}"; then
            log_error "Cannot add ${suite_name} to environment"
            exit 1
        fi
    fi

    if ! setup_development_packages "${suite_name}" "${version}" "${qualifier}" "${gcc_version}" "${cxxstd}" "${checkout_packages}" "${arch}"; then
        log_error "Failed to download package source"
        exit 1
    fi

    # Create DAQInterface symbolic link if it exists
    if [[ -d "./srcs/sbndaq/${DAQ_SUITE_SBNENV}/DAQInterface2" ]]; then
        ln -s "./srcs/sbndaq/${DAQ_SUITE_SBNENV}/DAQInterface2" DAQInterface
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

build_packages() {
    local dir_name="$1"
    local suite_name="$2"
    local version="$3" 
    local qualifier="$4"
    local gcc_version="$5"
    local cxxstd="${6:-}"
    local build_threads="${7:-${BUILD_THREADS:-}}"
    local debug_build="${8:-${DEBUG_BUILD:-false}}"
    local checkout_packages="${9:-${DAQ_SUITE_CHECKOUT_PACKAGES}}"
    local arch="${SPACK_TARGET_PLATFORM}"
    
    # Validate required parameters
    if [[ -z "$dir_name" || -z "$suite_name" || -z "$version" ]]; then
        log_error "Missing required parameters for build_packages"
        log_error "Usage: build_packages dir_name suite_name version [qualifier] [gcc_version] [cxxstd] [build_threads] [debug_build] [checkout_packages]"
        return 1
    fi

    # Use environment variable defaults if needed
    suite_name="${suite_name:-${DAQ_SUITE_NAME}}"
    
    log_info "Building packages..."
    log_warn "This step may take several minutes depending on NFS system speed"
    
    # Determine number of threads to use
    local cpu_count
    cpu_count=$(get_cpu_count)
    local j_value=${build_threads:-$((cpu_count / 2))}
    
    # Build command options
    local build_opts="-y -j${j_value} --fresh --no-cache --source"
    
    # Add any debug options if needed
    if [[ "${debug_build}" == true ]]; then
        build_opts+=" --debug"
    fi

    local cxxstd_suffix=""
    local cxxstd_param=""
    if [[ -n "$cxxstd" ]]; then
        local cxxstd_num="${cxxstd#c++}"
        cxxstd_param="cxxstd=${cxxstd_num}"
        cxxstd_suffix="-${cxxstd}"
    fi

    local spec_file="${dir_name}/${suite_name}-${version}-s${qualifier#s}-gcc${gcc_version%%.*}${cxxstd_suffix}-${SPACK_DISTRO_NAME}.pkgs.txt"

    log_command "spack spec ${suite_name}@${version} s=${qualifier#s} ${cxxstd_param} arch=${arch} %gcc@${gcc_version} > ${spec_file}"

    if ! spack spec ${suite_name}@${version} s=${qualifier#s} ${cxxstd_param} arch=${arch} %gcc@${gcc_version} > ${spec_file}; then
        log_error "Cannot run spack spec"
        exit 1
    fi

    log_command "spack install ${build_opts}"
    if ! spack install ${build_opts}; then
        log_warn "Build failed - entering interactive build mode"
        
        # Interactive build recovery
        IFS=',' read -ra CHECKOUT_PACKAGES <<< "${checkout_packages}"
        
        while true; do
            echo "Available packages:"
            for i in "${!CHECKOUT_PACKAGES[@]}"; do
                echo "$((i+1)). ${CHECKOUT_PACKAGES[$i]}"
            done
            echo "0. Exit interactive build mode"
            
            local choice
            read -p "Select package to build (0-${#CHECKOUT_PACKAGES[@]}): " choice
            
            if [[ "$choice" == "0" ]]; then
                log_info "Exiting interactive build mode"
                break
            elif [[ "$choice" =~ ^[1-9]+$ ]] && ((choice <= ${#CHECKOUT_PACKAGES[@]})); then
                local pkg_name
                pkg_name=$(echo "${CHECKOUT_PACKAGES[$((choice-1))]}" | cut -d'@' -f1)
                
                log_info "Entering build environment for ${pkg_name}"
                log_info "Available commands in build environment:"
                log_info "  make    # Build the package"
                log_info "  exit 0  # Exit build environment"

                log_command "spack cd --build-dir ${pkg_name}" 
                spack cd --build-dir ${pkg_name}

                log_command "spack build-env ${pkg_name} -- bash"
                spack build-env "${pkg_name}" -- bash

                local build_status
                read -p "Did the build succeed? (y/n): " build_status
                if [[ ${build_status,,} == "y" ]]; then
                    continue
                fi
            else
                log_warn "Invalid selection: ${choice}"
            fi
        done
        
        local continue_response
        read -p "Continue with buildcache creation? (y/n): " continue_response
        if [[ ${continue_response,,} == "y" ]]; then
            generate_package_buildcache "${dir_name}" "${suite_name}" "${version}" "${qualifier}" "${gcc_version}" "${cxxstd}"
            return 0
        else
            log_error "Build process aborted by user"
            return 1
        fi
    else
        generate_package_buildcache "${dir_name}" "${suite_name}" "${version}" "${qualifier}" "${gcc_version}" "${cxxstd}"
        return 0
    fi
}

main() {
    # Initialize log directory
    LOGS_DIR="${SPACK_DAQ_AREAS:-${HOME}/DAQ_SPACK_DevAreas}/logs"
    ensure_log_directory
    CMDS_FILE="${LOGS_DIR}/spack_commands.txt"
    
    # Set up signal handlers
    setup_signal_handlers
    
    # Create or verify configuration file
    if ! create_default_config "${SPACK_ENVFILE}"; then
        log_error "Failed to create or verify configuration file"
        exit 1
    fi
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Load configuration from file
    local required_vars="DEVNAME:DAQ_SUITE_NAME:DAQ_SUITE_VERSIONS:DAQ_SUITE_SBNENV:DAQ_SUITE_CHECKOUT_PACKAGES:SPACK_SOFTWARE_BASE:SPACK_DIR:SPACK_VERSION:SPACK_MIRROR_BASE:SPACK_DAQ_AREAS:SPACK_PACKAGES_TOP:SPACK_USE_USER_CONFIG:RUN_BUILD:BUILD_THREADS:DEBUG_BUILD:ENABLE_TESTS:ENABLE_GIT_PUSH:ALLOW_HOSTS:ALLOW_USERS"
    if ! load_build_config "${SPACK_ENVFILE}" "${required_vars}"; then
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

    # Parse the first element of DAQ_SUITE_VERSIONS to get version, qualifier, gcc_version, and cxxstd
    if [[ -z "${DAQ_SUITE_VERSIONS}" ]]; then
        log_error "DAQ_SUITE_VERSIONS is not defined in configuration"
        exit 1
    fi
    
    IFS=':' read -r VERSION QUALIFIER COMPILER CXXSTD <<< "${DAQ_SUITE_VERSIONS%%,*}"
    
    # Validate components
    if [[ -z "${VERSION}" || -z "${QUALIFIER}" || -z "${COMPILER}" || -z "${CXXSTD}" ]]; then
        log_error "Invalid DAQ_SUITE_VERSIONS format. Expected: version:qualifier:compiler:standard"
        log_error "Got: VERSION=${VERSION}, QUALIFIER=${QUALIFIER}, COMPILER=${COMPILER}, CXXSTD=${CXXSTD}"
        exit 1
    fi
    
    # Use DEFAULT_VERSION if specified via command line, otherwise use VERSION from DAQ_SUITE_VERSIONS
    if [[ -n "${DEFAULT_VERSION}" ]]; then
        VERSION="${DEFAULT_VERSION}"
        log_debug "Using command-line specified version: ${VERSION}"
    else
        log_debug "Using version from DAQ_SUITE_VERSIONS: ${VERSION}"
    fi
    
    # Extract GCC version from compiler string (removing "gcc" prefix)
    GCC_VERSION="${COMPILER#gcc}"
    # Ensure qualifier has "s=" prefix - but we'll pass the raw qualifier to functions
    BUILD_QUALIFIER="s=${QUALIFIER#s}"
    # Extract C++ standard number from c++ string (removing "c++" prefix)
    CXXSTD_PARAM="cxxstd=${CXXSTD#c++}"
    
    log_debug "Parsed values: VERSION=${VERSION}, BUILD_QUALIFIER=${BUILD_QUALIFIER}, GCC_VERSION=${GCC_VERSION}, CXXSTD_PARAM=${CXXSTD_PARAM}"
    
    log_debug "Setting up Spack environment with GCC ${GCC_VERSION}"
    echo "# Spack commands executed:" > "${CMDS_FILE}"
    
    # Initialize Spack environment with explicit parameters
    if ! initialize_spack_environment "${SPACK_DIR}" "${SPACK_VERSION}" "${GCC_VERSION}" "${CXXSTD}" "${SPACK_MICRO_ARCH}" "${BUILD_THREADS}" "${DEBUG_BUILD}"; then
        log_error "Cannot initialize Spack environment - check Spack installation"
        exit 1
    fi

    # Select package version with explicit parameters
    local version
    version=$(select_package_version "${DAQ_SUITE_NAME}" "${QUALIFIER}" "${GCC_VERSION}" "${VERSION}" "${CXXSTD}")
    if [[ -z "${version}" ]]; then
        log_error "Failed to determine package version"
        exit 1
    fi
    
    echo
    log_info "Selected ${DAQ_SUITE_NAME} version: ${version}"
    
    # Create directory with date, developer name, and version information
    local date_str
    date_str=$(date +%Y-%m-%d)
    local dir_name="DAQ_${date_str}_${DEVNAME}_${version}"

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
    if [[ -d "${dir_name}" ]]; then
        local delete_response
        delete_response=$(read_with_timeout "Directory ${dir_name} exists. Delete it? [y/N]: " "N")
        
        if [[ ${delete_response,,} == "y" ]]; then
            log_info "Removing existing directory: ${dir_name}"
            log_warn "This step may take several minutes depending on NFS system speed"
            
            if ! rm -rf "${SPACK_DAQ_AREAS}/${dir_name}"; then
                log_error "Failed to remove directory: ${dir_name}"
                exit 1
            fi
            
            if ! setup_development_environment "${dir_name}" "${DAQ_SUITE_NAME}" "${version}" "${QUALIFIER}" "${GCC_VERSION}" "${CXXSTD}" "${SPACK_TARGET_PLATFORM}" "${DAQ_SUITE_CHECKOUT_PACKAGES}"; then
                log_error "Failed to set up development environment"
                exit 1
            fi
        else
            echo
            log_info "Using existing directory: ${dir_name}"
        fi
    else
        if ! setup_development_environment "${dir_name}" "${DAQ_SUITE_NAME}" "${version}" "${QUALIFIER}" "${GCC_VERSION}" "${CXXSTD}" "${SPACK_TARGET_PLATFORM}" "${DAQ_SUITE_CHECKOUT_PACKAGES}"; then
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
        
        log_command "export SPACK_USER_CONFIG_PATH=${PWD}/${dir_name}/spack"
        export SPACK_USER_CONFIG_PATH="${PWD}/${dir_name}/spack"
    fi

    # Activate the Spack environment
    log_command "spack env activate --prompt --dir ${dir_name}"
    if ! spack env activate --prompt --dir "${dir_name}"; then
        log_error "Cannot activate Spack environment: ${dir_name}"
        exit 1
    fi

    # Handle environment concretization
    if [[ -f ${dir_name}/spack.lock ]]; then
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
        if ! build_packages "${dir_name}" "${DAQ_SUITE_NAME}" "${version}" "${QUALIFIER}" "${GCC_VERSION}" "${CXXSTD}" "${BUILD_THREADS}" "${DEBUG_BUILD}" "${DAQ_SUITE_CHECKOUT_PACKAGES}"; then
            log_error "Build process failed"
            spack env deactivate || true
            exit 1
        fi
    fi

    # Save command log with timestamp
    local timestamp
    timestamp=$(date +%Y%m%d-%H%M%S)
    local new_cmds_file="${dir_name}/spack_commands-${timestamp}.txt"
    
    if ! mv "${CMDS_FILE}" "${new_cmds_file}"; then
        log_warn "Failed to save commands log to: ${new_cmds_file}"
    else
        log_info "Commands log saved to: ${new_cmds_file}"
    fi
    
    log_success "Setup completed successfully"
    return 0
}

# Run the main function with all arguments
main "$@"
