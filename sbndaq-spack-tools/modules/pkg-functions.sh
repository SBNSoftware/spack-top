#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_PKG_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _PKG_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"

# Select a package version from available versions
select_package_version() {
    #if less than 5 arguments are provided, then complain
    if [[ $# -lt 5 ]]; then
        log_error "select_package_version requires at least 5 arguments"
        log_debug "Args: $*"
        log_error "Usage: select_package_version package_name preferred_version gcc_version qualifiers arch"
        return 1
    fi

    local package_name="$1"
    local preferred_version="$4"
    local gcc_version="$2"
    local qualifiers="$3"
    local arch="$5"
    
    
    if [[ -z "${preferred_version}" ]]; then
        # First check if version is already in DAQ_PKG_VERSIONS
        if [[ -n "${DAQ_PKG_VERSIONS:-}" ]]; then
            local first_version
            first_version=$(echo "${DAQ_PKG_VERSIONS%%,*}" | cut -d':' -f1)
            if [[ -n "${first_version}" ]]; then
                preferred_version="${first_version}"
                log_debug "Using version from DAQ_PKG_VERSIONS: ${preferred_version}"
                echo "${preferred_version}"
                return 0
            fi
        fi
        
        # Fall back to querying Spack
        local spack_find_command="spack find --no-groups ${package_name}"
        if [[ -n "${formatted_qualifier}" ]]; then
            spack_find_command+=" ${formatted_qualifier}"
        fi
        if [[ -n "${cpp_standard_param}" ]]; then
            spack_find_command+=" ${cpp_standard_param}"
        fi
        spack_find_command+=" %gcc@${compiler_version} arch=${target_platform}"
        
        log_command "${spack_find_command}"
        
        local find_output
        if ! find_output=$(eval "${spack_find_command}" 2>&1); then
            log_error "Failed to find ${package_name} versions: ${find_output}"
            return 1
        fi
        
        preferred_version=$(echo "${find_output}" | grep -o '@[0-9a-zA-Z._-]*' | 
                         cut -d'@' -f2 | sort -ru | head -1)
        
        if [[ -z "${preferred_version}" ]]; then
            log_error "No ${package_name} versions found"
            return 1
        fi
    fi
    
    # If non-interactive, return the preferred version directly
    if [[ "${NON_INTERACTIVE:-false}" == "true" ]]; then
        echo "${preferred_version}"
        return 0
    fi
    
    # Otherwise prompt for confirmation/selection
    read_with_timeout "Enter version (default: ${preferred_version}): " "${preferred_version}"
}

# Set up development packages for a given package
setup_development_packages() {
    #if less than 6 arguments are provided, then complain
    if [[ $# -lt 6 ]]; then
        log_error "setup_development_packages requires at least 6 arguments"
        log_debug "Args: $*"
        log_error "Usage: setup_development_packages package_name version compiler_version qualifiers arch dev_packages_list spack_dev_top_dir"
        return 1
    fi
    
    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4" 
    local arch="$5"
    local dev_packages_list="$6"
    local spack_dev_top_dir="$7"

    
    local spec_output_path=$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").pkgs.txt
    log_debug "Working directory: $(pwd)"
    log_debug "Downloading package sources for ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    log_command "spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} > ${spec_output_path}"

    if ! spack spec "${package_name}@${version}" ${qualifiers} "arch=${arch}" "%gcc@${gcc_version}" > "${spec_output_path}"; then
        log_error "Failed to run spack spec"
        return 1
    fi

    #remove the s=NNN qualifier from qualifiers
    local filtered_qualifiers=$(echo "${qualifiers}" | sed 's/s=[0-9]*//g')

    unset GIT_CONFIG_GLOBAL
    unset GIT_EXEC_PATH

    # Set up development packages
    log_debug "Setting up development environment..."
    IFS=',' read -ra CHECKOUT_PACKAGES <<< "${dev_packages_list}"
    
    for package in "${CHECKOUT_PACKAGES[@]}"; do
        local pkg_name pkg_version
        pkg_name=$(echo "${package}" | cut -d'@' -f1)
        pkg_version=$(echo "${package}" | cut -d'@' -f2)
        pkg_version_from_spec=$(grep -oP "${pkg_name}@\K[^%]*" ${spec_output_path})
        
        if [[ -z "${pkg_version}" || "${pkg_version}" == "spec" ]]; then
            pkg_version=${pkg_version_from_spec}
        fi

        log_debug "Setting up development environment for: ${pkg_name}@${pkg_version}"
        log_command "spack develop --clone --force FORCE --path ../srcs/${pkg_name} ${pkg_name}@develop ${filtered_qualifiers} %gcc@${gcc_version}"
        if ! spack develop --clone --force FORCE --path "../srcs/${pkg_name}" "${pkg_name}@develop" ${filtered_qualifiers} "%gcc@${gcc_version}"; then
            log_error "Cannot set up development environment for: ${pkg_name}"
            exit 1
        fi
        
        if ! checkout_package "${pkg_name}" "${pkg_version}"; then
            exit 1
        fi
        
        # No need to add qualifier to the develop command since we're using the version from spec
        log_command "spack develop --no-clone --path ../srcs/${pkg_name} ${pkg_name}@${pkg_version_from_spec} ${filtered_qualifiers} %gcc@${gcc_version}"
        if ! spack develop --no-clone --path "../srcs/${pkg_name}" "${pkg_name}@${pkg_version_from_spec}" ${filtered_qualifiers} "%gcc@${gcc_version}"; then
            log_error "Cannot set up development environment for: ${pkg_name}"
            exit 1
        fi
    done

    # Initialize Git repository in the src directory
    if ! cd srcs; then
        log_error "Cannot access srcs directory"
        exit 1
    fi
    
    git config --global init.defaultBranch main
    if ! git init >/dev/null 2>&1; then
        log_error "Cannot initialize Git repository in srcs directory"
        exit 1
    fi
    
    if ! cd - >/dev/null; then
        log_error "Cannot return to previous directory"
        exit 1
    fi
   
    return 0
}

# Checkout a specific package version
checkout_package() {
    local pkg_name="$1"
    local pkg_version="$2"
    local enable_git_push="${ENABLE_GIT_PUSH:-false}"
    
    if ! cd "srcs/${pkg_name}"; then
        log_error "Cannot access package directory: srcs/${pkg_name}"
        return 1
    fi
    
    if [[ "${enable_git_push}" == true ]]; then
        log_command "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -T git@github.com"
        if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -T git@github.com >/dev/null 2>&1; then
            log_warn "Failed to authenticate to github.com - setting ENABLE_GIT_PUSH to false"
            log_info "Please check your ssh key configuration and try again"
            enable_git_push=false        
        fi
    fi

    # Try different branch/tag strategies
    if [[ "${pkg_version}" == *"v"* || "${pkg_version}" == *"V"* ]]; then
        if git checkout "${pkg_version}" >/dev/null 2>&1; then
            log_command "git checkout ${pkg_version}"
            log_info "Checked out ${pkg_version} tag for ${pkg_name}"
        elif git checkout "release/${pkg_version}" >/dev/null 2>&1; then
                log_command "git checkout release/${pkg_version}"
                log_info "Checked out release/${pkg_version} branch for ${pkg_name}"
            else
                git checkout -b "release/${pkg_version}" >/dev/null 2>&1
                log_command "git checkout -b release/${pkg_version}"
                log_info "Created and checked out release/${pkg_version} branch for ${pkg_name}"
                if [[ "${enable_git_push}" == true ]]; then
                    if git push origin "release/${pkg_version}" >/dev/null 2>&1; then
                        log_command "git push origin release/${pkg_version}"
                        log_info "Pushed release/${pkg_version} branch to origin"
                    else
                        log_warn "Failed to push release/${pkg_version} branch to origin"
                    fi
                fi
            fi
        elif git checkout "feature/${pkg_version}" >/dev/null 2>&1; then
            log_command "git checkout feature/${pkg_version}"
            log_info "Checked out feature/${pkg_version} branch for ${pkg_name}"
    else 
        git checkout -b "feature/${pkg_version}" >/dev/null 2>&1
        log_command "git checkout -b feature/${pkg_version}"
        log_info "Created and checked out feature/${pkg_version} branch for ${pkg_name}"
        if [[ "${enable_git_push}" == true ]]; then
            if git push origin "feature/${pkg_version}" >/dev/null 2>&1; then
                log_command "git push origin feature/${pkg_version}"
                log_info "Pushed feature/${pkg_version} branch to origin"
            else
                log_warn "Failed to push feature/${pkg_version} branch to origin"
            fi
        fi
    fi

    if ! cd - >/dev/null; then
        log_error "Cannot return to previous directory"
        return 1
    fi

    return 0
}

# Generate a buildcache for a package
generate_package_buildcache() {
    #if less than  8 arguments are provided, then complain
    if [[ $# -lt 6 ]]; then
        log_error "generate_package_buildcache requires at least 6 arguments"
        log_debug "Args: $*"
        log_error "Usage: generate_package_buildcache package_name version gcc_version qualifiers arch spack_env_top_dir"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local spack_env_top_dir="$6"

    
    local buildcache_output_path="${spack_env_top_dir}/spack_mirrors/${package_name}/${version}"

    log_info "Creating buildcache at: ${buildcache_output_path}"
    mkdir -p "${buildcache_output_path}"
    
    local spack_find_command="spack find -lpd ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"

    log_command "${spack_find_command}"
    while IFS= read -r line; do
        local pkg_hash pkg_spec
        pkg_hash=$(echo "$line" | awk '{print $1}')
        pkg_spec=$(echo "$line" | awk '{print $2}')
        
        if [[ -n "${pkg_hash}" && -n "${pkg_spec}" ]]; then
            log_command "spack buildcache push --unsigned --only package ${buildcache_output_path} ${pkg_spec} ${pkg_hash}"
            spack buildcache push --unsigned --only package "${buildcache_output_path}" "${pkg_spec}" "${pkg_hash}" || \
                log_warn "Failed to push to buildcache: ${pkg_spec}"
        fi
    done < <(eval "${spack_find_command}" | grep -v "==>" | grep "/${spack_env_top_dir}/" | awk '{printf("/%s %s\n", $1, $2)}')
    
    update_buildcache "${package_name}" "${version}" "${spack_env_top_dir}" "${buildcache_output_path}"
}

# Update the buildcache index
update_buildcache() {
    #if less than 4 arguments are provided, then complain
    if [[ $# -lt 4 ]]; then
        log_error "update_buildcache requires at least 4 arguments"
        log_debug "Args: $*"
        log_error "Usage: update_buildcache package_name version spack_env_top_dir buildcache_output_path"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local spack_env_top_dir="$3"
    local buildcache_output_path="$4"
    

    cat > "${spack_env_top_dir}/spack/linux/mirrors.yaml" << EOF
mirrors:
  local_mirror:
    url: file://${PWD}/${buildcache_output_path}
EOF

    log_info "Updating buildcache index..."
    log_command "spack buildcache update-index ${buildcache_output_path}"
    spack buildcache update-index "${buildcache_output_path}" || log_warn "Cannot update buildcache index"
    
    log_info "Listing packages in buildcache..."
    log_command "spack buildcache list -lva ${package_name}@${version}"
    spack buildcache list -lva "${package_name}@${version}" || log_warn "Cannot list buildcache contents"
}

# Build packages in the specified environment
build_packages() {
    #if less than 9 arguments are provided, then complain
    if [[ $# -lt 9 ]]; then
        log_error "build_packages requires at least 9 arguments"
        log_debug "Args: $*"
        log_error "Usage: build_packages package_name version gcc_version qualifiers arch checkout_packages build_threads debug_build spack_env_top_dir"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    local checkout_packages="$6"
    local build_threads="$7"
    local debug_build="$8"
    local spack_env_top_dir="$9"

    log_info "Building packages for ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    log_warn "This step may take several minutes depending on NFS system speed"
    log_debug "Working directory: $(pwd)"
    
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


    local build_lock=$(format_path_name "${spack_env_top_dir}/${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").build_lock.txt

    if [[ -f "${build_lock}" ]]; then
        read_with_timeout "Build already succeeded - skip build? (Y/n): " "y"
        if [[ ${skip_build,,} == "n" ]]; then   
            log_info "Ok, skipping build, you can always run this script again to build the package"
            generate_package_buildcache  "${package_name}"  "${version}"  "${gcc_version}"  "${qualifiers}"  "${arch}"  "${spack_env_top_dir}"
            return 0
        else
            log_info "Removing build lock, and re-running build"
            rm -f "${build_lock}"
        fi
    fi

    local spec_file=$(format_path_name "${spack_env_top_dir}/${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").pkgs.txt

    log_command "spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} > ${spec_file}"
    spack spec "${package_name}@${version}" ${qualifiers} "arch=${arch}" "%gcc@${gcc_version}" > ${spec_file}
    if ! spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} > ${spec_file}; then
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
                    log_debug "Build succeeded - creating buildcache"
                    touch "${build_success}"
                    continue
                fi
            else
                log_warn "Invalid selection: ${choice}"
            fi
        done
        
        local continue_response
        read -p "Continue with buildcache creation? (y/n): " continue_response
        if [[ ${continue_response,,} == "y" ]]; then
            generate_package_buildcache  "${package_name}" "${version}"  "${gcc_version}"  "${qualifiers}" "${arch}" "${spack_env_top_dir}"
            return 0
        else
            log_error "Build process aborted by user"
            return 1
        fi
    else
        log_debug "Build succeeded - creating buildcache"
        touch "${build_lock}"
        generate_package_buildcache  "${package_name}"  "${version}"  "${gcc_version}"  "${qualifiers}"  "${arch}"  "${spack_env_top_dir}"
        return 0
    fi
}

# Function to download package source code
download_package_source() {
    #if less than 5 arguments are provided, then complain
    if [[ $# -lt 5 ]]; then
        log_error "download_package_source requires at least 5 arguments"
        log_debug "Args: $*"
        log_error "Usage: download_package_source package_name version gcc_version qualifiers arch"
        return 1
    fi

    local package_name="$1"
    local version="$2"
    local gcc_version="$3"
    local qualifiers="$4"
    local arch="$5"
    
    log_debug "Downloading package source for ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version}"
    
    # Create spec file name
    local spec_file=$(format_path_name "${package_name}-${version}" "${gcc_version}" "${qualifiers}" "${arch}" "-").spec.txt
    
    log_command "spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} > ${spec_file}"
    spack spec "${package_name}@${version}" ${qualifiers} "arch=${arch}" "%gcc@${gcc_version}" > ${spec_file}
    if ! spack spec ${package_name}@${version} ${qualifiers} arch=${arch} %gcc@${gcc_version} > ${spec_file}; then
        log_error "Cannot run spack spec"
        return 1
    fi
    
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides package management functions for Spack development."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 