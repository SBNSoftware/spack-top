#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_BUILD_ANYDAQ_SUITE_SH_:-0}" -eq 1 ]]; then
    return 0
fi
_BUILD_ANYDAQ_SUITE_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/spack-functions.sh"

print_anydaq_usage() {
    local script_name="$1"
    local package_name="$2"
    
    print_usage "${script_name}" "Build and publish ${package_name} packages to buildcache." \
        "" \
        "    VERSIONS            Optional list of versions to process (default: predefined list)" \
        ""
}

install_package() {
    local version="$1"
    local qualifier="$2"
    local package="$3"
    local gcc_version="$4"
    local cxxstd="$5"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for package installation"
        return 1
    fi

    if ! ensure_log_directory; then
        log_warn "Cannot create log directory - continuing with limited logging"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${LOGS_DIR}/${package}-${version}-s${qualifier}-gcc${gcc_version}-cxxstd${cxxstd}-${SPACK_OS}.${timestamp}-install.log"

    # Remove 's' prefix if present in qualifier
    qualifier="${qualifier#s}"

    # Format the C++ standard parameter if provided
    local cxxstd_param=""
    if [[ -n "$cxxstd" ]]; then
        # Extract just the number from c++XX format
        local cxxstd_num="${cxxstd#c++}"
        cxxstd_param="cxxstd=${cxxstd_num}"
        log_info "Installing ${package}@${version} s=${qualifier} ${cxxstd_param} with GCC ${gcc_version}"
    else
        log_info "Installing ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
    fi
    
    log_info "Installation log: ${log_file}"
    
    if [[ -n "$cxxstd_param" ]]; then
        log_command "spack install ${SPACK_INSTALL_OPTS} ${package}@${version} s=${qualifier} ${cxxstd_param} arch=${SPACK_ARCH} %gcc@${gcc_version}"
        if ! spack install ${SPACK_INSTALL_OPTS} "${package}@${version}" "s=${qualifier}" "${cxxstd_param}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" > "${log_file}" 2>&1; then
            log_error "Package installation failed: ${package}@${version} s=${qualifier} ${cxxstd_param}"
            log_error "See installation log for details: ${log_file}"
            return 1
        fi
    else
        log_command "spack install ${SPACK_INSTALL_OPTS} ${package}@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${gcc_version}"
        if ! spack install ${SPACK_INSTALL_OPTS} "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" > "${log_file}" 2>&1; then
            log_error "Package installation failed: ${package}@${version} s=${qualifier}"
            log_error "See installation log for details: ${log_file}"
            return 1
        fi
    fi

    if [[ -n "$cxxstd_param" ]]; then
        log_success "Installed ${package}@${version} s=${qualifier} ${cxxstd_param} with GCC ${gcc_version}"
    else
        log_success "Installed ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
    fi
    return 0
}

generate_package_spec() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    local package="$5"
    local gcc_version="$6"
    local cxxstd="$7"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for spec generation"
        return 1
    fi

    # Remove 's' prefix if present in qualifier
    qualifier="${qualifier#s}"

    local hash_dir="${spack_dir}/${spack_version}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Cannot create hash directory: ${hash_dir}"
            return 1
        }
    fi

    local cxxstd_suffix=""
    local cxxstd_param=""
    if [[ -n "$cxxstd" ]]; then
        local cxxstd_num="${cxxstd#c++}"
        cxxstd_param="cxxstd=${cxxstd_num}"
        cxxstd_suffix="-${cxxstd}"
    fi

    local spec_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${gcc_version}${cxxstd_suffix}-${SPACK_OS}.txt"

    if [[ -n "$cxxstd_param" ]]; then
        log_info "Generating spec for ${package}@${version} s=${qualifier} ${cxxstd_param} with GCC ${gcc_version}"
    else
        log_info "Generating spec for ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
    fi

    if ! cd "${hash_dir}"; then
        log_error "Cannot access hash directory: ${hash_dir}"
        return 1
    fi

    if [[ -n "$cxxstd_param" ]]; then
        log_command "spack spec ${package}@${version} s=${qualifier} ${cxxstd_param} arch=${SPACK_ARCH} %gcc@${gcc_version} > ${spec_file}"
        if ! spack spec "${package}@${version}" "s=${qualifier}" "${cxxstd_param}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" > "${spec_file}"; then
            log_error "Spec generation failed for ${package}@${version} s=${qualifier} ${cxxstd_param}"
            return 1
        fi
    else
        log_command "spack spec ${package}@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${gcc_version} > ${spec_file}"
        if ! spack spec "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" > "${spec_file}"; then
            log_error "Spec generation failed for ${package}@${version} s=${qualifier}"
            return 1
        fi
    fi

    log_success "Spec saved to: ${spec_file}"
    return 0
}

generate_package_hashes() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    local package="$5"
    local gcc_version="$6"
    local cxxstd="$7"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for hash generation"
        return 1
    fi

    # Remove 's' prefix if present in qualifier
    qualifier="${qualifier#s}"

    local hash_dir="${spack_dir}/${spack_version}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Cannot create hash directory: ${hash_dir}"
            return 1
        }
    fi

    local cxxstd_suffix=""
    local cxxstd_param=""
    if [[ -n "$cxxstd" ]]; then
        local cxxstd_num="${cxxstd#c++}"
        cxxstd_param="cxxstd=${cxxstd_num}"
        cxxstd_suffix="-${cxxstd}"
    fi

    local hash_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${gcc_version}${cxxstd_suffix}-${SPACK_OS}-hashes.txt"

    if [[ -n "$cxxstd_param" ]]; then
        log_info "Generating hashes for ${package}@${version} s=${qualifier} ${cxxstd_param} with GCC ${gcc_version}"
    else
        log_info "Generating hashes for ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
    fi

    if ! cd "${hash_dir}"; then
        log_error "Cannot access hash directory: ${hash_dir}"
        return 1
    fi

    log_command "spack unload --all"
    spack unload --all || {
        log_warn "Failed to unload all packages - proceeding anyway"
    }

    local package_count
    if [[ -n "$cxxstd_param" ]]; then
        if ! package_count=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "${cxxstd_param}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" | grep -Eo '/daq/software/.*$' | wc -l); then
            log_error "Cannot determine package count - check Spack installation"
            return 1
        fi
    else
        if ! package_count=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" | grep -Eo '/daq/software/.*$' | wc -l); then
            log_error "Cannot determine package count - check Spack installation"
            return 1
        fi
    fi

    if [[ $package_count -gt 1 ]]; then
        log_debug "Multiple package instances found - selecting latest"

        local package_paths
        if [[ -n "$cxxstd_param" ]]; then
            if ! package_paths=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "${cxxstd_param}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" | grep -Eo '/daq/software/.*$'); then
                log_error "Cannot list package paths - check Spack database"
                return 1
            fi
        else
            if ! package_paths=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}" | grep -Eo '/daq/software/.*$'); then
                log_error "Cannot list package paths - check Spack database"
                return 1
            fi
        fi

        local latest_package
        if ! latest_package=$(/bin/ls -ldtr $package_paths 2>/dev/null | tail -1 | awk '{print $NF}'); then
            log_error "Cannot determine latest package - check file system permissions"
            return 1
        fi

        local hash
        if ! hash=$(basename "$latest_package" | grep -Eo '[^-]+$'); then
            log_error "Cannot extract hash from package path - unexpected path format"
            return 1
        fi

        log_command "spack load \"${package}@${version}\" \"/${hash}\""
        if ! spack load "${package}@${version}" "/${hash}"; then
            log_error "Cannot load package: ${package}@${version}/${hash}"
            return 1
        fi
    else
        if [[ -n "$cxxstd_param" ]]; then
            log_command "spack load \"${package}@${version}\" \"s=${qualifier}\" \"${cxxstd_param}\" \"arch=${SPACK_ARCH}\" \"%gcc@${gcc_version}\""
            if ! spack load "${package}@${version}" "s=${qualifier}" "${cxxstd_param}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}"; then
                log_error "Cannot load package: ${package}@${version} s=${qualifier} ${cxxstd_param}"
                return 1
            fi
        else
            log_command "spack load \"${package}@${version}\" \"s=${qualifier}\" \"arch=${SPACK_ARCH}\" \"%gcc@${gcc_version}\""
            if ! spack load "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${gcc_version}"; then
                log_error "Cannot load package: ${package}@${version} s=${qualifier}"
                return 1
            fi
        fi
    fi

    log_command "spack find -ldfv --loaded > ${hash_file}"
    if ! spack find -ldfv --loaded > "${hash_file}"; then
        log_error "Cannot save loaded package info - check file system permissions"
        return 1
    fi

    if [[ ! -s "${hash_file}" ]]; then
        log_error "Generated hash file is empty: ${hash_file}"
        return 1
    fi

    log_success "Hashes saved to: ${hash_file}"
    return 0
}

push_to_buildcache() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    local package="$6"
    local gcc_version="$7"
    local cxxstd="$8"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for buildcache push"
        return 1
    fi

    # Remove 's' prefix if present in qualifier
    qualifier="${qualifier#s}"

    local e_version
    e_version=$(get_qualifier_e_version "$gcc_version")

    local hash_dir="${spack_dir}/${spack_version}/hashes"
    
    local cxxstd_suffix=""
    if [[ -n "$cxxstd" ]]; then
        cxxstd_suffix="-${cxxstd}"
    fi
    
    local hash_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${gcc_version}${cxxstd_suffix}-${SPACK_OS}-hashes.txt"
    local mirror_path="${mirror_base}/s${qualifier}-${e_version}/"

    if [[ -n "$cxxstd" ]]; then
        # Extract just the number from c++XX format
        local cxxstd_num="${cxxstd#c++}"
        log_info "Pushing ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num} to buildcache at ${mirror_path}"
    else
        log_info "Pushing ${package}@${version} s=${qualifier} to buildcache at ${mirror_path}"
    fi

    if ! cd "${hash_dir}"; then
        log_error "Cannot access hash directory: ${hash_dir}"
        return 1
    fi

    if [[ ! -f "${hash_file}" ]]; then
        log_error "Hash file not found: ${hash_file}"
        return 1
    fi

    if [[ ! -s "${hash_file}" ]]; then
        log_error "Hash file is empty: ${hash_file}"
        return 1
    fi

    if [[ ! -d "${mirror_path}" ]]; then
        log_info "Creating mirror directory: ${mirror_path}"
        mkdir -p "${mirror_path}" || {
            log_error "Cannot create mirror directory: ${mirror_path}"
            return 1
        }
    fi

    local hashes
    hashes=$(grep -vE "^(--|$)" < "${hash_file}" | awk '{printf ("/%s\n", $1) }')

    if [[ -z "${hashes}" ]]; then
        log_error "No hashes found in hash file: ${hash_file}"
        return 1
    fi

    local hash_count=0
    local first_hash=true
    local already_in_cache=false
    local continue_pushing=true

    while IFS= read -r hash; do
        if [[ "$continue_pushing" != true ]]; then
            break
        fi

        log_command "spack buildcache push --only package \"${mirror_path}\" \"${hash}\""

        local output
        output=$(spack buildcache push --only package "${mirror_path}" "${hash}" 2>&1)
        local push_status=$?

        if [[ $push_status -eq 0 ]]; then
            if [[ "$output" == *"The spec is already in the buildcache"* ]] && [[ "$first_hash" == true ]]; then
                log_warn "${package}@${version} s=${qualifier} already exists in buildcache"
                already_in_cache=true
                first_hash=false
                log_warn "Skipping remaining hashes - top package already in buildcache"
                break
            fi
        else
          log_error "Failed to push hash ${hash} to buildcache"
          log_error "Error: ${output}"
        fi

        ((hash_count++))
    done <<< "${hashes}"

    if [[ $hash_count -eq 0 ]] && [[ "$already_in_cache" != true ]]; then
        log_error "No hashes were pushed to buildcache - operation failed"
        return 1
    elif [[ "$already_in_cache" == true ]]; then
        log_warn "Package already in buildcache - pushed ${hash_count} additional hashes"
    else
        log_success "Pushed ${hash_count} hashes to buildcache"
    fi

    return 0
}

build_package_version() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    local package="$6"
    local gcc_version="$7"
    local cxxstd="$8"

    # Remove 's' prefix if present in qualifier
    qualifier="${qualifier#s}"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" || -z "$gcc_version" ]]; then
        log_error "Missing required parameters for package processing"
        return 1
    fi

    if ! ensure_log_directory; then
        log_warn "Cannot create log directory - continuing with limited logging"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local build_log="${LOGS_DIR}/${package}-${version}-s${qualifier}-gcc-${gcc_version}"
    
    if [[ -n "$cxxstd" ]]; then
        build_log="${build_log}-${cxxstd}"
    fi
    
    build_log="${build_log}-${SPACK_OS}.${timestamp}-build.log"

    if [[ -n "$cxxstd" ]]; then
        local cxxstd_num="${cxxstd#c++}"
        log_info "Building ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num} with GCC ${gcc_version}"
    else
        log_info "Building ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
    fi
    
    log_info "Build log: ${build_log}"

    export SPACK_GCC_VERSION="${gcc_version}"
    log_debug "Set SPACK_GCC_VERSION=${SPACK_GCC_VERSION} for this process"

    {
        if ! install_package "$version" "$qualifier" "$package" "$gcc_version" "$cxxstd"; then
            if [[ -n "$cxxstd" ]]; then
                local cxxstd_num="${cxxstd#c++}"
                log_error "Installation failed for ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num}"
            else
                log_error "Installation failed for ${package}@${version} s=${qualifier}"
            fi
            return 1
        fi

        if ! reindex_spack_database; then
            log_warn "Spack database reindex failed - continuing anyway"
        fi

        if ! generate_package_spec "$spack_dir" "$spack_version" "$version" "$qualifier" "$package" "$gcc_version" "$cxxstd"; then
            if [[ -n "$cxxstd" ]]; then
                local cxxstd_num="${cxxstd#c++}"
                log_error "Spec generation failed for ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num}"
            else
                log_error "Spec generation failed for ${package}@${version} s=${qualifier}"
            fi
            return 1
        fi

        if ! generate_package_hashes "$spack_dir" "$spack_version" "$version" "$qualifier" "$package" "$gcc_version" "$cxxstd"; then
            if [[ -n "$cxxstd" ]]; then
                local cxxstd_num="${cxxstd#c++}"
                log_error "Hash generation failed for ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num}"
            else
                log_error "Hash generation failed for ${package}@${version} s=${qualifier}"
            fi
            return 1
        fi

        if ! push_to_buildcache "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier" "$package" "$gcc_version" "$cxxstd"; then
            if [[ -n "$cxxstd" ]]; then
                local cxxstd_num="${cxxstd#c++}"
                log_error "Failed to push to buildcache: ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num}"
            else
                log_error "Failed to push to buildcache: ${package}@${version} s=${qualifier}"
            fi
            return 1
        fi

        local e_version
        e_version=$(get_qualifier_e_version "$gcc_version")
        local mirror_path="${mirror_base}/s${qualifier}-${e_version}/"

        if ! update_buildcache_index "$spack_dir" "$spack_version" "$mirror_path"; then
            log_error "Failed to update buildcache index for s${qualifier}-${e_version}"
            return 1
        fi

        if [[ -n "$cxxstd" ]]; then
            local cxxstd_num="${cxxstd#c++}"
            log_success "Successfully built ${package}@${version} s=${qualifier} cxxstd=${cxxstd_num} with GCC ${gcc_version}"
        else
            log_success "Successfully built ${package}@${version} s=${qualifier} with GCC ${gcc_version}"
        fi
    } 2>&1 | tee -a "${build_log}"

    local result=${PIPESTATUS[0]}

    if [[ $result -eq 0 ]]; then
        log_info "Build completed successfully - log saved to ${build_log}"
    else
        log_error "Build failed with status $result - see log: ${build_log}"
    fi

    return $result
}

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
        
        log_info "Building configuration: ${daq_suite_name}@${version} ${qualifier} with ${compiler} standard ${cxxstd}"
        
        # Setup spack environment with the proper gcc version for this configuration
        if ! setup_spack_environment "$spack_dir" "$spack_version" "$gcc_version"; then
            log_error "Failed to initialize Spack environment with GCC ${gcc_version}"
            failures=$((failures + 1))
            continue
        fi
        
        if ! build_package_version "$spack_dir" "$spack_version" "$spack_mirror_base" "$version" "$qualifier" "$daq_suite_name" "$gcc_version" "$cxxstd"; then
            log_error "Failed to build ${daq_suite_name}@${version} ${qualifier} with ${compiler} standard ${cxxstd}"
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

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f print_anydaq_usage
    export -f install_package
    export -f generate_package_spec
    export -f generate_package_hashes
    export -f push_to_buildcache
    export -f build_package_version
    export -f run_daq_build
    
    log_debug "Exported functions from $(basename "${BASH_SOURCE[0]}")"
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides common functions for building DAQ packages"
    log_info "It should be sourced by other scripts, not executed directly"
    exit 0
fi 