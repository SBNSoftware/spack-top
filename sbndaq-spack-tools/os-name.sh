#!/bin/bash

show_usage() {
    cat << EOF
Usage: $0 [OPTION]
Detect OS name based on kernel version.

Options:
  -h, --help, /?    Show this help message and exit

Examples:
  $0                Get OS name from kernel version
  $0 --help         Show this help message

Exit codes:
  0                 Success
  1                 Unknown OS or error
EOF
}

get_os_name_from_kernel() {
    local kernel_version major minor
    
    kernel_version=$(uname -r 2>/dev/null) || { echo "UnknownOS"; return 1; }
    
    IFS='.' read -r major minor _ <<< "$kernel_version" || { echo "UnknownOS"; return 1; }
    
    case "$major.$minor" in
        "3.10") echo "scientific7" ;;
        "5.14") echo "almalinux9" ;;
        *) echo "UnknownOS"; return 1 ;;
    esac
}

main() {
    case "${1:-}" in
        -h|--help|/?)
            show_usage
            exit 0
            ;;
        "")
            get_os_name_from_kernel
            ;;
        *)
            echo "Error: Invalid option '$1'" >&2
            show_usage >&2
            exit 1
            ;;
    esac
}

main "$@"
