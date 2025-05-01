#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_SPACK_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
_SPACK_FUNCTIONS_SH_=1

if ! readonly -p | grep -q "declare -r SPACK_ENVFILE="; then
    readonly SPACK_ENVFILE=${SPACK_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}
fi

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"

setup_spack_environment() {
    local spack_dir="$1"
    local spack_version="$2"
    local gcc_version="$3"

    log_info "Setting up Spack environment with GCC ${gcc_version}"

    local spack_path="${spack_dir}/${spack_version}"
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

    export SPACK_DISABLE_LOCAL_CONFIG=true
    export SPACK_GCC_VERSION="${gcc_version}"
    export SPACK_MICRO_ARCH=${SPACK_MICRO_ARCH:-'v2'}

    local spack_arch_output
    if ! spack_arch_output=$(spack arch -o 2>/dev/null); then
        log_error "Failed to determine Spack architecture"
        return 1
    fi
    export SPACK_OS="${spack_arch_output}"

    local cpu_count
    cpu_count=$(get_cpu_count)
    export SPACK_J=${SPACK_J:-"${cpu_count}"}
    export SPACK_ARCH="linux-${SPACK_OS}-x86_64_${SPACK_MICRO_ARCH}"
    export SPACK_INSTALL_OPTS=" -y -j${SPACK_J} --deprecated --fresh --no-cache --source"
    
    log_debug "Spack environment configured:"
    log_debug "  SPACK_ARCH: ${SPACK_ARCH}"
    log_debug "  SPACK_J: ${SPACK_J}"
    log_debug "  SPACK_GCC_VERSION: ${SPACK_GCC_VERSION}"
    log_debug "  SPACK_MICRO_ARCH: ${SPACK_MICRO_ARCH}"

    return 0
}

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
        
        if [[ "${NON_INTERACTIVE}" == true ]]; then
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

update_buildcache_index() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_path="$3"

    if [[ ! -d "${mirror_path}" ]]; then
        log_info "Creating mirror directory: ${mirror_path}"
        
        if ! mkdir -p "${mirror_path}" 2>/dev/null; then
            log_error "Failed to create mirror directory: ${mirror_path}"
            return 1
        fi
        
        log_success "Created mirror directory: ${mirror_path}"
    fi

    log_info "Updating buildcache index at ${mirror_path}"

    if ! cd "${spack_dir}/${spack_version}"; then
        log_error "Cannot change directory to: ${spack_dir}/${spack_version}"
        return 1
    fi

    if ! command -v spack &>/dev/null; then
        log_error "Spack command not available - cannot update buildcache index"
        return 1
    fi

    local cmd="spack buildcache update-index \"${mirror_path}\""
    log_command "${cmd}"
    
    if ! eval "${cmd}"; then
        log_error "Failed to update buildcache index for: ${mirror_path}"
        return 1
    fi

    log_success "Buildcache index updated at: ${mirror_path}"
    return 0
}

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
    
    cat > "${config_file}" << EOF
# Default configuration generated on $(date)

# Base directories
SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SOFTWARE_BASE}/spack_mirrors/sbndaq-suite

# Compiler settings
GCC_VERSION=13.1.0

# DAQ suite configuration
DAQ_SUITE_NAME=sbndaq-suite

# Format: version|qualifier|compiler|standard;version|qualifier|compiler|standard
DAQ_SUITE_VERSIONS=migration_artdaqv3_13_02|s131|gcc13.1.0|c++17;migration_artdaqv3_13_02|s131|gcc13.1.0|c++20

# Legacy configuration fields - no longer used but kept for compatibility
DAQ_SUITE_QUALIFIERS=s131:s132

# Build options
# BUILD_THREADS=8
# DEBUG_BUILD=false
# ENABLE_TESTS=true
EOF

    if [[ ! -f "${config_file}" ]]; then
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    fi
    
    log_success "Default configuration file created at: ${config_file}"
    log_info "Please review the configuration file before continuing"
    return 0
}

test_spack_functions() {
    trap 'echo "ERROR: Line $LINENO: Command \"$BASH_COMMAND\" failed with exit code $?"; exit 1' ERR
    NON_INTERACTIVE=true
    
    log_info "Testing spack-functions.sh functionality"
    
    local test_dir=$(mktemp -d "/tmp/spack-functions-test-XXXXXX")
    
    log_info "== Testing Configuration Management =="
    local test_config_file="${test_dir}/spack-config.env"
    
    create_default_config "${test_config_file}"
    if [[ -f "${test_config_file}" ]]; then
        log_success "Default configuration created successfully"
        
        if grep -q "SOFTWARE_BASE=" "${test_config_file}" && 
           grep -q "SPACK_DIR=" "${test_config_file}" && 
           grep -q "SPACK_VERSION=" "${test_config_file}" && 
           grep -q "GCC_VERSION=" "${test_config_file}"; then
            log_success "Default configuration contains expected entries"
        else
            log_error "Default configuration is missing expected entries"
            exit 1
        fi
        
        if create_default_config "${test_config_file}"; then
            log_success "Correctly handled existing configuration file"
        else
            log_error "Failed when handling existing configuration file"
            exit 1
        fi
    else
        log_error "Failed to create default configuration"
        exit 1
    fi
    
    log_info "== Testing Environment Setup (mocked) =="
    
    local mock_spack_dir="${test_dir}/spack"
    local mock_spack_version="test-version"
    local mock_spack_path="${mock_spack_dir}/${mock_spack_version}"
    mkdir -p "${mock_spack_path}"
    
    cat > "${mock_spack_path}/setup-env.sh" << EOF
#!/bin/bash
spack() {
    if [[ "\$1" == "arch" && "\$2" == "-o" ]]; then
        echo "mock-os"
        return 0
    elif [[ "\$1" == "reindex" ]]; then
        echo "Mock spack reindex called"
        return 0
    elif [[ "\$1" == "buildcache" ]]; then
        echo "Mock spack buildcache \$2 called with args: \${@:3}"
        return 0
    elif [[ "\$1" == "find" ]]; then
        echo "gcc@13.1.0"
        echo "python@3.9.0"
        return 0
    else
        echo "Mock spack: \$@"
        return 0
    fi
}
export -f spack
EOF
    chmod +x "${mock_spack_path}/setup-env.sh"
    
    log_info "Testing setup_spack_environment with GCC 13.1.0"
    if setup_spack_environment "${mock_spack_dir}" "${mock_spack_version}" "13.1.0"; then
        log_success "Spack environment setup succeeded with GCC 13.1.0"
        
        if [[ "${SPACK_GCC_VERSION}" == "13.1.0" && 
              "${SPACK_OS}" == "mock-os" && 
              "${SPACK_ARCH}" == "linux-${SPACK_OS}-x86_64_${SPACK_MICRO_ARCH}" ]]; then
            log_success "Spack environment variables set correctly"
        else
            log_error "Spack environment variables not set correctly"
            exit 1
        fi
    else
        log_error "Spack environment setup failed with GCC 13.1.0"
        exit 1
    fi
    
    log_info "Testing setup_spack_environment with GCC 12.1.0"
    if setup_spack_environment "${mock_spack_dir}" "${mock_spack_version}" "12.1.0"; then
        log_success "Spack environment setup succeeded with GCC 12.1.0"
        
        if [[ "${SPACK_GCC_VERSION}" == "12.1.0" ]]; then
            log_success "GCC version updated correctly"
        else
            log_error "GCC version not updated correctly"
            exit 1
        fi
    else
        log_error "Spack environment setup failed with GCC 12.1.0"
        exit 1
    fi
    
    log_info "Testing error handling with invalid parameters"
    if ! setup_spack_environment "/nonexistent/path" "${mock_spack_version}" "13.1.0" 2>/dev/null; then
        log_success "Correctly failed with nonexistent spack directory"
    else
        log_error "Should have failed with nonexistent spack directory"
        exit 1
    fi
    
    if ! setup_spack_environment "${mock_spack_dir}" "nonexistent-version" "13.1.0" 2>/dev/null; then
        log_success "Correctly failed with nonexistent spack version"
    else
        log_error "Should have failed with nonexistent spack version"
        exit 1
    fi
    
    log_info "== Testing Spack Reindex =="
    
    if reindex_spack_database; then
        log_success "reindex_spack_database function executed successfully"
    else
        log_error "reindex_spack_database function failed"
        exit 1
    fi
    
    log_info "Testing reindex with broken spack command"
    local temp_spack_func
    temp_spack_func=$(declare -f spack)
    unset -f spack
    
    spack() {
        if [[ "$1" == "reindex" ]]; then
            return 1
        fi
        return 0
    }
    export -f spack
    
    if ! reindex_spack_database 2>/dev/null; then
        log_success "reindex_spack_database correctly failed with broken spack command"
    else
        log_error "reindex_spack_database should have failed with broken spack command"
        exit 1
    fi
    
    unset -f spack
    eval "${temp_spack_func}"
    
    log_info "== Testing Mirror Directory Management =="
    local mock_mirror_base="${test_dir}/mirrors"
    
    if ensure_mirror_directories "${mock_spack_dir}" "${mock_spack_version}" "${mock_mirror_base}"; then
        log_success "Mirror directories created successfully"
        if [[ -d "${mock_mirror_base}" ]]; then
            log_info "Mirror base directory exists: ${mock_mirror_base}"
        else
            log_error "Mirror base directory was not created"
            exit 1
        fi
    else
        log_error "Failed to ensure mirror directories"
        exit 1
    fi
    
    log_info "Skipping update_buildcache_index test (requires real spack installation)"
    
    if [[ -d "${test_dir}" ]]; then
        rm -rf "${test_dir}"
        log_success "Cleaned up test directory"
    fi
    
    log_success "All tests completed successfully"
    trap - ERR
}

main() {
    parse_arguments "$@"
    
    if [[ "${RUN_TESTS:-false}" == "true" ]]; then
        test_spack_functions
        exit $?
    fi
    
    log_info "This script provides Spack functions and should be sourced, not executed directly"
    log_info "Run with --test flag to execute tests"
    exit 0
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    parse_arguments "$@"
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi