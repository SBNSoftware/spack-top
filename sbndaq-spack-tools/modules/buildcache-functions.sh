#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_BUILDCACHE_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _BUILDCACHE_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"

# Generate a package specification file
generate_package_spec() {
    #complain if less than 7 arguments
    if [[ $# -lt 7 ]]; then
        log_error "Missing required parameters for spec generation"
        log_debug "Args: $*"
        log_error "Usage: generate_package_spec package_name version gcc_version qualifiers arch spack_dir spack_version"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local spack_dir="$6"
    local spack_version="$7"
   
    local hash_dir="${spack_dir}/${spack_version}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Cannot create hash directory: ${hash_dir}"
            return 1
        }
    fi


    local spec_file=$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").spec.txt

    log_info "Generating spec for ${package_name}@${version} ${qualifiers} arch=${arch} with GCC ${gcc_version}"


    if ! cd "${hash_dir}"; then
        log_error "Cannot access hash directory: ${hash_dir}"
        return 1
    fi

    log_debug "Working directory: $(pwd)"

    local spack_cmd="spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    log_command "${spack_cmd}"
    if ! eval "${spack_cmd}" > "${spec_file}"; then
        log_error "Spec generation failed for ${package_name}@${version} ${qualifiers}"
        return 1
    fi

    local packages_to_build=""
    if ! packages_to_build=$(cat "${spec_file}" | grep -v '\[[\+e\^]\]'); then
        log_error "Cannot determine packages to build, check the spec file: ${spec_file}"
        return 1
    fi

    IFS=$'\n' read -rd '' -a packages_to_build <<< "${packages_to_build}"

    if [[ -z "${packages_to_build:-}" ]]; then
        log_debug "All packages were already built, check the spec file: ${spec_file}"        
    else
        log_debug "Found ${#packages_to_build[@]} packages to build"    
        for package in "${packages_to_build[@]}"; do
            log_debug "Package to build: ${package}"
        done
    fi

    log_success "Spec saved to: ${spec_file}" 
    return 0
}

# Generate package hashes for buildcache
generate_package_hashes() {
    #complain if less than 7 arguments
    if [[ $# -lt 7 ]]; then
        log_error "Missing required parameters for hash generation"
        log_debug "Args: $*"
        log_error "Usage: generate_package_hashes package_name version gcc_version qualifiers arch spack_dir spack_version"
        return 1
    fi
    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local spack_dir="$6"
    local spack_version="$7"


    local hash_dir="${spack_dir}/${spack_version}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Cannot create hash directory: ${hash_dir}"
            return 1
        }
    fi

    local hash_file=$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").hashes.txt

    log_info "Generating hashes for ${package_name}@${version} ${qualifiers} with GCC ${gcc_version}"


    if ! cd "${hash_dir}"; then
        log_error "Cannot access hash directory: ${hash_dir}"
        return 1
    fi

    log_command "spack unload --all"
    spack unload --all || {
        log_warn "Failed to unload all packages - proceeding anyway"
    }

    local spack_cmd="spack find -lpfv ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    log_command "${spack_cmd}"
    local package_count
    if ! package_count=$(eval ${spack_cmd} 2>/dev/null | grep -Eo '/daq/software/.*$' | wc -l); then
        log_error "Cannot determine package count - check Spack installation"
        return 1
    fi

    if [[ $package_count -gt 1 ]]; then
        log_debug "Multiple package instances found - selecting latest"

        local spack_cmd="spack find -lpfv ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
        log_command "${spack_cmd}"
        local package_paths
        if ! package_paths=$(eval ${spack_cmd} 2>/dev/null | grep -Eo '/daq/software/.*$'); then
            log_error "Cannot list package paths - check Spack database"
            return 1
        fi

        local local_cmd="/usr/bin/ls -ldtr ${package_paths} 2>/dev/null | tail -1 | awk '{print \$NF}'"
        #log_command "${local_cmd}"
        local latest_package
        if ! latest_package=$(eval ${local_cmd} 2>/dev/null); then
            log_debug "Package paths: ${package_paths}"
            log_error "Cannot determine latest package - check file system permissions"
            return 1
        fi

        local hash
        if ! hash=$(basename "$latest_package" | grep -Eo '[^-]+$'); then
            log_debug "Latest package: ${latest_package}"
            log_error "Cannot extract hash from package path - unexpected path format"
            return 1
        fi

        local spack_cmd="spack load ${package_name}@${version} /${hash}"
        log_command "${spack_cmd}"

        if ! eval "${spack_cmd}" 2>/dev/null; then
            log_error "Cannot load package: ${package_name}@${version}/${hash}"
            return 1    
        fi
    else
        local spack_cmd="spack load ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
        log_command "${spack_cmd}"
        if ! eval "${spack_cmd}" 2>/dev/null; then
            log_error "Cannot load package: ${package_name}@${version} ${qualifiers}"
            return 1
        fi
    fi

    log_debug "Working directory: $(pwd)"
    local spack_cmd="spack find -ldfv --loaded > ${hash_file}"
    log_command "${spack_cmd}"
    if ! eval "${spack_cmd}" 2>/dev/null; then
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

# Push packages to buildcache
push_to_buildcache() {
    if [[ $# -lt 8 ]]; then
        log_error "Missing required parameters for hash generation"
        log_debug "Args: $*"
        log_error "Usage: push_to_buildcache package_name version gcc_version qualifiers arch spack_dir spack_version mirror_base"
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
    

    local e_version=$(get_qualifier_e_version "$gcc_version")
    local s_qualifier=$(get_s_qualifier "${qualifiers}")

    local hash_dir="${spack_dir}/${spack_version}/hashes"
        
    local hash_file=$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").hashes.txt
    local mirror_path="${mirror_base}/${s_qualifier}-${e_version}/"

    log_info "Pushing ${package_name}@${version} ${qualifiers} to buildcache at ${mirror_path}"
 
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

        local spack_cmd="spack buildcache push --only package ${mirror_path} ${hash}"
        log_command "${spack_cmd}"

        local output
        output=$(eval "${spack_cmd}" 2>&1)
        local push_status=$?

        if [[ $push_status -eq 0 ]]; then
            if [[ "$output" == *"The spec is already in the buildcache"* ]] && [[ "$first_hash" == true ]]; then
                log_warn "${package_name}@${version} ${qualifiers} already exists in buildcache"
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

# Update the buildcache index for a specific mirror path
update_buildcache_index() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_path="$3"

    if [[ -z "$mirror_path" || -z "$spack_dir" || -z "$spack_version" ]]; then
        log_error "Missing required parameters for buildcache index update"
        return 1
    fi

    log_info "Updating buildcache index for ${mirror_path}"

    local spack_cmd="spack buildcache update-index ${mirror_path}"
    log_command "${spack_cmd}"
    if ! eval "${spack_cmd}" 2>/dev/null; then
        log_error "Failed to update buildcache index"
        return 1
    fi

    log_success "Buildcache index updated successfully"
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides buildcache management functions for Spack."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 