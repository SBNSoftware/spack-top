#!/usr/bin/env bash

set -eo pipefail

setup_environment() {
    local spack_dir="$1"
    local spack_version="$2"
    local gcc_version="$3"

    cd "${spack_dir}/${spack_version}" || { echo "Failed to change directory to ${spack_dir}/${spack_version}" >&2; exit 1; }
    export SPACK_DISABLE_LOCAL_CONFIG=true
    source "${spack_dir}/${spack_version}/setup-env.sh" || { echo "Failed to source setup-env.sh" >&2; exit 1; }
    export SPACK_DISABLE_LOCAL_CONFIG=true
    export SPACK_GCC_VERSION="${gcc_version}"
    export SPACK_MICRO_ARCH='v2'
    export SPACK_OS=$(spack arch -o)
    export SPACK_J=$(nproc)
    export SPACK_ARCH="linux-${SPACK_OS}-x86_64_${SPACK_MICRO_ARCH}"
    export SPACK_INSTALL_OPTS=" -y -j${SPACK_J} --deprecated --fresh --no-cache --source"
    echo "SPACK_ARCH:${SPACK_ARCH}"
}

install_package() {
    local version="$1"
    local qualifier="$2"
    
    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi
    
    spack install ${SPACK_INSTALL_OPTS} artdaq-suite@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${SPACK_GCC_VERSION}
}

generate_spec() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    
    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi
    
    cd "${spack_dir}/${spack_version}/hashes/" || { echo "Failed to change directory to ${spack_dir}/${spack_version}/hashes/" >&2; return 1; }
    spack spec artdaq-suite@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${SPACK_GCC_VERSION} > "artdaq-suite-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}.txt"
}

generate_hashes_v1() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"
    
    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi
    
    cd "${spack_dir}/${spack_version}/hashes/" || { echo "Failed to change directory to ${spack_dir}/${spack_version}/hashes/" >&2; return 1; }
    spack unload --all
    spack load artdaq-suite@${version} s=${qualifier} arch=${SPACK_ARCH} %gcc@${SPACK_GCC_VERSION}
    spack find -ldfv --loaded > "artdaq-suite-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-hashes.txt"
}

generate_hashes_v2() {
    local spack_dir="$1"
    local spack_version="$2"
    local version="$3"
    local qualifier="$4"

    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi

    cd "${spack_dir}/${spack_version}/hashes/" || { echo "Failed to change directory to ${spack_dir}/${spack_version}/hashes/" >&2; return 1; }
    spack unload --all

    local package_count
    package_count=$(spack find -lpfv "artdaq-suite@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" | grep -Eo '/daq/software/.*$' | wc -l)

    if [[ $package_count -gt 1 ]]; then
        local latest_package
        latest_package=$(/bin/ls -ldtr $(spack find -lpfv "artdaq-suite@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}" | grep -Eo '/daq/software/.*$') | tail -1 | awk '{print $NF}')
        
        local hash
        hash=$(basename "$latest_package" | grep -Eo '[^-]+$')
        
        spack load "artdaq-suite@${version}" "/${hash}"
    else
        spack load "artdaq-suite@${version}" "s=${qualifier}" "arch=${SPACK_ARCH}" "%gcc@${SPACK_GCC_VERSION}"
    fi
    
    spack find -ldfv --loaded > "artdaq-suite-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-hashes.txt"
}

get_qualifier_e_version() {
    local gcc_version="$1"
    
    if [[ "$gcc_version" == "13.1.0" ]]; then
        echo "e28"
    elif [[ "$gcc_version" == "12.1.0" ]]; then
        echo "e26"
    else
        echo "e28"  # Default to e28 for other gcc versions
    fi
}

push_to_buildcache() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    
    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi
    
    local e_version=$(get_qualifier_e_version "$SPACK_GCC_VERSION")
    
    cd "${spack_dir}/${spack_version}/hashes/" || { echo "Failed to change directory to ${spack_dir}/${spack_version}/hashes/" >&2; return 1; }
    
    /bin/cat "artdaq-suite-${version}-s${qualifier}-gcc-${SPACK_GCC_VERSION}-hashes.txt" | \
    grep -vE "^(--|$)" | \
    awk '{printf ("/%s\n", $1) }' | \
    xargs -I{} spack buildcache push --only package "${mirror_base}/s${qualifier}-${e_version}/" {}
}

update_buildcache_index() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"

    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi

    local e_version=$(get_qualifier_e_version "$SPACK_GCC_VERSION")

    cd "${spack_dir}/${spack_version}" || { echo "Failed to change directory to ${spack_dir}/${spack_version}" >&2; return 1; }
    
    spack buildcache update-index "${mirror_base}/s${qualifier}-${e_version}/" || {
        echo "Failed to update buildcache index for ${mirror_base}/s${qualifier}-${e_version}/" >&2
        return 1
    }
}

process_version_qualifier() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local version="$4"
    local qualifier="$5"
    
    if [[ -z "$version" || -z "$qualifier" ]]; then
        echo "Version and qualifier are required" >&2
        return 1
    fi
    
    install_package "$version" "$qualifier"
    generate_spec "$spack_dir" "$spack_version" "$version" "$qualifier"
    generate_hashes_v2 "$spack_dir" "$spack_version" "$version" "$qualifier"
    push_to_buildcache "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier"
    update_buildcache_index "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier"
}

process_all_versions_qualifiers() {
    local spack_dir="$1"
    local spack_version="$2"
    local mirror_base="$3"
    local versions=("${@:4}")
    local qualifiers=(132 131)
    
    if [[ ${#versions[@]} -eq 0 ]]; then
        #versions=(v3_13_01 v3_13_02)
        versions=(v4_01_00 v3_13_01 v3_13_02)
    fi
    
    for version in "${versions[@]}"; do
        for qualifier in "${qualifiers[@]}"; do
            process_version_qualifier "$spack_dir" "$spack_version" "$mirror_base" "$version" "$qualifier"
        done
    done
}

main() {
    local software_base="/daq/software"
    local spack_dir="${software_base}/spack_packages/spack"
    local spack_version="v1.0.1.sbnd"
    local mirror_base="${software_base}/spack_mirrors/artdaq-suite"
    local gcc_version="${1:-13.1.0}"
    
    # Validate GCC version
    if [[ "$gcc_version" != "13.1.0" && "$gcc_version" != "12.1.0" ]]; then
        echo "Unsupported GCC version: $gcc_version. Supported versions are 13.1.0 (default) and 12.1.0." >&2
        exit 1
    fi
    
    shift || true
    
    setup_environment "$spack_dir" "$spack_version" "$gcc_version"
    process_all_versions_qualifiers "$spack_dir" "$spack_version" "$mirror_base" "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
