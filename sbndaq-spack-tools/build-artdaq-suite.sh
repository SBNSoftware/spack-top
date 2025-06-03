#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${_BUILD_ARTDAQ_SUITE_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _BUILD_ARTDAQ_SUITE_SH_=1

export LOGS_DIR=/tmp/artdaq-suite-build-logs

SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/modules/build-anydaq-suite.sh"

# Configuration loading
readonly BUILD_ARTDAQ_ENVFILE=${BUILD_ARTDAQ_ENVFILE:-"$(basename "${BASH_SOURCE[0]%.*}").env"}

# Display help if requested directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]] && [[ -n "${1:-}" ]] && [[ "$1" =~ ^(-h|--help)$ ]]; then
    print_usage "$(basename "$0")" "artdaq-suite"
    exit 0
fi

# Set prompt for interactive shells
export PS1='\[\033[0;35m\]\t\[\033[0;33m\]\u\[\033[0;35m\]@\[\033[0;36m\]\h\[\033[0;32m\]:\w\[\033[0;32m\]\n$ \[\e[m\]'

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_info "Sourcing $(basename "${BASH_SOURCE[0]}")..."
fi

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    run_artdaq_build build-artdaq-suite.env
fi
