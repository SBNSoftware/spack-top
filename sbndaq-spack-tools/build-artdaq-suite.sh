#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_BUILD_ARTDAQ_SUITE_SH_:-0}" -eq 1 ]]; then
    return 0
fi
_BUILD_ARTDAQ_SUITE_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/spack-functions.sh"
source "${SCRIPT_DIR}/build-anydaq-suite.sh"

# Configuration loading
readonly BUILD_ARTDAQ_ENVFILE=${BUILD_ARTDAQ_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}

print_artdaq_usage() {
    print_anydaq_usage "$(basename "$0")" "artdaq-suite"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -n "${1:-}" ]] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    print_artdaq_usage
    exit 0
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_info "Sourcing $(basename "${BASH_SOURCE[0]}")..."
fi

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

main() {
    if ! create_artdaq_default_config "${BUILD_ARTDAQ_ENVFILE}"; then
        return 1
    fi
    
    run_daq_build "${BUILD_ARTDAQ_ENVFILE}" "$@"
    return $?
}

export PS1='\[\033[0;35m\]\t\[\033[0;33m\]\u\[\033[0;35m\]@\[\033[0;36m\]\h\[\033[0;32m\]:\w\[\033[0;32m\]\n$ \[\e[m\]'

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    parse_arguments "$@"
    log_debug "Finished sourcing $(basename "${BASH_SOURCE[0]}")"
fi