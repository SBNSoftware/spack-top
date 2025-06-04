#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_BUILD_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _BUILD_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/config-functions.sh"
source "${SCRIPT_DIR}/env-functions.sh"
source "${SCRIPT_DIR}/buildcache-functions.sh"

# Install a package with the specified parameters
install_package() {
    if [[ $# -lt 5 ]]; then
        log_error "install_package requires at least 5 arguments"
        log_debug "Args: $*"
        log_error "Usage: install_package package_name version gcc_version qualifiers arch"
        return 1
    fi
    local package_name="${1}"
    local version="${2}"
    local gcc_version="${3}"
    local qualifiers="${4}"
    local arch="${5:-"${SPACK_ARCH:-linux-almalinux9-x86_64_v2}"}"

    # Determine number of threads to use

    local build_threads=${BUILD_THREADS:-$(($(get_cpu_count) / 2))}
    
    # Build command options
    local build_opts="-y -j${build_threads} --fresh --no-cache --source"
    
    # Add any debug options if needed
    if [[ "${debug_build}" == true ]]; then
        build_opts+=" --debug"
    fi

    if ! ensure_log_directory; then
        log_warn "Cannot create log directory - continuing with limited logging"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file=${LOGS_DIR}/$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").${timestamp}-install.log
    
    log_info "Installing ${package_name}@${version} ${qualifiers} with GCC ${gcc_version}"
    log_info "Installation log: ${log_file}"

    local spack_cmd="spack install ${build_opts} ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    
    log_command "${spack_cmd}"
    if ! eval "${spack_cmd}" > "${log_file}" 2>&1; then
        log_error "Package installation failed: ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
        log_error "See installation log for details: ${log_file}"
        return 1
    fi

    log_success "Installed ${package_name}@${version} ${qualifiers} with GCC ${gcc_version}"
    return 0
}

# Build a package version with all dependencies
build_package_version() {
    if [[ $# -lt 8 ]]; then
        log_error "Missing required parameters for package processing"
        log_debug "Args: $*"
        log_error "Usage: build_package_version package_name version gcc_version qualifiers arch spack_dir spack_version mirror_base"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local spack_dir="$6"
    local spack_version="$7"
    local mirror_base="$8"


    if ! ensure_log_directory; then
        log_warn "Cannot create log directory - continuing with limited logging"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local build_log=${LOGS_DIR}/$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").${timestamp}-build.log
    
    log_info "Building ${package_name}@${version} ${qualifiers} with GCC ${gcc_version}"
    log_info "Build log: ${build_log}"

    export SPACK_GCC_VERSION="${gcc_version}"

    {
        if ! install_package "${package_name}" "${version}" "${gcc_version}" "${qualifiers}" "${arch}"; then
            log_error "Installation failed for ${package_name}@${version} ${qualifiers} ${arch} with GCC ${gcc_version}"
            return 1
        fi

        if ! reindex_spack_database; then
            log_warn "Spack database reindex failed - continuing anyway"
        fi
		if ! generate_package_spec "${package_name}" "${version}" "${gcc_version}" "${qualifiers}" "${arch}" "${spack_dir}" "${spack_version}"; then
            log_error "Package spec generation failed for ${package_name}@${version} ${qualifiers} ${arch} with GCC ${gcc_version}"
            return 1
        fi

        if ! generate_package_spec "${package_name}" "${version}" "${gcc_version}" "${qualifiers}" "${arch}" "${spack_dir}" "${spack_version}"; then
            log_error "Package spec generation failed for ${package_name}@${version} ${qualifiers} ${arch} with GCC ${gcc_version}"
            return 1
        fi

        if ! generate_package_hashes "${package_name}" "${version}" "${gcc_version}" "${qualifiers}" "${arch}" "${spack_dir}" "${spack_version}"; then
            log_error "Hash generation failed for ${package_name}@${version} ${qualifiers}"
            return 1
        fi

        if ! push_to_buildcache "${package_name}" "${version}" "${gcc_version}" "${qualifiers}" "${arch}" "${spack_dir}" "${spack_version}" "${mirror_base}"; then
            log_error "Failed to push to buildcache: ${package_name}@${version} ${qualifiers}"
            return 1
        fi

        local e_version=$(get_qualifier_e_version "${gcc_version}")
        local s_qualifier=$(get_s_qualifier "${qualifiers}")
        local mirror_path="${mirror_base}/${s_qualifier}-${e_version}/"
        log_debug "Pushing to buildcache at: ${mirror_path}"

        if ! update_buildcache_index "${spack_dir}" "${spack_version}" "${mirror_path}"; then
            log_error "Failed to update buildcache index for ${package_name}@${version} ${qualifiers}"
            return 1
        fi

        log_success "Successfully built ${package_name}@${version} ${qualifiers} with GCC ${gcc_version}"
    } 2>&1 | tee -a "${build_log}"

    local result=${PIPESTATUS[0]}

    if [[ $result -eq 0 ]]; then
        log_info "Build completed successfully - log saved to ${build_log}"
    else
        log_error "Build failed with status $result - see log: ${build_log}"
    fi

    return $result
}

# Run the DAQ build process with the specified configuration
run_daq_build() {
    local config_file="$1"
    local var_list="SOFTWARE_BASE:SPACK_DIR:SPACK_VERSION:SPACK_MIRROR_BASE:DAQ_SUITE_NAME:DAQ_SUITE_VERSIONS"
    
    if ! create_default_config "${config_file}"; then
        return 1
    fi

    log_debug "Loading configuration from ${config_file}"
    
    if ! load_build_config "${config_file}" "${var_list}"; then
        log_error "Failed to load configuration from ${config_file}"
        return 1
    fi

    local software_base="${SOFTWARE_BASE}"
    local spack_dir="${SPACK_DIR}"
    local spack_version="${SPACK_VERSION}"
    local spack_mirror_base="${SPACK_MIRROR_BASE}"
    local daq_suite_name="${DAQ_SUITE_NAME}"
    local versions_str="${DAQ_SUITE_VERSIONS}"

    local spack_micro_arch=${SPACK_MICRO_ARCH:-"v2"}
    local build_threads=${BUILD_THREADS:-$(($(get_cpu_count) / 2))}
    local debug_build=${DEBUG_BUILD:-false}

    if ! ensure_log_directory; then
        log_warn "Cannot create log directory - continuing with limited logging"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local build_log="${LOGS_DIR}/build.${timestamp}.log"
    exec > >(tee -a "${build_log}") 2>&1
    log_info "Starting build process - logging to ${build_log}"

    parse_arguments "$@"
    setup_signal_handlers

    if ! ensure_mirror_directories "$spack_dir" "$spack_version" "$spack_mirror_base"; then
        log_error "Mirror directory setup failed - cannot continue"
        exit 1
    fi

    log_info "Starting ${daq_suite_name} build process"
    log_debug "Spack directory: ${spack_dir}/${spack_version}"
    log_debug "Spack mirror: ${spack_mirror_base}"

    # Parse versions_str and process each entry
    # Format: version:qualifier:compiler:standard,\\
    #         version:qualifier:compiler:standard
    local failures=0
    
    IFS=',' read -ra configurations <<< "$versions_str"
    
    log_info "Building ${#configurations[@]} configurations from DAQ_SUITE_VERSIONS"
    
    for config in "${configurations[@]}"; do
        IFS=':' read -ra config_parts <<< "$config"
        
        if [[ ${#config_parts[@]} -ne 4 ]]; then
            log_error "Invalid configuration format: ${config}, expected version:qualifier:compiler:standard"
            failures=$((failures + 1))
            continue
        fi
        
        local version="${config_parts[0]}"
        local qualifier="${config_parts[1]}"
        local compiler="${config_parts[2]}"
        local cxxstd="${config_parts[3]}"
        
        # Extract gcc version from compiler string (e.g., gcc13.1.0 -> 13.1.0)
        local gcc_version="${compiler#gcc}"

        # Format qualifiers for spack commands
        # Pass the qualifier directly to format_spack_qualifiers
        # The function will handle any 's' prefix already in the qualifier
        local qualifiers=$(format_spack_qualifiers "${qualifier}" "${cxxstd}")
        
        log_info "Building configuration: ${daq_suite_name}@${version} with ${qualifiers} using ${compiler}"
        
        # Setup spack environment with the proper gcc version for this configuration
        if ! initialize_spack_environment "$spack_dir" "$spack_version" "$gcc_version" "$spack_micro_arch" "$build_threads" "$debug_build"; then
            log_error "Failed to initialize Spack environment for ${daq_suite_name}@${version} with ${qualifiers} using ${compiler}"
            failures=$((failures + 1))
            continue
        fi
        
        local spack_arch="linux-$(spack arch -o)-x86_64_${spack_micro_arch}"
        
        if ! build_package_version "$daq_suite_name" "$version"  "$gcc_version" "$qualifiers" "$spack_arch" "$spack_dir" "$spack_version" "$spack_mirror_base"; then
            log_error "Failed to build ${daq_suite_name}@${version} with ${qualifiers} using ${compiler}"
            failures=$((failures + 1))
        fi
    done

    if [[ $failures -gt 0 ]]; then
        log_warn "Completed with $failures failed package combinations"
        exit 1
    fi

    log_success "Build process completed successfully"
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides build functions for Spack packages."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 