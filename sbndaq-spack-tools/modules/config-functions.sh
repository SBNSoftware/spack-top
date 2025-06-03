#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_CONFIG_FUNCTIONS_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _CONFIG_FUNCTIONS_SH_=1

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/common-functions.sh"

# Creates all configuration files for a development environment
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
    create_repos_yaml "${dir_name}" || return 1
    create_packages_yaml "${dir_name}" || return 1
    create_compilers_yaml "${dir_name}" || return 1
    create_mpd_repo "${dir_name}" || return 1
    return 0
}

# Creates upstreams.yaml configuration file
create_upstreams_yaml() {
    local dir_name="$1"
    local spack_packages_top="${SPACK_PACKAGES_TOP}"
    local yaml_file="${dir_name}/spack/linux/upstreams.yaml"
    
    #don't create the file if it already exists
    if [[ -f "${yaml_file}" ]]; then
        log_debug "Upstreams.yaml file already exists: ${yaml_file}"
        return 0
    fi
    
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

# Creates config.yaml configuration file
create_config_yaml() {
    local dir_name="$1"
    local dev_envs_root_dir="${SPACK_DAQ_AREAS}"
    local yaml_file="${dir_name}/spack/config.yaml"

    #don't create the file if it already exists
    if [[ -f "${yaml_file}" ]]; then
        log_debug "Config.yaml file already exists: ${yaml_file}"
        return 0
    fi
    
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

# Creates .clang-format file
create_clang_format() {
    local dir_name="$1"
    local format_file="${dir_name}/srcs/.clang-format"

    #don't create the file if it already exists
    if [[ -f "${format_file}" ]]; then
        log_debug ".clang-format file already exists: ${format_file}"
        return 0
    fi
    
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

# Creates repos.yaml configuration file
create_repos_yaml() {
    local dir_name="$1"
    local yaml_file="${dir_name}/spack/repos.yaml"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local dev_envs_root_dir="${SPACK_DAQ_AREAS}"
    
    #don't create the file if it already exists
    if [[ -f "${yaml_file}" ]]; then
        log_debug "Repos.yaml file already exists: ${yaml_file}"
        return 0
    fi
    
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

# Creates packages.yaml configuration file
create_packages_yaml() {
    local dir_name="$1"
    local distro_name="${SPACK_DISTRO_NAME}"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local yaml_file="${dir_name}/spack/linux/${distro_name}/packages.yaml"

    #don't create the file if it already exists
    if [[ -f "${yaml_file}" ]]; then
        log_debug "Packages.yaml file already exists: ${yaml_file}"
        return 0
    fi
    
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

# Creates compilers.yaml configuration file
create_compilers_yaml() {
    local dir_name="$1"
    local distro_name="${SPACK_DISTRO_NAME}"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local yaml_file="${dir_name}/spack/linux/${distro_name}/None/compilers.yaml"

    #don't create the file if it already exists
    if [[ -f "${yaml_file}" ]]; then
        log_debug "Compilers.yaml file already exists: ${yaml_file}"
        return 0
    fi
    
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

# Creates MPD repository
create_mpd_repo() {
    local dir_name="$1"
    local spack_install_root="${SPACK_DIR}"
    local spack_release_version="${SPACK_VERSION}"
    local mpd_repo_dir="${dir_name}/spack-repos/mpd"

    #don't create the file if it already exists
    if [[ -d "${mpd_repo_dir}" ]]; then
        log_debug "MPD repository already exists: ${mpd_repo_dir}"
        return 0
    fi

    log_debug "Creating mpd repo: ${mpd_repo_dir}"

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

# Creates default configuration file
create_default_config() {
    local config_file="$1"
    local pkg_type="${2:-suite}"  # 'suite' or 'proj'
    
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
    
    # Create different default configs based on package type
    if [[ "${pkg_type}" == "suite" ]]; then
        # Suite config
        cat > "${config_file}" << EOF || {
# Default configuration generated on $(date)

DEVNAME=EFG
# DAQ suite configuration
DAQ_PKG_NAME=sbndaq-suite

# Format: version:qualifier:compiler:standard,\\
#         version:qualifier:compiler:standard
DAQ_PKG_VERSIONS=migration_artdaqv3_13_02:s131:gcc13.1.0:c++20,\\
migration_artdaqv3_13_02:s132:gcc13.1.0:c++20
DAQ_PKG_SBNENV=sbn-fd
DAQ_PKG_CHECKOUT_PACKAGES=sbndaq@upgrade_gcc13.1.0,sbndaq-artdaq@upgrade_gcc13.1.0,\\
sbndaq-artdaq-core@upgrade_gcc13.1.0,wibtools@upgrade_gcc13.1.0


# Spack configuration
SPACK_SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SPACK_SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SPACK_SOFTWARE_BASE}/spack_mirrors/\${DAQ_PKG_NAME}
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
    else
        # Project config
        cat > "${config_file}" << EOF || {
# Default configuration generated on $(date)

DEVNAME=ABC
# DAQ project configuration
DAQ_PKG_NAME=artdaq-database

# Format: version:qualifier:compiler:standard,\
#         version:qualifier:compiler:standard
DAQ_PKG_VERSIONS=v1_10_00::gcc13.1.0:c++20,\
v1_10_00::gcc13.1.0:c++17
DAQ_PKG_CHECKOUT_PACKAGES=artdaq-database@v1_10_00


# Spack configuration
SPACK_SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SPACK_SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SPACK_SOFTWARE_BASE}/spack_mirrors/\${DAQ_PKG_NAME}
SPACK_DAQ_AREAS=\${HOME}/DAQ_SPACK_ProjAreas
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
    fi
    
    if [[ ! -f "${config_file}" ]]; then
        log_error "Failed to create configuration file: ${config_file}"
        return 1
    fi
    
    log_success "Default configuration file created at: ${config_file}"
    log_info "Please review the configuration file before continuing"
    return 0
}

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides configuration file creation functions for Spack development."
    log_info "It should be sourced by other scripts, not executed directly."
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 