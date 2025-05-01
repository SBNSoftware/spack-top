#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Guard against multiple sourcing
if [[ "${_SPACK_SETUP_ENVIRONMENT_SH_:-0}" -eq 1 ]]; then
    return 0
fi
_SPACK_SETUP_ENVIRONMENT_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"
source "${SCRIPT_DIR}/spack-functions.sh"

#
# Configuration file creation functions
#

create_config_files() {
    local dir_name="$1"
    
    log_info "Creating configuration directory structure..."
    if ! mkdir -p "${dir_name}/spack/linux" "${dir_name}/srcs"; then
        log_error "Failed to create directory structure in ${dir_name}"
        return 1
    fi

    create_upstreams_yaml "${dir_name}" || return 1
    create_config_yaml "${dir_name}" || return 1
    create_clang_format "${dir_name}" || return 1
    #create_compile_flags_txt "${dir_name}" || return 1
    create_repos_yaml "${dir_name}" || return 1
    create_packages_yaml "${dir_name}" || return 1
    create_compilers_yaml "${dir_name}" || return 1
    create_mpd_repo "${dir_name}" || return 1
    return 0
}

create_upstreams_yaml() {
    local dir_name="$1"
    local spack_packages_top="${SPACK_PACKAGES_TOP}"
    local yaml_file="${dir_name}/spack/linux/upstreams.yaml"
    
    log_debug "Creating upstreams.yaml file: ${yaml_file}"
    
    if ! cat > "${yaml_file}" << 'EOF'
upstreams:
  spack-instance-1:
    install_tree: ${SPACK_PACKAGES_TOP}
    modules:
      tcl: ${SPACK_PACKAGES_TOP}/modules
EOF
    then
        log_error "Failed to create upstreams.yaml file"
        return 1
    fi
    
    # Replace placeholders with actual values
    if ! sed -i "s|\${SPACK_PACKAGES_TOP}|${spack_packages_top}|g" "${yaml_file}"; then
        log_error "Failed to replace variables in upstreams.yaml"
        return 1
    fi
    
    return 0
}

create_config_yaml() {
    local dir_name="$1"
    local dev_envs_root_dir="${SPACK_DAQ_AREAS}"
    local yaml_file="${dir_name}/spack/config.yaml"
    
    log_debug "Creating config.yaml file: ${yaml_file}"
    
    if ! cat > "${yaml_file}" << 'EOF'
config:
  install_tree:
    root: ${SPACK_DAQ_AREAS}/${dir_name}/spack_packages
    padded_length: 255
EOF
    then
        log_error "Failed to create config.yaml file"
        return 1
    fi
    
    # Replace placeholders with actual values
    if ! sed -i "s|\${SPACK_DAQ_AREAS}|${dev_envs_root_dir}|g; s|\${dir_name}|${dir_name}|g" "${yaml_file}"; then
        log_error "Failed to replace variables in config.yaml"
        return 1
    fi
    
    return 0
}

create_clang_format() {
    local dir_name="$1"
    local format_file="${dir_name}/srcs/.clang-format"
    
    log_debug "Creating .clang-format file: ${format_file}"
    if ! cat > "${format_file}" << 'EOF'
DisableFormat: true
EOF
    then
        log_error "Failed to create .clang-format file"
        return 1
    fi
    
    return 0
}

select_suite_version() {
    local package_name="${DAQ_SUITE_NAME}"
    local target_platform="${SPACK_TARGET_PLATFORM}"
    local pkg_version=""
    local pkg_hash=""
    local -a available_versions=()
    local -a available_hashes=()
    
    log_debug "Finding available ${package_name} versions..."
    
    local spack_find_command="spack find -l --no-groups ${package_name} arch=${target_platform}"
    
    local spack_output
    if ! spack_output=$(${spack_find_command} 2>&1); then
        log_warn "Failed to find ${package_name} versions: ${spack_output}"
        echo ""
        return 1
    fi
    
    while IFS= read -r line; do
        local tmp_hash tmp_version
        tmp_hash=$(echo "$line" | cut -d' ' -f1)
        tmp_version=$(echo "$line" | cut -d' ' -f2)
        
        if [[ -n "${tmp_hash}" && -n "${tmp_version}" ]]; then
            if [[ -z "$pkg_version" ]]; then
                pkg_version="$tmp_version"
                pkg_hash="$tmp_hash"
            fi
            available_versions+=("$tmp_version")
            available_hashes+=("$tmp_hash")
        fi
    done < <(echo "${spack_output}" | sed "s/${package_name}@//" | sort -r -k2 | head -6)

    # If no versions found, return empty
    if [[ ${#available_versions[@]} -eq 0 ]]; then
        log_warn "No ${package_name} versions found"
        echo ""
        return 1
    fi

    echo
    log_info "Select ${package_name} version for compile_flags.txt:"
    for i in "${!available_versions[@]}"; do
        echo "$((i + 1)). ${available_versions[$i]} (${available_hashes[$i]})"
    done
    
    local response
    response=$(read_with_timeout "Choose a version (default: $pkg_version): " "$pkg_version")
    echo
    
    if [[ "$response" =~ ^[0-9]+$ ]]; then
        local index=$((response - 1))
        if [[ "$index" -ge 0 && "$index" -lt "${#available_versions[@]}" ]]; then
            pkg_version="${available_versions[$index]}"
            pkg_hash="${available_hashes[$index]}"
        fi
    elif [[ -n "$response" && "$response" != "$pkg_version" ]]; then
        # User entered something else, check if it matches any version
        local found=false
        for i in "${!available_versions[@]}"; do
            if [[ "${available_versions[$i]}" == "$response" ]]; then
                pkg_version="${available_versions[$i]}"
                pkg_hash="${available_hashes[$i]}"
                found=true
                break
            fi
        done
        
        if [[ "$found" != true ]]; then
            log_info "Using default version: $pkg_version ($pkg_hash)"
        fi
    fi

    # Return the selected version and hash as a composite string
    echo "${pkg_version}|${pkg_hash}"
}

create_compile_flags_txt() {
    local dir_name="$1"
    local package_suite_name="${DAQ_SUITE_NAME}"
    local target_platform="${SPACK_TARGET_PLATFORM}"
    local compiler_version="${GCC_VERSION}"
    
    log_debug "Creating compile_flags.txt file..."

    # Select package version
    local version_info
    version_info=$(select_suite_version)
    if [[ -z "${version_info}" ]]; then
        log_warn "Could not determine ${package_suite_name} version, skipping compile_flags.txt creation"
        return 1
    fi

    # Extract version and hash from the composite string
    local pkg_version pkg_hash
    pkg_version=$(echo "${version_info}" | cut -d'|' -f1)
    pkg_hash=$(echo "${version_info}" | cut -d'|' -f2)

    log_info "Loading ${package_suite_name}@${pkg_version} /${pkg_hash} for compile_flags.txt generation"
    
    if ! spack load ${package_suite_name}@${pkg_version} /${pkg_hash} arch=${target_platform}; then
        log_error "Failed to load ${package_suite_name}@${pkg_version}"
        return 1
    fi
    
    if ! spack load gcc@${compiler_version} arch=${target_platform}; then
        log_error "Failed to load gcc@${compiler_version}"
        spack unload ${package_suite_name}
        return 1
    fi

    local flags_file="${dir_name}/srcs/compile_flags.txt"
    log_info "Creating compile_flags.txt file: ${flags_file}"
    
    cat > "${flags_file}" << EOF || {
-Wall
-Wextra 
-Werror
-std=c++17
-pthread
-pedantic
-Wno-unused-parameter
-Wno-unused-variable
-Wno-uninitialized
-Wno-unused-include
-Wno-narrowing
-Wno-conversion
$( for p in $(echo $CMAKE_PREFIX_PATH | sed "s/:/\n/g" |sort -u | \
  grep -E '(/gcc/)'); do echo -I${p}/include; done )
$( for p in $(echo $CMAKE_PREFIX_PATH | sed "s/:/\n/g" |sort -u | \
  grep -E '(/art|/cetlib|/trace|/fhic|/boost|/message|/caen|/json|/windri)'); do echo -I${p}/include; done )
$( for p in $(echo $CMAKE_PREFIX_PATH | sed "s/:/\n/g" |sort -u | \
  grep -E '(/sbndaq|/wibtools)'); do echo -I${p}/include; done )
$( for p in $(echo $CMAKE_PREFIX_PATH | sed "s/:/\n/g" |sort -u | \
  grep -E '(/canvas|/hep-concurrency|/intel-tbb|/clhep|/root)'); do echo -I${p}/include; done )
EOF
        log_error "Failed to create compile_flags.txt file"
        spack unload gcc
        spack unload ${package_suite_name}
        return 1
    }

    spack unload gcc
    spack unload ${package_suite_name}
    
    log_success "Created compile_flags.txt with include paths from ${package_suite_name}@${pkg_version}"
    return 0
}

create_repos_yaml() {
    local dir_name="$1"
    local yaml_file="${dir_name}/spack/repos.yaml"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local dev_envs_root_dir="${SPACK_DAQ_AREAS}"
    
    log_debug "Creating repos.yaml file: ${yaml_file}"

    # Copy existing repository configuration
    if [[ -f "${spack_install_root}/${spack_release_version}/NULL/etc/spack/repos.yaml" ]]; then
        if ! cp "${spack_install_root}/${spack_release_version}/NULL/etc/spack/repos.yaml" "${dir_name}/spack/"; then
            log_error "Failed to copy repos.yaml from ${spack_install_root}/${spack_release_version}/NULL/etc/spack/repos.yaml"
            return 1
        fi
    else
        log_warn "Could not find ${spack_install_root}/${spack_release_version}/NULL/etc/spack/repos.yaml - skipping copy"
    fi

    # remove any existing mpd repo entry
    if ! sed -i '/mpd/d' "${yaml_file}"; then
        log_warn "No mpd entry found in ${yaml_file}"
    fi
    
    # add the mpd repo entry at the top of the "repos:" section
    if ! sed -i "1,/^repos:/!b;/^repos:/{a\\
- $dev_envs_root_dir/$dir_name/spack-repos/mpd
}" "${yaml_file}"; then
        log_error "Failed to add ${dev_envs_root_dir}/${dir_name}/spack-repos/mpd to repos.yaml"
        return 1
    fi
    
    return 0
}

create_packages_yaml() {
    local dir_name="$1"
    local distro_name="${SPACK_DISTRO_NAME}"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local yaml_file="${dir_name}/spack/linux/${distro_name}/packages.yaml"
    
    log_debug "Creating packages.yaml file: ${yaml_file}"

    if ! mkdir -p "${dir_name}/spack/linux/${distro_name}"; then
        log_error "Failed to create ./spack/linux/${distro_name} directory"
        return 1
    fi

    # Copy existing packages configuration
    if [[ -f "${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/packages.yaml" ]]; then
        if ! cp "${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/packages.yaml" "${dir_name}/spack/linux/${distro_name}/"; then
            log_error "Failed to copy packages.yaml from ${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/packages.yaml"
            return 1
        fi
    else
        log_warn "Could not find ${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/packages.yaml - skipping copy"
    fi
    
    return 0
}

create_compilers_yaml() {
    local dir_name="$1"
    local distro_name="${SPACK_DISTRO_NAME}"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local yaml_file="${dir_name}/spack/linux/${distro_name}/None/compilers.yaml"
    
    log_debug "Creating compilers.yaml file: ${yaml_file}"

    if ! mkdir -p "${dir_name}/spack/linux/${distro_name}/None"; then
        log_error "Failed to create ./spack/linux/${distro_name}/None directory"
        return 1
    fi

    # Copy existing packages configuration
    if [[ -f "${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/None/compilers.yaml" ]]; then
        if ! cp "${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/None/compilers.yaml" "${dir_name}/spack/linux/${distro_name}/None/"; then
            log_error "Failed to copy compilers.yaml from ${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/None/compilers.yaml"
            return 1
        fi
    else
        log_warn "Could not find ${spack_install_root}/${spack_release_version}/NULL/etc/spack/linux/${distro_name}/None/compilers.yaml - skipping copy"
    fi
    
    return 0
}

setup_development_packages() {
    local package_suite_name="$1"
    local version="$2"
    local s_qualifier="$3" 
    local compiler_version="$4"
    local cpp_standard="${5:-}"
    local dev_packages_list="${6:-${DAQ_SUITE_CHECKOUT_PACKAGES}}"
    local target_platform="${7:-${SPACK_TARGET_PLATFORM}}"
    
    # Fall back to environment variables if parameters are not provided
    package_suite_name="${package_suite_name:-${DAQ_SUITE_NAME}}"
    version="${version:-}"
    s_qualifier="${s_qualifier:-}"
    compiler_version="${compiler_version:-}"
    
    # Clean up qualifier
    s_qualifier=$(echo "${s_qualifier}" | sed 's/^s=\|^s//')
    
    local spec_output_path=${package_suite_name}-${version}-s${s_qualifier//=/}-gcc${compiler_version%%.*}-${cpp_standard}-${SPACK_OS}.env.txt
    local cpp_standard_param=""
    
    if [[ -n "${cpp_standard}" ]]; then
        cpp_standard_param="cxxstd=${cpp_standard#c++}"
    fi
    log_debug "Downloading package source for ${package_suite_name}@${version} s=${s_qualifier} ${cpp_standard_param} arch=${target_platform} %gcc@${compiler_version}"
    log_command "spack spec ${package_suite_name}@${version} s=${s_qualifier} ${cpp_standard_param} arch=${target_platform} %gcc@${compiler_version} > ${spec_output_path}"
    if ! spack spec "${package_suite_name}@${version}" "s=${s_qualifier}" "${cpp_standard_param}" "arch=${target_platform}" "%gcc@${compiler_version}" > "${spec_output_path}"; then
        log_error "Failed to run spack spec"
        return 1
    fi

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
        log_command "spack develop --clone --force FORCE --path srcs/${pkg_name} ${pkg_name}@develop ${cpp_standard_param} %gcc@${compiler_version}"
        if ! spack develop --clone --force FORCE --path "srcs/${pkg_name}" "${pkg_name}@develop" "${cpp_standard_param}" "%gcc@${compiler_version}"; then
            log_error "Cannot set up development environment for: ${pkg_name}"
            exit 1
        fi
        
        if ! checkout_package "${pkg_name}" "${pkg_version}"; then
            exit 1
        fi
        
        log_command "spack develop --no-clone --path srcs/${pkg_name} ${pkg_name}@${pkg_version_from_spec} ${cpp_standard_param} %gcc@${compiler_version}"
        if ! spack develop --no-clone --path "srcs/${pkg_name}" "${pkg_name}@${pkg_version_from_spec}" "${cpp_standard_param}" "%gcc@${compiler_version}"; then
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

create_mpd_repo() {
    local dir_name="$1"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    
    log_debug "Creating mpd repo: ${dir_name}/spack-repos/mpd"

    if ! mkdir -p "${dir_name}/spack-repos/mpd"; then
        log_error "Failed to create ./spack-repos/mpd directory"
        return 1
    fi

    # Copy existing mpd repo configuration
    if [[ -d "${spack_install_root}/${spack_release_version}/spack-repos/mpd" ]]; then
        if ! cp -r "${spack_install_root}/${spack_release_version}/spack-repos/mpd" "${dir_name}/spack-repos/"; then
            log_error "Failed to copy mpd repo from ${spack_install_root}/${spack_release_version}/spack-repos/mpd"
            return 1
        fi
    else
        log_warn "Could not find ${spack_install_root}/${spack_release_version}/spack-repos/mpd - skipping copy"
    fi
    
    return 0
}

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

initialize_spack_environment() {
    local spack_install_root="$1"
    local spack_release_version="$2"
    local compiler_version="$3"
    local cpp_standard="${4:-}"
    local target_microarch="${5:-${SPACK_MICRO_ARCH:-'v2'}}"
    local build_threads="${6:-${BUILD_THREADS:-}}"
    local debug_build="${7:-${DEBUG_BUILD:-false}}"
    
    # Validate required parameters
    if [[ -z "$spack_install_root" || -z "$spack_release_version" || -z "$compiler_version" ]]; then
        log_error "Missing required parameters for initialize_spack_environment"
        log_error "Usage: initialize_spack_environment spack_install_root spack_release_version compiler_version [cpp_standard] [target_microarch] [build_threads] [debug_build]"
        return 1
    fi
    
    log_info "Setting up Spack environment with GCC ${compiler_version}"
    
    # Set up core environment variables
    export SPACK_COMPILER_VERSION="${compiler_version}"
    export SPACK_MICRO_ARCH=${target_microarch}
    
    # Store C++ standard if provided
    if [[ -n "${cpp_standard}" ]]; then
        export SPACK_CPP_STANDARD="${cpp_standard}"
    fi

    # Determine number of build threads to use
    local cpu_count
    cpu_count=$(get_cpu_count)
    export SPACK_BUILD_THREADS=${build_threads:-$((cpu_count / 2))}
    
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
    
    # Set up architecture-specific variables
    local distro_name
    if ! distro_name=$(spack arch -o 2>/dev/null); then
        log_error "Failed to determine Spack architecture"
        return 1
    fi
    export SPACK_DISTRO_NAME="${distro_name}"
    
    # Set up complete architecture specification
    export SPACK_TARGET_PLATFORM="linux-${SPACK_DISTRO_NAME}-x86_64_${target_microarch}"
    
    # Set up build options
    local install_options="-y -j${SPACK_BUILD_THREADS} --deprecated --fresh --no-cache --source"
    
    # Add debug flag if requested
    if [[ "${debug_build}" == true ]]; then
        install_options+=" --debug"
    fi
    
    export SPACK_INSTALL_OPTIONS="${install_options}"
    
    log_debug "Spack environment configured:"
    log_debug "  SPACK_TARGET_PLATFORM: ${SPACK_TARGET_PLATFORM}"
    log_debug "  SPACK_DISTRO_NAME: ${SPACK_DISTRO_NAME}"
    log_debug "  SPACK_BUILD_THREADS: ${SPACK_BUILD_THREADS}"
    log_debug "  SPACK_COMPILER_VERSION: ${SPACK_COMPILER_VERSION}"
    log_debug "  SPACK_MICRO_ARCH: ${SPACK_MICRO_ARCH}"
    if [[ -n "${SPACK_CPP_STANDARD:-}" ]]; then
        log_debug "  SPACK_CPP_STANDARD: ${SPACK_CPP_STANDARD}"
    fi
    log_debug "  SPACK_INSTALL_OPTIONS: ${SPACK_INSTALL_OPTIONS}"
    
    return 0
}

generate_package_buildcache() {
    local dev_env_dir="$1"
    local package_suite_name="$2"
    local version="$3"
    local s_qualifier="$4"
    local compiler_version="$5"
    local cpp_standard="${6:-}"
    local buildcache_mirror_root="${7:-${SPACK_MIRROR_BASE}}"
    local dev_envs_root_dir="${8:-${SPACK_DAQ_AREAS}}"
    
    # Fall back to environment variables for missing parameters
    package_suite_name="${package_suite_name:-${DAQ_SUITE_NAME}}"
    version="${version:-}"
    s_qualifier="${s_qualifier:-}"
    compiler_version="${compiler_version:-${GCC_VERSION}}"
    local target_platform="${SPACK_TARGET_PLATFORM}"

    # Validate required parameters
    if [[ -z "$dev_env_dir" || -z "$package_suite_name" || -z "$version" || -z "$compiler_version" ]]; then
        log_error "Missing required parameters for generate_package_buildcache"
        log_error "Usage: generate_package_buildcache dev_env_dir package_suite_name version s_qualifier compiler_version [cpp_standard] [buildcache_mirror_root] [dev_envs_root_dir]"
        return 1
    fi
    
    local buildcache_output_path="${dev_envs_root_dir}/${dev_env_dir}/spack_mirrors/${package_suite_name}/${version}"
    local cpp_standard_param=""
    
    if [[ -n "${cpp_standard}" ]]; then
        cpp_standard_param="cxxstd=${cpp_standard#c++}"
    fi
    
    log_info "Creating buildcache at: ${buildcache_output_path}"
    mkdir -p "${buildcache_output_path}"
    
    local spack_find_command="spack find -lpd ${package_suite_name}@${version}"
    if [[ -n "${s_qualifier}" ]]; then
        spack_find_command+=" s=${s_qualifier#s}"
    fi
    if [[ -n "${cpp_standard_param}" ]]; then
        spack_find_command+=" ${cpp_standard_param}"
    fi
    spack_find_command+=" %gcc@${compiler_version}"
    
    log_command "${spack_find_command}"
    while IFS= read -r line; do
        local pkg_hash pkg_spec
        pkg_hash=$(echo "$line" | awk '{print $1}')
        pkg_spec=$(echo "$line" | awk '{print $2}')
        
        if [[ -n "${pkg_hash}" && -n "${pkg_spec}" ]]; then
            log_command "spack buildcache push --unsigned --only package file://${buildcache_output_path} ${pkg_spec} ${pkg_hash}"
            spack buildcache push --unsigned --only package "file://${buildcache_output_path}" "${pkg_spec}" "${pkg_hash}" || \
                log_warn "Failed to push to buildcache: ${pkg_spec}"
        fi
    done < <(eval "${spack_find_command}" | grep "/${dev_env_dir}/" | awk '{printf("/%s %s\n", $1, $2)}')
    
    update_buildcache "${dev_env_dir}" "${buildcache_output_path}" "${version}" "${package_suite_name}" "${dev_envs_root_dir}"
}

update_buildcache() {
    local dev_env_dir="$1"
    local buildcache_output_path="$2"
    local version="$3"
    local package_suite_name="${4:-${DAQ_SUITE_NAME}}"
    local dev_envs_root_dir="${5:-${SPACK_DAQ_AREAS}}"

    # Validate required parameters
    if [[ -z "$dev_env_dir" || -z "$buildcache_output_path" || -z "$version" || -z "$package_suite_name" || -z "$dev_envs_root_dir" ]]; then
        log_error "Missing required parameters for update_buildcache"
        log_error "Usage: update_buildcache dev_env_dir buildcache_output_path version [package_suite_name] [dev_envs_root_dir]"
        return 1
    fi

    cat > "${dev_envs_root_dir}/${dev_env_dir}/spack/linux/mirrors.yaml" << EOF
mirrors:
  local_mirror:
    url: file://${buildcache_output_path}
EOF

    log_info "Updating buildcache index..."
    log_command "spack buildcache update-index file://${buildcache_output_path}"
    spack buildcache update-index "file://${buildcache_output_path}" || log_warn "Cannot update buildcache index"
    
    log_info "Listing packages in buildcache..."
    log_command "spack buildcache list -lva ${package_suite_name}@${version}"
    spack buildcache list -lva "${package_suite_name}@${version}" || log_warn "Cannot list buildcache contents"
}

select_package_version() {
    local package_suite_name="$1"
    local s_qualifier="$2"
    local compiler_version="$3"
    local preferred_version="${4:-}"
    local cpp_standard="${5:-}"
    local target_platform="${6:-${SPACK_TARGET_PLATFORM}}"
    
    # Fall back to environment variables for missing parameters
    package_suite_name="${package_suite_name:-${DAQ_SUITE_NAME}}"
    s_qualifier="${s_qualifier:-}"
    compiler_version="${compiler_version:-${GCC_VERSION}}"
    preferred_version="${preferred_version:-${DEFAULT_VERSION}}"
    
    # Format qualifier and cxxstd parameter
    local formatted_s_qualifier=""
    if [[ -n "${s_qualifier}" ]]; then
        formatted_s_qualifier="s=${s_qualifier#s}"
    fi
    
    local cpp_standard_param=""
    if [[ -n "${cpp_standard}" ]]; then
        cpp_standard_param="cxxstd=${cpp_standard#c++}"
    fi
    
    # Validate required parameters
    if [[ -z "$package_suite_name" || -z "$compiler_version" ]]; then
        log_error "Missing required parameters for select_package_version"
        log_error "Usage: select_package_version package_suite_name s_qualifier compiler_version [preferred_version] [cpp_standard] [target_platform]"
        return 1
    fi
    
    if [[ -z "${preferred_version}" ]]; then
        # First check if version is already in DAQ_SUITE_VERSIONS
        if [[ -n "${DAQ_SUITE_VERSIONS}" ]]; then
            local first_version
            first_version=$(echo "${DAQ_SUITE_VERSIONS%%,*}" | cut -d':' -f1)
            if [[ -n "${first_version}" ]]; then
                preferred_version="${first_version}"
                log_debug "Using version from DAQ_SUITE_VERSIONS: ${preferred_version}"
                echo "${preferred_version}"
                return 0
            fi
        fi
        
        # Fall back to querying Spack
        local spack_find_command="spack find --no-groups ${package_suite_name}"
        if [[ -n "${formatted_s_qualifier}" ]]; then
            spack_find_command+=" ${formatted_s_qualifier}"
        fi
        if [[ -n "${cpp_standard_param}" ]]; then
            spack_find_command+=" ${cpp_standard_param}"
        fi
        spack_find_command+=" %gcc@${compiler_version} arch=${target_platform}"
        
        log_command "${spack_find_command}"
        
        local find_output
        if ! find_output=$(eval "${spack_find_command}" 2>&1); then
            log_error "Failed to find ${package_suite_name} versions: ${find_output}"
            return 1
        fi
        
        preferred_version=$(echo "${find_output}" | grep -o '@[0-9a-zA-Z._-]*' | 
                         cut -d'@' -f2 | sort -ru | head -1)
        
        if [[ -z "${preferred_version}" ]]; then
            log_error "No ${package_suite_name} versions found"
            return 1
        fi
    fi
    
    read_with_timeout "Enter version (default: ${preferred_version}): " "${preferred_version}"
}


# Export for use in other scripts
# All functions now use explicit parameters instead of relying on environment variables
# Standard parameter order: package_suite_name, version, s_qualifier, compiler_version, cpp_standard, ...

# create_config_files(dir_name)
export -f create_config_files

# create_compile_flags_txt(dir_name)
export -f create_compile_flags_txt

# initialize_spack_environment(spack_install_root, spack_release_version, compiler_version, [cpp_standard], [target_microarch], [build_threads], [debug_build])
export -f initialize_spack_environment

# generate_package_buildcache(dev_env_dir, package_suite_name, version, s_qualifier, compiler_version, [cpp_standard], [buildcache_mirror_root], [dev_envs_root_dir])
export -f generate_package_buildcache

# update_buildcache(dev_env_dir, buildcache_output_path, version, [package_suite_name], [dev_envs_root_dir])
export -f update_buildcache

# checkout_package(pkg_name, pkg_version)
export -f checkout_package

# create_mpd_repo(dir_name)
export -f create_mpd_repo

# create_compilers_yaml(dir_name)
export -f create_compilers_yaml

# setup_development_packages(package_suite_name, version, s_qualifier, compiler_version, [cpp_standard], [dev_packages_list], [target_platform])
export -f setup_development_packages

# select_package_version(package_suite_name, s_qualifier, compiler_version, [preferred_version], [cpp_standard], [target_platform])
export -f select_package_version

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides environment setup functions for Spack development."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Init when sourced
log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
