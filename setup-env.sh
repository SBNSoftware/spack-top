#!/bin/bash

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Error: This script must be sourced, not executed directly."
  echo "Please use: source ${0}"
  exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SETUP_FILE="${SCRIPT_DIR}/NULL/share/spack/setup-env.sh"
if [[ -f "${SETUP_FILE}" ]]; then
  source "${SETUP_FILE}"
else
  echo "Error: Could not find ${SETUP_FILE}"
  return 1
fi

