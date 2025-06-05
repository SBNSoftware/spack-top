#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Script configuration
SPACK_ENVFILE="$(basename "${BASH_SOURCE[0]%.*}").env"

# Ensure script is executed, not sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    echo "Error: This script should be executed, not sourced."
    return 1
fi

# Source required scripts
MAIN_SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${MAIN_SCRIPT_DIR}/modules/common-functions.sh"
source "${MAIN_SCRIPT_DIR}/modules/spack-unified.sh"

# Main script function
main() {
    # Display help if requested
    if [[ $# -gt 0 && ("$1" == "-h" || "$1" == "/?" || "$1" == "--help") ]]; then
        print_usage
        exit 0
    fi

    setup_daq_development_area "suite" "${SPACK_ENVFILE}" "$@"
    
    return $?
}

# Run the main function
main "$@"