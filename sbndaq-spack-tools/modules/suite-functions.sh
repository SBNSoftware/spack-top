#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_SUITE_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _SUITE_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/build-functions.sh"


# Print usage information for DAQ suite build scripts
#unset the function if it exists    
if declare -f print_usage &>/dev/null; then
    unset -f print_usage
fi

print_usage() {
    local script_name="$1"
    local package_name="$2"
    
    cat << EOF
Usage: ${script_name} [VERSIONS]
Build and publish ${package_name} packages to buildcache.

Arguments:
    VERSIONS            Optional list of versions to process (default: predefined list)
EOF
}

parse_arguments() {
    local config_file="$1"
    shift
    
    if [[ -f "${config_file}" ]]; then
        log_debug "Using existing configuration file: ${config_file}"
        return 0
    fi
    
    log_info "Creating default configuration for ${package_name}: ${config_file}"
    
    if ! create_default_config "${config_file}" "${package_name}"; then
        log_error "Failed to create default configuration for ${package_name}: ${config_file}"
        return 1
    fi
    
    return 0
    
}

# Create default configuration file for artdaq-suite
create_artdaq_default_config() {
    local config_file="$1"
    
    if [[ -f "${config_file}" ]]; then
        log_debug "Using existing configuration file: ${config_file}"
        return 0
    fi
    
    log_info "Creating default configuration for artdaq-suite: ${config_file}"
    
    local config_dir
    config_dir=$(dirname "${config_file}")
    
    if [[ ! -d "${config_dir}" ]]; then
        if ! mkdir -p "${config_dir}" 2>/dev/null; then
            log_error "Cannot create configuration directory: ${config_dir}"
            return 1
        fi
    fi
    
    cat > "${config_file}" << EOF
# Default configuration for artdaq-suite build - generated on $(date)
# Customize these values according to your environment

# Base directories
SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SOFTWARE_BASE}/spack_mirrors/artdaq-suite

# DAQ suite configuration
DAQ_SUITE_NAME=artdaq-suite

# Format: version:qualifier:compiler:standard,\\
#         version:qualifier:compiler:standard
DAQ_SUITE_VERSIONS=v3_13_02:s131:gcc13.1.0:c++17,\\
v3_13_02:s131:gcc13.1.0:c++20,\\
v3_13_02:s132:gcc13.1.0:c++20,\\
v4_01_00:s132:gcc13.1.0:c++20


# Uncomment to customize build options
# BUILD_THREADS=8
# DEBUG_BUILD=false
# ENABLE_TESTS=true
EOF

    if [[ ! -f "${config_file}" ]]; then
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    fi
    
    log_success "Default configuration created at: ${config_file}"
    log_info "Please review the configuration before continuing"
    return 0
}

# Create default configuration file for sbndaq-suite
create_sbndaq_default_config() {
    local config_file="$1"
    
    if [[ -f "${config_file}" ]]; then
        log_debug "Using existing configuration file: ${config_file}"
        return 0
    fi
    
    log_info "Creating default configuration for sbndaq-suite: ${config_file}"
    
    local config_dir
    config_dir=$(dirname "${config_file}")
    
    if [[ ! -d "${config_dir}" ]]; then
        if ! mkdir -p "${config_dir}" 2>/dev/null; then
            log_error "Cannot create configuration directory: ${config_dir}"
            return 1
        fi
    fi
    
    cat > "${config_file}" << EOF
# Default configuration for sbndaq-suite build - generated on $(date)
# Customize these values according to your environment

# Base directories
SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SOFTWARE_BASE}/spack_mirrors/sbndaq-suite

# DAQ suite configuration
DAQ_SUITE_NAME=sbndaq-suite

# Format: version:qualifier:compiler:standard,\\
#         version:qualifier:compiler:standard
DAQ_SUITE_VERSIONS=migration_artdaqv3_13_02:s131:gcc13.1.0:c++17,\\
migration_artdaqv3_13_02:s131:gcc13.1.0:c++20,\\
migration_artdaqv3_13_02:s132:gcc13.1.0:c++20,\\
migration_artdaqv4_01_00:s132:gcc13.1.0:c++20


# Uncomment to customize build options
# BUILD_THREADS=8
# DEBUG_BUILD=false
# ENABLE_TESTS=true
EOF

    if [[ ! -f "${config_file}" ]]; then
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    fi
    
    log_success "Default configuration created at: ${config_file}"
    log_info "Please review the configuration before continuing"
    return 0
}

# Run the artdaq-suite build process
run_artdaq_build() {
    local config_file="${1:-build-artdaq-suite.env}"
    shift
    
    if ! create_artdaq_default_config "${config_file}"; then
        return 1
    fi
    
    run_daq_build "${config_file}" "$@"
    return $?
}

# Run the sbndaq-suite build process
run_sbndaq_build() {
    local config_file="${1:-build-sbndaq-suite.env}"
    shift
    
    if ! create_sbndaq_default_config "${config_file}"; then
        return 1
    fi
    
    run_daq_build "${config_file}" "$@"
    return $?
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides suite-specific functions for DAQ software."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 