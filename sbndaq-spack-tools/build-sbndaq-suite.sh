#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

[[ "${_COMMON_SH_:-0}" -eq 1 ]] && return 0
declare -r _COMMON_SH_=1

export NON_INTERACTIVE=${NON_INTERACTIVE:-false}
export VERBOSE=${VERBOSE:-true}
export WITH_CLEANUP=${WITH_CLEANUP:-true}
export LOGS_DIR=${LOGS_DIR:-"$(dirname "${BASH_SOURCE[0]}")/logs"}
export CMDS_FILE=${CMDS_FILE:-"${LOGS_DIR}/commands.log"}
export MAX_LOGS=${MAX_LOGS:-10}

readonly COMMON_ENVFILE=${COMMON_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}
readonly COMMON_CONFFILE=${COMMON_CONFFILE:-"$(dirname "${BASH_SOURCE[0]}")/${COMMON_ENVFILE}"}

declare -a remaining_args=()
declare -a ___cleanup_functions=(
    remove_temp_files
    close_open_handles
    reset_signal_handlers
    cleanup_logs
    rotate_logs
)

declare -r RED='\033[38;2;243;139;168m'
declare -r YELLOW='\033[38;2;249;226;175m'
declare -r BLUE='\033[38;2;137;180;250m'
declare -r GREEN='\033[38;2;166;227;161m'
declare -r RESET='\033[0m'
declare -r GREY='\033[38;2;186;194;222m'

log_info() { printf "${BLUE}[INFO]${RESET} %s\n" "$*" >&2; }
log_error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; }
log_warn() { printf "${YELLOW}[WARN]${RESET} %s\n" "$*" >&2; }
log_debug() { [[ "${VERBOSE}" == true ]] && printf "${GREY}[DEBUG]${RESET} %s\n" "$*" >&2; }
log_command() {
    printf "${GREEN}[CMD]${RESET} %s\n" "$*" >&2
    mkdir -p "$(dirname "${CMDS_FILE}")" || {
        log_warn "Failed to create directory for commands file"
        return 0
    }
    printf '%s\n' "$*" >> "${CMDS_FILE}" || log_warn "Failed to write to commands file"
}

print_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS] [GCC_VERSION] [VERSIONS...]

Build and publish sbndaq-suite packages to buildcache.

Options:
    -h, --help          Show this help message
    --non-interactive   Run in non-interactive mode
    --verbose           Enable verbose output
    --with-cleanup      Enable cleanup on exit

Arguments:
    GCC_VERSION         GCC version to use (12.1.0 or 13.1.0, default: 13.1.0)
    VERSIONS            Optional list of versions to process (default: predefined list)

Environment Variables:
    SOFTWARE_BASE       Base directory for software (default: /daq/software)
    SPACK_DIR           Spack directory (default: SOFTWARE_BASE/spack_packages/spack)
    SPACK_VERSION       Spack version (default: v1.0.1.sbnd)
    MIRROR_BASE         Mirror base directory (default: SOFTWARE_BASE/spack_mirrors/sbndaq-suite)
EOF
}

[[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -n "${1:-}" ]] && [[ "$1" =~ ^(-h|--help)$ ]] && { print_usage; exit 0; }
[[ "${BASH_SOURCE[0]}" != "${0}" ]] && log_info "$(basename "${BASH_SOURCE[0]}") is being sourced..."

load_build_config() {
    if [[ ! -f "${COMMON_CONFFILE}" ]]; then
        log_error "Configuration file not found: ${COMMON_CONFFILE}"
        return 1
    fi

    local required_vars=(
        "SOFTWARE_BASE"
        "SPACK_DIR"
        "SPACK_VERSION"
        "SPACK_MIRROR_BASE"
        "GCC_VERSION"
        "DAQ_SUITE_NAME"
        "DAQ_SUITE_VERSIONS"
        "DAQ_SUITE_QUALIFIERS"
    )

    for var in "${required_vars[@]}"; do
        if ! declare -p "$var" &>/dev/null; then
            #log_warn "Required configuration variable not declared: ${var}"
            continue
        fi
        if [[ -z "${!var}" ]]; then
            log_warn "Required configuration variable not set: ${var}"
        fi
    done

    log_info "Loading configuration from ${COMMON_CONFFILE}"
    source "${COMMON_CONFFILE}"

    for var in "${required_vars[@]}"; do
        if ! declare -p "$var" &>/dev/null; then
            log_error "Required configuration variable not declared: ${var}"
            continue
        fi
        if [[ -z "${!var}" ]]; then
            log_error "Required configuration variable not set: ${var}"
            return 1
        fi
    done

    for var in "${required_vars[@]}"; do
        export "${var}"
        readonly "${var}"
    done
}


handle_error() {
    local exit_code="$1" line_no="$2" command="$3"
    log_error "Error occurred:"
    log_error "Command: ${command}"
    log_error "Line number: ${line_no}"
    log_error "Exit code: ${exit_code}"
    cleanup_on_exit
    exit "${exit_code}"
}

setup_signal_handlers() {
    log_debug "Setting up signal handlers..."
    trap 'handle_sigint' SIGINT
    trap 'handle_sigterm' SIGTERM
    trap 'handle_sigquit' SIGQUIT
    trap 'cleanup_on_exit' EXIT
    trap 'handle_error $? $LINENO "$BASH_COMMAND"' ERR
}

handle_sigint() {
    log_warn "Caught SIGINT (Ctrl+C)"
    cleanup_on_exit
    exit 130
}

handle_sigterm() {
    log_warn "Caught SIGTERM"
    cleanup_on_exit
    exit 143
}

handle_sigquit() {
    log_warn "Caught SIGQUIT"
    cleanup_on_exit
    exit 131
}

cleanup_on_exit() {
    [[ "${WITH_CLEANUP}" == true ]] || return 0
    log_debug "Performing cleanup..."
    for func in "${___cleanup_functions[@]}"; do
        if ! "$func"; then
            log_warn "Cleanup function $func failed"
        fi
    done
}

remove_temp_files() {
    log_debug "Removing temporary files..."
    [[ -f "${CMDS_FILE}" ]] && rm -f "${CMDS_FILE}" || log_warn "Failed to remove commands file"
    return 0
}

close_open_handles() {
    log_debug "Closing open file handles..."
    exec 3>&- 2>/dev/null || true
    exec 4>&- 2>/dev/null || true
    return 0
}

reset_signal_handlers() {
    log_debug "Resetting signal handlers..."
    trap - SIGINT SIGTERM SIGQUIT EXIT ERR
    return 0
}

cleanup_logs() {
    log_debug "Cleaning up logs..."
    if [[ -f "${CMDS_FILE}" ]] && [[ -s "${CMDS_FILE}" ]]; then
        mkdir -p "${LOGS_DIR}" || {
            log_warn "Failed to create logs directory: ${LOGS_DIR}"
            return 0
        }
        mv "${CMDS_FILE}" "${LOGS_DIR}/commands.$(date +%Y%m%d_%H%M%S).log" || {
            log_warn "Failed to move commands file to logs directory"
            return 0
        }
    fi
    return 0
}

rotate_logs() {
    log_debug "Rotating logs to keep only ${MAX_LOGS} recent logs..."
    [[ -d "${LOGS_DIR}" ]] || return 0

    local pattern file_count
    for pattern in "*-install.log" "*-process.log" "commands.*.log"; do
        file_count=$(find "${LOGS_DIR}" -name "${pattern}" 2>/dev/null | wc -l) || continue
        if [[ ${file_count} -gt ${MAX_LOGS} ]]; then
            log_debug "Removing old ${pattern} logs (keeping ${MAX_LOGS} of ${file_count})"
            find "${LOGS_DIR}" -name "${pattern}" -printf "%T@ %p\n" 2>/dev/null |
                sort -n |
                head -n "$(( file_count - MAX_LOGS ))" |
                cut -d' ' -f2- |
                xargs -r rm -f
        fi
    done
    return 0
}

ensure_log_directory() {
    if [[ ! -d "${LOGS_DIR}" ]]; then
        mkdir -p "${LOGS_DIR}" || {
            log_warn "Failed to create logs directory: ${LOGS_DIR}"
            return 1
        }
    fi
    return 0
}

ask_for_continue() {
    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode, continuing automatically"
        return 1
    fi

    local response
    while true; do
        read -rp "Do you want to continue? [y/N] " response
        case $response in
            [Yy]* ) return 0;;
            [Nn]* | "" ) return 1;;
            * ) log_error "Please answer y or n.";;
        esac
    done
}

read_with_timeout() {
    local prompt="$1" default="$2" response

    if [[ "${NON_INTERACTIVE}" == true ]]; then
        log_debug "Non-interactive mode, using default: ${default}"
        echo "${default}"
        return 0
    fi

    if read -rt 10 -p "${prompt}" response; then
        echo "${response:-$default}"
    else
        log_warn "Timeout occurred, using default: ${default}"
        echo "${default}"
    fi
}

parse_arguments() {
    remaining_args=()
    while [[ $# -gt 0 ]]; do
        case $1 in
            --non-interactive) NON_INTERACTIVE=true; shift ;;
            --verbose) VERBOSE=true; shift ;;
            --with-cleanup) WITH_CLEANUP=true; shift ;;
            -h|--help) print_usage; exit 0 ;;
            *) log_error "Unknown option: $1"; return 1 ;;
        esac
    done
}

get_distro_type() {
    local distro_type="unknown"

    if [[ -f /etc/os-release ]]; then
        distro_type=$(grep "^ID=" /etc/os-release | cut -d'=' -f2 | tr -d '"')
    elif [[ -f /etc/redhat-release ]]; then
        distro_type="redhat"
    elif [[ -f /etc/debian_version ]]; then
        distro_type="debian"
    elif [[ -f /etc/arch-release ]]; then
        distro_type="arch"
    elif [[ -f /etc/alpine-release ]]; then
        distro_type="alpine"
    fi

    echo "${distro_type}"
}

get_os_name() {
    uname -s | tr '[:upper:]' '[:lower:]'
}

call_with_sudo() {
    if [[ "$(get_os_name)" == "linux" ]]; then
        command sudo "$@"
    else
        command "$@"
    fi
}

setup_environment() {
    local spack_dir="$1"
    local spack_version="$2"
    local gcc_version="$3"

    log_info "Setting up environment with GCC ${gcc_version}"

    local spack_path="${spack_dir}/${spack_version}"
    if [[ ! -d "${spack_path}" ]]; then
        log_error "Spack directory not found: ${spack_path}"
        return 1
    fi

    if ! cd "${spack_path}"; then
        log_error "Failed to change directory to ${spack_path}"
        return 1
    fi

    export SPACK_DISABLE_LOCAL_CONFIG=true

    if ! source "${spack_path}/setup-env.sh"; then
        log_error "Failed to source setup-env.sh"
        return 1
    fi

    export SPACK_DISABLE_LOCAL_CONFIG=true
    export SPACK_GCC_VERSION="${gcc_version}"
    export SPACK_MICRO_ARCH='v2'

    local spack_arch_output
    if ! spack_arch_output=$(spack arch -o); then
        log_error "Failed to determine spack architecture"
        return 1
    fi
    export SPACK_OS="${spack_arch_output}"

    local nproc_count
    nproc_count=$(nproc 2>/dev/null || echo "4")
    export SPACK_J="${nproc_count}"
    export SPACK_ARCH="linux-${SPACK_OS}-x86_64_${SPACK_MICRO_ARCH}"
    export SPACK_INSTALL_OPTS=" -y -j${SPACK_J} --deprecated --fresh --no-cache --source"
    log_debug "SPACK_ARCH: ${SPACK_ARCH}"

    local hash_dir="${spack_path}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Failed to create hash directory: ${hash_dir}"
            return 1
        }
    fi

    return 0
}

install_package() {
    local version="$1"
    local qualifier="$2"
    local package="$3"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" ]]; then
        log_error "Version, qualifier, and package name are required"
        return 1
    fi

    if ! ensure_log_directory; then
        log_warn "Failed to create log directory, continuing anyway"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local log_file="${LOGS_DIR}/${package}-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-${SPACK_OS}.${timestamp}-install.log"

    log_info "Installing ${package}@${version} s=${qualifier} with GCC ${SPACK_GCC_VERSION}"
    log_info "Installation log: ${log_file}"
    log_command "spack install ${SPACK_INSTALL_OPTS} ${package}@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${SPACK_GCC_VERSION}"

    if ! spack install ${SPACK_INSTALL_OPTS} "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" > "${log_file}" 2>&1; then
        log_error "Failed to install ${package}@${version} s=${qualifier}"
        log_error "See log for details: ${log_file}"
        return 1
    fi

    log_info "Successfully installed ${package}@${version} s=${qualifier}"
    return 0
}

generate_spec() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    local package="$5"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" ]]; then
        log_error "Version, qualifier, and package name are required"
        return 1
    fi

    local hash_dir="${spack_dir}/${spack_version}/hashes/"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Failed to create hash directory: ${hash_dir}"
            return 1
        }
    fi

    local spec_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-${SPACK_OS}.txt"

    log_info "Generating spec for ${package}@${version} s=${qualifier}"

    if ! cd "${hash_dir}"; then
        log_error "Failed to change directory to ${hash_dir}"
        return 1
    fi

    log_command "spack spec ${package}@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${SPACK_GCC_VERSION} > ${spec_file}"

    if ! spack spec "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" > "${spec_file}"; then
        log_error "Failed to generate spec for ${package}@${version} s=${qualifier}"
        return 1
    fi

    log_info "Spec generated and saved to ${spec_file}"
    return 0
}

generate_hashes() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    local package="$5"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" ]]; then
        log_error "Version, qualifier, and package name are required"
        return 1
    fi

    local hash_dir="${spack_dir}/${spack_version}/hashes"
    if [[ ! -d "${hash_dir}" ]]; then
        log_info "Creating hash directory: ${hash_dir}"
        mkdir -p "${hash_dir}" || {
            log_error "Failed to create hash directory: ${hash_dir}"
            return 1
        }
    fi

    local hash_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-${SPACK_OS}-hashes.txt"

    log_info "Generating hashes for ${package}@${version} s=${qualifier}"

    if ! cd "${hash_dir}"; then
        log_error "Failed to change directory to ${hash_dir}"
        return 1
    fi

    log_command "spack unload --all"
    spack unload --all || {
        log_warn "Failed to unload all packages, continuing anyway"
    }

    local package_count
    if ! package_count=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" | grep -Eo '/daq/software/.*$' | wc -l); then
        log_error "Failed to count package instances"
        return 1
    fi

    if [[ $package_count -gt 1 ]]; then
        log_debug "Multiple package instances found, selecting the latest one"

        local package_paths
        if ! package_paths=$(spack find -lpfv "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" | grep -Eo '/daq/software/.*$'); then
            log_error "Failed to list package paths"
            return 1
        fi

        local latest_package
        if ! latest_package=$(/bin/ls -ldtr $package_paths 2>/dev/null | tail -1 | awk '{print $NF}'); then
            log_error "Failed to determine latest package"
            return 1
        fi

        local hash
        if ! hash=$(basename "$latest_package" | grep -Eo '[^-]+$'); then
            log_error "Failed to extract hash from latest package path"
            return 1
        fi

        log_command "spack load \"${package}@${version}\" \"/${hash}\""
        if ! spack load "${package}@${version}" "/${hash}"; then
            log_error "Failed to load ${package}@${version}/${hash}"
            return 1
        fi
    else
        log_command "spack load \"${package}@${version}\" \"s=${qualifier}\" \"arch=${SPACK_ARCH}\" \"%gcc@${SPACK_GCC_VERSION}\""
        if ! spack load "${package}@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}"; then
            log_error "Failed to load ${package}@${version} s=${qualifier}"
            return 1
        fi
    fi

    log_command "spack find -ldfv --loaded > ${hash_file}"
    if ! spack find -ldfv --loaded > "${hash_file}"; then
        log_error "Failed to save loaded package info to ${hash_file}"
        return 1
    fi

    if [[ ! -s "${hash_file}" ]]; then
        log_error "Generated hash file is empty: ${hash_file}"
        return 1
    fi

    log_info "Hashes generated and saved to ${hash_file}"
    return 0
}

get_qualifier_e_version() {
    local gcc_version="$1"

    case "$gcc_version" in
        13.1.0) echo "e28" ;;
        12.1.0) echo "e26" ;;
        *)
            log_warn "Unrecognized GCC version: ${gcc_version}, defaulting to e28"
            echo "e28" ;;
    esac
}

push_to_buildcache() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    local package="$6"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" ]]; then
        log_error "Version, qualifier, and package name are required"
        return 1
    fi

    local e_version
    e_version=$(get_qualifier_e_version "$SPACK_GCC_VERSION")

    local hash_dir="${spack_dir}/${spack_version}/hashes"
    local hash_file="${hash_dir}/${package}-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-${SPACK_OS}-hashes.txt"
    local mirror_path="${mirror_base}/s${qualifier}-${e_version}/"

    log_info "Pushing ${package}@${version} s=${qualifier} to buildcache at ${mirror_path}"

    if ! cd "${hash_dir}"; then
        log_error "Failed to change directory to ${hash_dir}"
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
            log_error "Failed to create mirror directory: ${mirror_path}"
            return 1
        }
    fi

    local hashes
    hashes=$(grep -vE "^(--|$)" < "${hash_file}" | awk '{printf ("/%s\n", $1) }')

    if [[ -z "${hashes}" ]]; then
        log_error "No hashes found in ${hash_file}"
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
                log_warn "${package}@${version} s=${qualifier} is already in the buildcache"
                already_in_cache=true
                first_hash=false
                log_warn "Skipping remaining hashes since the top package was already pushed to buildcache"
                break
            fi
        else
          log_error "Failed to push hash ${hash} to buildcache"
          log_error "Error: ${output}"
        fi

        ((hash_count++))
    done <<< "${hashes}"

    if [[ $hash_count -eq 0 ]] && [[ "$already_in_cache" != true ]]; then
        log_error "No hashes were successfully pushed to buildcache"
        return 1
    elif [[ "$already_in_cache" == true ]]; then
        log_warn "Package was already in buildcache, pushed ${hash_count} additional hashes"
    else
        log_info "Successfully pushed ${hash_count} hashes to buildcache"
    fi

    return 0
}

update_buildcache_index() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"

    if [[ -z "$version" || -z "$qualifier" ]]; then
        log_error "Version and qualifier are required"
        return 1
    fi

    local e_version
    e_version=$(get_qualifier_e_version "$SPACK_GCC_VERSION")
    local mirror_path="${mirror_base}/s${qualifier}-${e_version}/"

    if [[ ! -d "${mirror_path}" ]]; then
        log_info "Creating mirror directory: ${mirror_path}"
        mkdir -p "${mirror_path}" || {
            log_error "Failed to create mirror directory: ${mirror_path}"
            return 1
        }
    fi

    log_info "Updating buildcache index at ${mirror_path}"

    if ! cd "${spack_dir}/${spack_version}"; then
        log_error "Failed to change directory to ${spack_dir}/${spack_version}"
        return 1
    fi

    log_command "spack buildcache update-index \"${mirror_path}\""
    if ! spack buildcache update-index "${mirror_path}"; then
        log_error "Failed to update buildcache index for ${mirror_path}"
        return 1
    fi

    log_info "Successfully updated buildcache index at ${mirror_path}"
    return 0
}

spack_reindex() {
    log_info "Reindexing spack database"
    log_command "spack reindex"

    if ! spack reindex; then
        log_error "Failed to reindex spack database"
        return 1
    fi

    return 0
}

process_version_qualifier() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    local package="$6"

    qualifier="${qualifier#s}"

    if [[ -z "$version" || -z "$qualifier" || -z "$package" ]]; then
        log_error "Version, qualifier, and package name are required"
        return 1
    fi

    if ! ensure_log_directory; then
        log_warn "Failed to create log directory, continuing anyway"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local process_log="${LOGS_DIR}/${package}-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-${SPACK_OS}.${timestamp}-process.log"

    log_info "Processing ${package}@${version} s=${qualifier}, logging to ${process_log}"

    {
        if ! install_package "$version" "$qualifier" "$package"; then
            log_error "Failed to install package ${package}@${version} s=${qualifier}"
            return 1
        fi

        if ! spack_reindex; then
            log_warn "Spack reindex failed, continuing anyway"
        fi

        if ! generate_spec "$spack_dir" "$spack_version" "$version" "$qualifier" "$package"; then
            log_error "Failed to generate spec for ${package}@${version} s=${qualifier}"
            return 1
        fi

        if ! generate_hashes "$spack_dir" "$spack_version" "$version" "$qualifier" "$package"; then
            log_error "Failed to generate hashes for ${package}@${version} s=${qualifier}"
            return 1
        fi

        if ! push_to_buildcache "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier" "$package"; then
            log_error "Failed to push ${package}@${version} s=${qualifier} to buildcache"
            return 1
        fi

        if ! update_buildcache_index "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier"; then
            log_error "Failed to update buildcache index for s${qualifier}"
            return 1
        fi

        log_info "Successfully processed ${package}@${version} s=${qualifier}"
    } 2>&1 | tee -a "${process_log}"

    local result=${PIPESTATUS[0]}

    if [[ $result -eq 0 ]]; then
        log_info "Process completed successfully and log saved to ${process_log}"
    else
        log_error "Process failed with status $result, see log at ${process_log}"
    fi

    return $result
}

process_package_versions_qualifiers() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local package_name="$4"
    local versions_str="$5"
    local qualifiers_str="$6"

    local -a versions=()
    local -a qualifiers=()
    IFS=':' read -ra versions <<< "$versions_str"
    IFS=':' read -ra qualifiers <<< "$qualifiers_str"

    [[ ${#versions[@]} -eq 0 ]] && log_error "No versions specified" && return 1
    [[ ${#qualifiers[@]} -eq 0 ]] && log_error "No qualifiers specified" && return 1

    log_info "Processing ${package_name} with ${#versions[@]} versions and ${#qualifiers[@]} qualifiers"

    local failures=0

    for version in "${versions[@]}"; do
        for qualifier in "${qualifiers[@]}"; do
            if ! process_version_qualifier "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier" "$package_name"; then
                log_error "Failed to process ${package_name}@${version} ${qualifier}"
                ((failures++))
            fi
        done
    done

    if [[ $failures -gt 0 ]]; then
        log_warn "Completed with $failures failures"
        return 1
    fi

    log_info "Successfully processed all ${package_name} versions and qualifiers"
    return 0
}

ensure_directories() {
    local spack_dir="$1"
    local spack_version="$2"
    local spack_mirror_base="$3"

    if [[ ! -d "${spack_dir}" ]]; then
        log_error "Spack directory not found: ${spack_dir}"
        log_error "This directory must exist and contain the Spack installation"
        return 1
    fi

    if [[ ! -d "${spack_dir}/${spack_version}" ]]; then
        log_error "Spack version directory not found: ${spack_dir}/${spack_version}"
        log_error "The specific Spack version must be installed before running this script"
        return 1
    fi

    if [[ ! -d "${spack_mirror_base}" ]]; then
        log_warn "Mirror base directory not found: ${spack_mirror_base}"
        if [[ "${NON_INTERACTIVE}" == true ]]; then
            log_info "Non-interactive mode: automatically creating mirror directory"
            mkdir -p "${spack_mirror_base}" || {
                log_error "Failed to create mirror directory: ${spack_mirror_base}"
                return 1
            }
        else
            if ask_for_continue; then
                log_info "Creating mirror directory: ${spack_mirror_base}"
                mkdir -p "${spack_mirror_base}" || {
                    log_error "Failed to create mirror directory: ${spack_mirror_base}"
                    return 1
                }
            else
                log_error "Cannot continue without mirror directory"
                return 1
            fi
        fi
    fi

    return 0
}

main() {
    if [[ ! -f "${COMMON_CONFFILE}" ]]; then
        log_info "Creating test configuration file: ${COMMON_CONFFILE}..."
        cat > "${COMMON_CONFFILE}" << EOF
SOFTWARE_BASE=/daq/software
SPACK_DIR=\${SOFTWARE_BASE}/spack_packages/spack
SPACK_VERSION=v1.0.1.sbnd
SPACK_MIRROR_BASE=\${SOFTWARE_BASE}/spack_mirrors/sbndaq-suite
GCC_VERSION=13.1.0
DAQ_SUITE_NAME=sbndaq-suite
DAQ_SUITE_VERSIONS=migration_artdaqv3_13_02:migration_artdaqv4_01_00
DAQ_SUITE_QUALIFIERS=s131:s132
EOF
      log_info "A new configuration file has been created at ${COMMON_CONFFILE}"
      log_info "Please review its contents and run the script again."
      return 1
    fi

    log_debug "Loading ${COMMON_CONFFILE}"
    if ! load_build_config; then
        log_error "Failed to load ${COMMON_CONFFILE}"
        return 1
    fi

    local software_base="${SOFTWARE_BASE}"
    local spack_dir="${SPACK_DIR}"
    local spack_version="${SPACK_VERSION}"
    local spack_mirror_base="${SPACK_MIRROR_BASE}"
    local gcc_version="${GCC_VERSION}"
    local daq_suite_name="${DAQ_SUITE_NAME}"
    local versions_str="${DAQ_SUITE_VERSIONS}"
    local qualifiers_str="${DAQ_SUITE_QUALIFIERS}"

    if ! ensure_log_directory; then
        log_warn "Failed to create log directory, continuing anyway"
    fi

    local timestamp=$(date +%Y%m%d_%H%M%S)
    local build_log="${LOGS_DIR}/build.${timestamp}.log"
    exec > >(tee -a "${build_log}") 2>&1
    log_info "Starting build script, logging to ${build_log}"

    parse_arguments "$@"
    setup_signal_handlers

    if ! ensure_directories "$spack_dir" "$spack_version" "$spack_mirror_base"; then
        log_error "Directory setup failed"
        exit 1
    fi

    if ! setup_environment "$spack_dir" "$spack_version" "$gcc_version"; then
        log_error "Failed to set up environment"
        exit 1
    fi

    log_info "Starting ${daq_suite_name} Build"
    log_debug "Spack directory: ${spack_dir}"
    log_debug "Spack version: ${spack_version}"
    log_debug "Spack mirror dir: ${spack_mirror_base}"
    log_info "Using GCC ${gcc_version}"
    log_info "Using qualifiers: ${qualifiers_str//:/ }"
    log_info "Using versions: ${versions_str//:/ }"

    if ! process_package_versions_qualifiers "$spack_dir" "$spack_version" "$spack_mirror_base" "$daq_suite_name" "$versions_str" "$qualifiers_str"; then
        log_warn "Some ${daq_suite_name} packages failed"
        exit 1
    fi

    log_info "Build completed successfully"
    return 0
}

export PS1='\[\033[0;35m\]\t\[\033[0;33m\]\u\[\033[0;35m\]@\[\033[0;36m\]\h\[\033[0;32m\]:\w\[\033[0;32m\]\n$ \[\e[m\]'

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit $?
fi

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    parse_arguments "$@"
    log_debug "Finished sourcing $(basename "${BASH_SOURCE[0]}")..."
fi

