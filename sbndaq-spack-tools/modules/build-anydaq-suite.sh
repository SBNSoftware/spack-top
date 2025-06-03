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
source "${SCRIPT_DIR}/suite-functions.sh"

# If directly executed (not sourced), display help
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    log_info "This script provides common functions for building DAQ packages"
    log_info "It should be sourced by other scripts, not executed directly"
    exit 0
fi

# Log when sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"
fi 