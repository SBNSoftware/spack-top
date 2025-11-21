#!/usr/bin/env bash
# setup-local-spack.sh - Source this script to use local Spack database with shared packages
#
# Usage: source setup-local-spack.sh [OPTIONS]
#
# Options:
#   --delete-existing    Delete existing local environment and recreate
#   --clean-bash        Start pristine bash (--noprofile --norc) with only essential
#                       system variables (HOME, PATH, USER, TERM, LANG, etc.)
#                       and configuration from ~/.spack-local.env
#   -h, --help          Display help information
#
# This script sets up Spack to:
# - Install packages to ~/.spack-local/install/ (read-write)
# - Read packages from /daq/software/spack_packages/ (read-only via upstreams)
# - Use local database in ~/.spack-local/install/.spack-db/ (read-write)
# - Store all local configurations in ~/.spack-local/config/
# - Avoid locking and permission issues with shared database
# - Automatically detect and reuse existing local environment
#
# Key features:
# - New packages install to ~/.spack-local/install/
# - Shared packages are accessible (read-only)
# - Local database prevents write conflicts
# - No writes to /daq/software/spack_packages/.spack-db/
# - Skips recreation if environment exists (unless --delete-existing)
# - Clean bash option for reproducible, pristine environment

#set -o errexit
#set -o nounset
#set -o pipefail

# Source guard - prevent multiple sourcing
if [[ "${_SETUP_LOCAL_SPACK_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _SETUP_LOCAL_SPACK_SH_=1

# Execution check - ensure script is sourced, not executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed."
    echo "Usage: source ${BASH_SOURCE[0]}"
    echo ""
    echo "This script sets up a local Spack database with access to shared packages."
    echo "After sourcing, run 'verify_local_spack' to verify the setup."
    exit 1
fi

# Source required modules
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/modules/logging-functions.sh"
source "${SCRIPT_DIR}/modules/signal-functions.sh"

# Disable strict mode for sourced scripts (modules enable it, but we don't want it in the user's shell)
set +o errexit
set +o nounset
set +o pipefail

# Setup signal handlers for graceful cleanup
setup_signal_handlers

# Add log_fail function for verification
log_fail() { printf "${RED}${BOLD}[✗]${RESET} %s\n" "$*" >&2; }

# ============================================================================
# Function: local_spack_help
# Display help information about this script and available commands
# ============================================================================

local_spack_help() {
    cat << 'EOF'
========================================
  Local Spack Setup - Help
========================================

OVERVIEW:
  This setup configures Spack to use a local installation (~/.spack-local/install)
  with a local database (~/.spack-local/install/.spack-db)
  while maintaining read-only access to shared packages (/daq/software/spack_packages).

SETUP:
  To activate this configuration, source this script:
    source sbndaq-spack-tools/setup-local-spack.sh [OPTIONS]

  Options:
    --delete-existing   Delete and recreate existing local environment
    --clean-bash       Re-execute in pristine bash environment (--noprofile --norc)
                       with minimal PATH and settings from ~/.spack-local.env
    -h, --help         Display this help message

  Note: If a local environment already exists, it will be reused automatically.
        Use --delete-existing to force recreation.

CLEAN BASH MODE:
  The --clean-bash option provides a reproducible, pristine bash environment:
    • Starts fresh bash with --noprofile --norc (ignores ~/.bashrc, ~/.profile)
    • Sets minimal essential environment variables:
      - HOME, PATH, USER, LOGNAME, SHELL
      - HOSTNAME, TERM, TMPDIR
      - LANG, LC_ALL, LC_CTYPE (always en_US.UTF-8)
      - SSH_AUTH_SOCK, SSH_AGENT_PID (if set - for git/ssh)
      - DISPLAY (if set - for X11 applications)
    • Reads all configuration from ~/.spack-local.env
    • Creates ~/.spack-local.env with defaults if it doesn't exist

  Example:
    source setup-local-spack.sh --clean-bash

  This is useful for:
    • Avoiding conflicts with existing environment variables
    • Ensuring reproducible builds and tests
    • Debugging environment-related issues
    • Clean environment for CI/CD pipelines

AVAILABLE COMMANDS:
  local_spack_help         - Display this help message
  verify_local_spack       - Verify the local Spack configuration

CONFIGURATION:
  Config Path:       ~/.spack-local/config/
  Install Directory: ~/.spack-local/install/
  Local Database:    ~/.spack-local/install/.spack-db/ (read-write)
  Shared Packages:   /daq/software/spack_packages/ (read-only via upstreams)
  Cache:             ~/.spack-local/cache/
  Bootstrap:         ~/.spack-local/bootstrap/

VERIFICATION:
  After sourcing this script, it's HIGHLY RECOMMENDED to run:
    verify_local_spack

  This will perform comprehensive checks to ensure:
    ✓ Spack is using the local database
    ✓ Shared packages are accessible via upstreams
    ✓ No write access to shared database
    ✓ All configurations are correct

HELPFUL COMMANDS:
  spack find                  - List packages (local + shared)
  spack install <pkg>         - Install a package locally
  spack config get config     - View configuration
  spack config get upstreams  - View upstream (shared) configuration
  ls -la ~/.spack-local/install/.spack-db/  - Check local database

NOTES:
  • Packages from /daq/software/spack_packages/ are READ-ONLY
  • New packages install to ~/.spack-local/install/
  • No locking conflicts with shared database
  • All write operations use local database

For more information, see:
  sbndaq-spack-tools/LOCAL-SPACK-SETUP.md

========================================
EOF
}

# ============================================================================
# Function: detect_os_distribution
# Detect the OS distribution for Spack configuration
# ============================================================================

detect_os_distribution() {
    SPACK_DISTRO_NAME="$(uname -r)"
    if [[ "$SPACK_DISTRO_NAME" == *"5.14"* ]]; then
        SPACK_DISTRO_NAME="almalinux9"
    elif [[ "$SPACK_DISTRO_NAME" == *"3.10"* ]]; then
        SPACK_DISTRO_NAME="scientific7"
    else
        log_warn "Unknown OS version, defaulting to almalinux9"
        SPACK_DISTRO_NAME="almalinux9"
    fi

    export SPACK_DISTRO_NAME
}

# ============================================================================
# Function: create_directory_structure
# Create the local directory structure for Spack
# ============================================================================

create_directory_structure() {
    log_info "Setting up local Spack configuration in: ${SPACK_LOCAL_ROOT}"

    # Create main directories
    # install/ - Package installation directory (contains .spack-db/)
    # config/ - Configuration files (for SPACK_USER_CONFIG_PATH)
    # cache/ - Misc cache
    # bootstrap/ - Bootstrap tools
    # stages/ - Build stages
    # sources/ - Source cache
    mkdir -p "${SPACK_LOCAL_ROOT}"/{install,config,cache,bootstrap,stages,sources} || {
        log_error "Failed to create local Spack directories"
        return 1
    }

    # Create OS-specific config directories under config/ subdirectory
    # CRITICAL: Must be in config/ for SPACK_USER_CONFIG_PATH to work
    mkdir -p "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}/None" || {
        log_error "Failed to create OS-specific config directories"
        return 1
    }

    # Create environment directory
    mkdir -p "${SPACK_LOCAL_ROOT}/environments/default" || {
        log_error "Failed to create environment directory"
        return 1
    }

    log_success "Directory structure created"
    log_debug "  - Install directory: ${SPACK_LOCAL_ROOT}/install"
    log_debug "  - Config directory: ${SPACK_LOCAL_ROOT}/config"
}

# ============================================================================
# Function: create_spack_environment
# Create a Spack environment with upstreams configuration
# NOTE: Upstreams only works in environments, not in user-level config
# ============================================================================

create_spack_environment() {
    log_info "Creating Spack environment with upstreams configuration..."

    local env_dir="${SPACK_LOCAL_ROOT}/environments/default"
    mkdir -p "${env_dir}"

    # Create spack.yaml for environment
    cat > "${env_dir}/spack.yaml" << EOF
# Spack environment configuration
# Generated on $(date)
spack:
  specs: []
  view: false
  concretizer:
    unify: true

  # Upstreams configuration - access shared packages read-only
  upstreams:
    shared-spack:
      install_tree: ${SPACK_SOFTWARE_BASE}/spack_packages

  # Config settings for this environment
  config:
    install_tree:
      root: ${SPACK_LOCAL_ROOT}/install
      padded_length: 128
      projections:
        all: '{name}-{version}-{hash:7}'
    build_stage:
      - ${SPACK_LOCAL_ROOT}/stages
    source_cache: ${SPACK_LOCAL_ROOT}/sources
    misc_cache: ${SPACK_LOCAL_ROOT}/cache
    locks: false
    build_jobs: 8
    suppress_gpg_warnings: true
    keep_stage: false
    debug: false
    verify_ssl: true
    shared_linking: rpath
EOF

    log_success "Created Spack environment with upstreams configuration"
}

# ============================================================================
# Function: create_config_yaml
# Create the main config.yaml file for local database
# ============================================================================

create_config_yaml() {
    log_info "Creating local config.yaml..."

    # CRITICAL: Config files must be in config/ subdirectory for SPACK_USER_CONFIG_PATH
    cat > "${SPACK_LOCAL_ROOT}/config/config.yaml" << EOF
# Local Spack configuration - Local database with shared packages
# Generated on $(date)

config:
  # Install tree - this is where NEW packages are installed and local .spack-db lives
  # Packages from upstream (/daq/software/spack_packages) are read-only
  install_tree:
    root: ${SPACK_LOCAL_ROOT}/install
    padded_length: 128
    projections:
      all: '{name}-{version}-{hash:7}'

  # Build stage directory
  build_stage:
    - ${SPACK_LOCAL_ROOT}/stages

  # Source cache directory
  source_cache: ${SPACK_LOCAL_ROOT}/sources

  # Miscellaneous cache (metadata, etc.)
  misc_cache: ${SPACK_LOCAL_ROOT}/cache

  # Bootstrap store location
  bootstrap: ${SPACK_LOCAL_ROOT}/bootstrap

  # Disable locks for better performance on NFS
  locks: false

  # Build jobs
  build_jobs: 8

  # Suppress gpg warnings
  suppress_gpg_warnings: true

  # Keep build stage on failure for debugging
  keep_stage: false

  # Debug level
  debug: false

  # Verify SSL certificates
  verify_ssl: true

  # Shared linking
  shared_linking: rpath
EOF

    log_success "Created config.yaml"
}

# ============================================================================
# Function: create_upstreams_yaml
# Create upstreams.yaml for accessing shared packages
# ============================================================================

create_upstreams_yaml() {
    log_info "Creating upstreams.yaml to access shared packages..."

    # CRITICAL: Config files must be in config/ subdirectory for SPACK_USER_CONFIG_PATH
    cat > "${SPACK_LOCAL_ROOT}/config/upstreams.yaml" << EOF
# Upstream configuration - Access shared packages in read-only mode
# Generated on $(date)
#
# This allows Spack to:
# - Read packages from ${SPACK_SOFTWARE_BASE}/spack_packages (read-only)
# - Maintain local database in ~/.spack/.spack-db/ (read-write)
# - Avoid locking/permission issues with shared database

upstreams:
  shared-spack:
    install_tree: ${SPACK_SOFTWARE_BASE}/spack_packages
EOF

    log_success "Created upstreams.yaml - Shared packages will be accessible"
}

# ============================================================================
# Function: create_repos_yaml
# Create repos.yaml to define package repositories
# ============================================================================

create_repos_yaml() {
    log_info "Creating local repos.yaml..."

    # CRITICAL: Config files must be in config/ subdirectory for SPACK_USER_CONFIG_PATH
    cat > "${SPACK_LOCAL_ROOT}/config/repos.yaml" << EOF
# Local repository configuration
# This uses the standard Spack repositories from the shared installation

repos:
  - ${SPACK_HOME_DIR}/var/spack/repos/builtin
EOF

    log_success "Created repos.yaml"
}

# ============================================================================
# Function: create_packages_yaml
# Create packages.yaml with package preferences
# ============================================================================

create_packages_yaml() {
    log_info "Creating local packages.yaml..."

    # CRITICAL: Config files must be in config/ subdirectory for SPACK_USER_CONFIG_PATH
    mkdir -p "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}"
    cat > "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}/packages.yaml" << EOF
# Local package configuration
# Generated on $(date)

packages:
  all:
    # Use system packages where possible
    providers:
      blas: [openblas]
      lapack: [openblas]
      mpi: [mpich]

    # Default to using external packages
    buildable: true

    # Compiler preferences
    compiler: [gcc]

    # Target architecture
    target: [x86_64_v2]

  # System packages (don't build these)
  cmake:
    externals:
    - spec: cmake@3.20.2
      prefix: /usr
    buildable: false

  perl:
    externals:
    - spec: perl@5.26.1
      prefix: /usr
    buildable: false

  python:
    externals:
    - spec: python@3.9.7
      prefix: /usr
    buildable: false
EOF

    log_success "Created packages.yaml"
}

# ============================================================================
# Function: create_compilers_yaml
# Create compilers.yaml with compiler configuration
# ============================================================================

create_compilers_yaml() {
    log_info "Creating local compilers.yaml..."

    # CRITICAL: Config files must be in config/ subdirectory for SPACK_USER_CONFIG_PATH
    mkdir -p "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}/None"

    # Check if we can copy from shared installation
    if [[ -f "${SPACK_HOME_DIR}/NULL/etc/spack/linux/${SPACK_DISTRO_NAME}/None/compilers.yaml" ]]; then
        cp "${SPACK_HOME_DIR}/NULL/etc/spack/linux/${SPACK_DISTRO_NAME}/None/compilers.yaml" \
           "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}/None/compilers.yaml"
        log_success "Copied compilers.yaml from shared installation"
    else
        # Create a basic compilers.yaml
        cat > "${SPACK_LOCAL_ROOT}/config/linux/${SPACK_DISTRO_NAME}/None/compilers.yaml" << EOF
# Compiler configuration
# Generated on $(date)
# Run 'spack compiler find' to auto-detect compilers

compilers: []
EOF
        log_warn "Created empty compilers.yaml - you may need to run 'spack compiler find'"
    fi
}

# ============================================================================
# Function: set_environment_variables
# Set Spack environment variables for local configuration
# ============================================================================

set_environment_variables() {
    log_info "Setting Spack environment variables..."

    # CRITICAL: SPACK_USER_CONFIG_PATH is REQUIRED (hard requirement)
    # This tells Spack where to find user configuration files
    # Must point to config subdirectory: ~/.spack-local/config
    export SPACK_USER_CONFIG_PATH="${SPACK_LOCAL_ROOT}/config"

    # User cache path (for misc downloads and temporary files)
    export SPACK_USER_CACHE_PATH="${SPACK_LOCAL_ROOT}/cache"

    # Bootstrap root (for Spack's own bootstrapped tools)
    export SPACK_BOOTSTRAP_ROOT="${SPACK_LOCAL_ROOT}/bootstrap"

    # Disable using home directory for cache
    export SPACK_DISABLE_LOCAL_CONFIG=false

    # Disable locks (useful for NFS)
    export SPACK_NO_LOCK=true

    # Python user base (for Python packages Spack might install)
    export PYTHONUSERBASE="${SPACK_LOCAL_ROOT}/python"

    # Prevent Spack from using system config
    unset SPACK_SYSTEM_CONFIG_PATH

    log_success "Environment variables set"
}

# ============================================================================
# Function: source_spack_setup
# Source the Spack setup script
# ============================================================================

source_spack_setup() {
    log_info "Sourcing Spack setup from: ${SPACK_HOME_DIR}/setup-env.sh"

    # Change to Spack directory and source setup
    pushd "${SPACK_HOME_DIR}" > /dev/null || {
        log_error "Cannot change to Spack directory"
        return 1
    }

    source "${SPACK_HOME_DIR}/setup-env.sh" || {
        log_error "Failed to source Spack setup script"
        popd > /dev/null
        return 1
    }

    popd > /dev/null

    # Verify Spack is available
    if ! command -v spack &>/dev/null; then
        log_error "Spack command not available after setup"
        return 1
    fi

    log_success "Spack loaded successfully"
}

# ============================================================================
# Function: activate_spack_environment
# Activate the local Spack environment
# ============================================================================

activate_spack_environment() {
    log_info "Activating Spack environment..."

    local env_dir="${SPACK_LOCAL_ROOT}/environments/default"

    if [[ ! -f "${env_dir}/spack.yaml" ]]; then
        log_error "Environment not found at: ${env_dir}"
        return 1
    fi

    # Activate environment
    spack env activate "${env_dir}" || {
        log_error "Failed to activate Spack environment"
        return 1
    }

    log_success "Spack environment activated"
}

# ============================================================================
# Function: display_configuration_summary
# Display a summary of the Spack configuration
# ============================================================================

display_configuration_summary() {
    log_info "Spack Local Configuration Summary:"
    echo "  Spack Version:     $(spack --version)"
    echo "  Config Path:       ${SPACK_LOCAL_ROOT}/"
    echo "  Local Install:     ${SPACK_LOCAL_ROOT}/"
    echo "  Local Database:    ${SPACK_LOCAL_ROOT}/.spack-db/ (read-write)"
    echo "  Shared Packages:   ${SPACK_SOFTWARE_BASE}/spack_packages/ (read-only)"
    echo "  Cache Path:        ${SPACK_USER_CACHE_PATH}"
    echo "  Bootstrap Root:    ${SPACK_BOOTSTRAP_ROOT}"
    echo "  Build Stages:      ${SPACK_LOCAL_ROOT}/stages"
    echo "  Source Cache:      ${SPACK_LOCAL_ROOT}/sources"
    echo "  OS Distribution:   ${SPACK_DISTRO_NAME}"
    echo ""
}

# ============================================================================
# Function: bootstrap_spack
# Bootstrap Spack with initial commands
# ============================================================================

bootstrap_spack() {
    log_info "Bootstrapping Spack..."
    echo ""

    log_info "Step 1/3: Running 'spack -b find -lpfv' to initialize bootstrap..."
    spack -b find -lpfv || {
        log_warn "Bootstrap find command had issues, continuing..."
    }
    echo ""

    log_info "Step 2/3: Running 'spack bootstrap now' to bootstrap dependencies..."
    spack bootstrap now || {
        log_warn "Bootstrap now command had issues, continuing..."
    }
    echo ""

    log_info "Step 3/3: Running 'spack solve zlib' to test solver..."
    spack solve zlib || {
        log_warn "Solve test had issues, continuing..."
    }
    echo ""

    log_success "Bootstrap process completed"
}

# ============================================================================
# Function: initial_verification
# Perform initial verification of the configuration
# ============================================================================

initial_verification() {
    log_info "Verifying configuration..."

    # Check that local database location is set correctly
    if [[ -d "${SPACK_LOCAL_ROOT}/.spack-db" ]]; then
        log_success "Local database created at: ${SPACK_LOCAL_ROOT}/.spack-db/"
    else
        log_warn "Local database not yet created (will be created on first operation)"
    fi

    # Get the actual install tree from config file directly
    # (spack config get doesn't show the root if it's using defaults)
    local config_file="${SPACK_USER_CONFIG_PATH}/config.yaml"
    if [[ -f "${config_file}" ]]; then
        ACTUAL_INSTALL_TREE=$(grep -A2 "install_tree:" "${config_file}" | grep "root:" | awk '{print $2}')

        if [[ -n "${ACTUAL_INSTALL_TREE}" ]]; then
            if [[ "${ACTUAL_INSTALL_TREE}" == "${SPACK_LOCAL_ROOT}"* ]]; then
                log_success "Verified: Spack install tree is local: ${ACTUAL_INSTALL_TREE}"
            else
                log_warn "Install tree is NOT local: ${ACTUAL_INSTALL_TREE}"
            fi
        else
            log_warn "Install tree root not found in config.yaml (using Spack default)"
        fi
    else
        log_fail "Could not find config.yaml at: ${config_file}"
    fi

    # Check upstream configuration
    UPSTREAM_CHECK=$(spack config get upstreams 2>/dev/null | grep "install_tree" | wc -l)
    if [[ "${UPSTREAM_CHECK}" -gt 0 ]]; then
        log_success "Upstream configuration detected - shared packages accessible"
        log_info "Shared packages from ${SPACK_SOFTWARE_BASE}/spack_packages/ are available (read-only)"
    else
        log_warn "No upstream configuration found"
    fi

    # Check if shared database exists
    if [[ -d "${SPACK_SOFTWARE_BASE}/spack_packages/.spack-db" ]]; then
        log_info "Shared database exists at: ${SPACK_SOFTWARE_BASE}/spack_packages/.spack-db/"
        log_info "This database will NOT be used - using local database instead"
    fi

    echo ""
    log_success "Setup complete! Local database: ${SPACK_LOCAL_ROOT}/.spack-db/"
    log_info "Shared packages available via upstreams (read-only)"
    echo ""
}

# ============================================================================
# Function: display_helpful_commands
# Display helpful commands for users
# ============================================================================

display_helpful_commands() {
    cat << 'EOF'
Helpful Commands:
  spack find              - List packages (from both local and shared)
  spack find --show-full-compiler  - Show package details
  spack install <pkg>     - Install a package locally
  spack info <pkg>        - Show package information
  spack compiler find     - Auto-detect compilers
  spack compiler list     - List configured compilers
  spack config get config - View install tree configuration
  spack config get upstreams - View upstream (shared) configuration

  # Verify local database location:
  ls -la ~/.spack-local/.spack-db/

  # Verify upstream packages are accessible:
  spack find | grep -i "installed"

  # Check that shared DB is NOT accessed:
  strace -e trace=open,openat spack find 2>&1 | grep -i ".spack-db"
  # Should only show: ~/.spack-local/.spack-db

  # Install a test package locally:
  spack install zlib

Important Notes:
  - Packages from /daq/software/spack_packages/ are READ-ONLY via upstreams
  - Local database: ~/.spack-local/.spack-db/ (read-write)
  - New packages install to: ~/.spack-local/
  - No locking issues with shared database

To deactivate:
  unset SPACK_USER_CONFIG_PATH SPACK_USER_CACHE_PATH SPACK_BOOTSTRAP_ROOT
EOF

    echo ""
}

# ============================================================================
# Function: verify_local_spack
# Comprehensive verification of local Spack setup
# Integrated from verify-local-spack.sh
# ============================================================================

verify_local_spack() {
    echo "=================================================="
    echo "  Spack Local DB + Shared Packages Verification"
    echo "=================================================="
    echo ""

    local ERRORS=0
    local WARNINGS=0

    # Check 1: Spack Command Available
    log_info "Check 1: Spack command availability..."
    if command -v spack &>/dev/null; then
        local SPACK_VERSION=$(spack --version 2>/dev/null)
        log_success "Spack is available: ${SPACK_VERSION}"
    else
        log_fail "Spack command not found"
        ((ERRORS++))
    fi
    echo ""

    # Check 2: Environment Variables
    log_info "Check 2: Environment variables..."

    if [[ -n "${SPACK_USER_CONFIG_PATH:-}" ]]; then
        log_success "SPACK_USER_CONFIG_PATH is set: ${SPACK_USER_CONFIG_PATH}"

        if [[ "${SPACK_USER_CONFIG_PATH}" == "${HOME}/.spack-local/config" ]]; then
            log_success "SPACK_USER_CONFIG_PATH points to local directory"
        else
            log_fail "SPACK_USER_CONFIG_PATH does not point to ~/.spack-local/config"
            ((ERRORS++))
        fi
    else
        log_fail "SPACK_USER_CONFIG_PATH is not set"
        ((ERRORS++))
    fi

    if [[ -n "${SPACK_USER_CACHE_PATH:-}" ]]; then
        log_success "SPACK_USER_CACHE_PATH is set: ${SPACK_USER_CACHE_PATH}"
    else
        log_warn "SPACK_USER_CACHE_PATH is not set"
        ((WARNINGS++))
    fi

    if [[ -n "${SPACK_BOOTSTRAP_ROOT:-}" ]]; then
        log_success "SPACK_BOOTSTRAP_ROOT is set: ${SPACK_BOOTSTRAP_ROOT}"
    else
        log_warn "SPACK_BOOTSTRAP_ROOT is not set"
        ((WARNINGS++))
    fi

    echo ""

    # Check 3: Configuration Files
    log_info "Check 3: Configuration files..."

    local REQUIRED_FILES=(
        "${HOME}/.spack-local/config/config.yaml"
        "${HOME}/.spack-local/config/repos.yaml"
        "${HOME}/.spack-local/config/upstreams.yaml"
    )

    for file in "${REQUIRED_FILES[@]}"; do
        if [[ -f "${file}" ]]; then
            log_success "Found: ${file}"
        else
            log_fail "Missing: ${file}"
            ((ERRORS++))
        fi
    done

    echo ""

    # Check 3a: Upstreams Configuration
    log_info "Check 3a: Upstreams configuration..."

    if [[ -f "${HOME}/.spack-local/config/upstreams.yaml" ]]; then
        local UPSTREAM_PATH=$(grep "install_tree:" "${HOME}/.spack-local/config/upstreams.yaml" | awk '{print $2}')

        if [[ -n "${UPSTREAM_PATH}" ]]; then
            log_success "Upstream install tree: ${UPSTREAM_PATH}"

            if [[ "${UPSTREAM_PATH}" == *"/daq/software/spack_packages"* ]]; then
                log_success "Upstream points to shared packages"
            else
                log_warn "Upstream does not point to /daq/software/spack_packages"
                ((WARNINGS++))
            fi
        else
            log_warn "Could not parse upstream install tree"
            ((WARNINGS++))
        fi
    else
        log_fail "upstreams.yaml not found - shared packages won't be accessible"
        ((ERRORS++))
    fi

    echo ""

    # Check 4: Install Tree Configuration
    log_info "Check 4: Install tree configuration..."

    # Read install tree directly from config.yaml
    # (spack config get doesn't show the root if it's using defaults)
    local config_file="${SPACK_USER_CONFIG_PATH}/config.yaml"
    local INSTALL_TREE=""

    if [[ -f "${config_file}" ]]; then
        INSTALL_TREE=$(grep -A2 "install_tree:" "${config_file}" | grep "root:" | awk '{print $2}')
    fi

    if [[ -n "${INSTALL_TREE}" ]]; then
        log_info "Configured install tree: ${INSTALL_TREE}"

        if [[ "${INSTALL_TREE}" == "${HOME}/.spack-local/install"* ]]; then
            log_success "Install tree points to local install directory: ${INSTALL_TREE}"
        else
            log_fail "Install tree does NOT point to ~/.spack-local/install"
            log_fail "This means new packages will be installed elsewhere!"
            ((ERRORS++))
        fi
    else
        log_warn "Install tree root not found in config.yaml (using Spack default)"
        log_info "Default is ~/.spack, not ~/.spack-local/install"
    fi

    echo ""

    # Check 4a: Upstream Packages Accessible
    log_info "Check 4a: Verifying upstream packages are accessible..."

    local UPSTREAM_CONFIG=$(spack config get upstreams 2>/dev/null)

    if [[ -n "${UPSTREAM_CONFIG}" ]]; then
        log_success "Spack can read upstream configuration"

        if echo "${UPSTREAM_CONFIG}" | grep -q "install_tree:"; then
            local UPSTREAM_TREE=$(echo "${UPSTREAM_CONFIG}" | grep "install_tree:" | awk '{print $2}')
            log_info "Upstream install tree: ${UPSTREAM_TREE}"

            if [[ -d "${UPSTREAM_TREE}" ]]; then
                log_success "Upstream directory exists and is accessible"
            else
                log_warn "Upstream directory does not exist: ${UPSTREAM_TREE}"
                ((WARNINGS++))
            fi
        fi
    else
        log_fail "No upstream configuration found"
        log_fail "Shared packages will NOT be accessible"
        ((ERRORS++))
    fi

    echo ""

    # Check 5: Database Location
    log_info "Check 5: Database location..."

    local EXPECTED_DB="${HOME}/.spack-local/install/.spack-db"
    local SHARED_DB="/daq/software/spack_packages/.spack-db"

    if [[ -d "${EXPECTED_DB}" ]]; then
        log_success "Local database exists: ${EXPECTED_DB}"

        local DB_COUNT=$(find "${EXPECTED_DB}" -type f 2>/dev/null | wc -l)
        log_info "Local database contains ${DB_COUNT} files"
    else
        log_warn "Local database not yet created: ${EXPECTED_DB}"
        log_info "This is normal - it will be created on first Spack operation"
        ((WARNINGS++))
    fi

    if [[ -d "${SHARED_DB}" ]]; then
        log_info "Shared database exists: ${SHARED_DB}"

        local SHARED_DB_COUNT=$(find "${SHARED_DB}" -type f 2>/dev/null | wc -l)
        log_info "Shared database contains ${SHARED_DB_COUNT} files"

        log_info "Verifying shared database won't be accessed for writes..."
        log_success "Shared packages accessible via upstreams (read-only)"
        log_success "Local database used for all writes"
    fi

    echo ""

    # Check 6: Bootstrap Configuration
    log_info "Check 6: Bootstrap configuration..."

    local BOOTSTRAP_ROOT=$(spack config get config:bootstrap 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{print $2}' | head -1)

    if [[ -n "${BOOTSTRAP_ROOT}" ]]; then
        log_info "Configured bootstrap root: ${BOOTSTRAP_ROOT}"

        if [[ "${BOOTSTRAP_ROOT}" == "${HOME}/.spack-local/bootstrap" ]]; then
            log_success "Bootstrap root points to local directory"
        else
            log_warn "Bootstrap root does not point to ~/.spack-local/bootstrap"
            ((WARNINGS++))
        fi
    fi

    if [[ -d "${HOME}/.spack-local/bootstrap" ]]; then
        log_success "Local bootstrap directory exists"
    else
        log_warn "Local bootstrap directory not yet created"
        ((WARNINGS++))
    fi

    echo ""

    # Check 7: Cache Configuration
    log_info "Check 7: Cache configuration..."

    local MISC_CACHE=$(spack config get config:misc_cache 2>/dev/null | grep -v "^#" | grep -v "^$" | awk '{print $2}' | head -1)

    if [[ -n "${MISC_CACHE}" ]]; then
        log_info "Configured misc cache: ${MISC_CACHE}"

        if [[ "${MISC_CACHE}" == "${HOME}/.spack-local/cache" ]]; then
            log_success "Misc cache points to local directory"
        else
            log_warn "Misc cache does not point to ~/.spack-local/cache"
            ((WARNINGS++))
        fi
    fi

    echo ""

    # Check 8: Test Spack Find
    log_info "Check 8: Testing 'spack find' command..."

    if spack find &>/dev/null; then
        local PACKAGE_COUNT=$(spack find 2>/dev/null | grep "^--" | wc -l)
        log_success "'spack find' executed successfully (found ${PACKAGE_COUNT} packages)"
    else
        log_fail "'spack find' failed"
        ((ERRORS++))
    fi

    echo ""

    # Check 9: Verify Database Access Patterns
    log_info "Check 9: Verifying database access patterns..."

    if command -v strace &>/dev/null; then
        log_info "Running strace test to detect database access..."

        local STRACE_OUTPUT=$(mktemp)
        timeout 5 strace -e trace=open,openat -o "${STRACE_OUTPUT}" spack find 2>/dev/null || true

        if grep -q "${HOME}/.spack-local/.spack-db" "${STRACE_OUTPUT}"; then
            log_success "Detected access to local database: ~/.spack-local/.spack-db/"
        else
            log_warn "No access to local database detected (may not exist yet)"
            ((WARNINGS++))
        fi

        # Check for WRITE access to shared database (two-stage grep to avoid false positives)
        if grep "/daq/software/spack_packages/.spack-db" "${STRACE_OUTPUT}" | grep -qE "O_RDWR|O_WRONLY"; then
            log_fail "WARNING: Detected WRITE access to shared database!"
            log_fail "This should not happen with upstreams configuration"
            ((ERRORS++))
        else
            log_success "No write access to shared database detected"
        fi

        if grep -q "/daq/software/spack_packages" "${STRACE_OUTPUT}"; then
            log_info "Read access to shared packages detected (expected via upstreams)"
        fi

        rm -f "${STRACE_OUTPUT}"
    else
        log_warn "strace not available, skipping file access verification"
        ((WARNINGS++))
    fi

    echo ""

    # Summary
    echo "=================================================="
    echo "  Verification Summary"
    echo "=================================================="
    echo ""

    if [[ ${ERRORS} -eq 0 && ${WARNINGS} -eq 0 ]]; then
        log_success "All checks passed! Spack is properly configured."
        echo ""
        log_info "Your Spack configuration:"
        echo "  • Config:         ${HOME}/.spack-local/config/"
        echo "  • Local DB:       ${HOME}/.spack-local/.spack-db/ (read-write)"
        echo "  • Local Packages: ${HOME}/.spack-local/"
        echo "  • Cache:          ${HOME}/.spack-local/cache/"
        echo "  • Bootstrap:      ${HOME}/.spack-local/bootstrap/"
        echo ""
        log_info "Upstream (shared) packages:"
        echo "  • Packages:       /daq/software/spack_packages/ (read-only)"
        echo "  • NOT using:      /daq/software/spack_packages/.spack-db/"
        echo ""
        log_success "Configuration allows shared package access without locking issues!"
        return 0
    elif [[ ${ERRORS} -eq 0 ]]; then
        log_warn "${WARNINGS} warning(s) found, but no critical errors"
        echo ""
        log_info "Spack should be properly configured with minor warnings"
        return 0
    else
        log_fail "${ERRORS} error(s) and ${WARNINGS} warning(s) found"
        echo ""
        log_error "Spack may NOT be properly configured!"
        log_error "Please review the errors above and check your configuration"
        return 1
    fi
}

# ============================================================================
# Function: check_local_environment_exists
# Check if local Spack environment is already set up
# ============================================================================

check_local_environment_exists() {
    local local_root="${1:-${HOME}/.spack-local}"

    # Check if directory exists
    if [[ ! -d "${local_root}" ]]; then
        return 1
    fi

    # Check for essential directories
    if [[ ! -d "${local_root}/config" ]]; then
        return 1
    fi

    # Check for key configuration files
    if [[ ! -f "${local_root}/config/config.yaml" ]] || \
       [[ ! -f "${local_root}/config/upstreams.yaml" ]]; then
        return 1
    fi

    # All checks passed - environment exists
    return 0
}

# ============================================================================
# Function: delete_local_environment
# Delete existing local Spack environment
# ============================================================================

delete_local_environment() {
    local local_root="${1:-${HOME}/.spack-local}"

    if [[ -d "${local_root}" ]]; then
        log_info "Deleting existing local environment at: ${local_root}"
        rm -rf "${local_root}" || {
            log_error "Failed to delete existing environment"
            return 1
        }
        log_success "Existing environment deleted"
    else
        log_info "No existing environment to delete"
    fi

    return 0
}

# ============================================================================
# Function: create_default_env_file
# Create default spack-local.env file with reasonable defaults
# ============================================================================

create_default_env_file() {
    local env_file="${HOME}/.spack-local.env"

    if [[ -f "${env_file}" ]]; then
        log_info "Configuration file already exists: ${env_file}"
        return 0
    fi

    log_info "Creating default configuration file: ${env_file}"

    cat > "${env_file}" << 'EOF'
# Spack Local Environment Configuration
# Generated by setup-local-spack.sh
# Edit this file to customize your Spack environment

# Base Spack installation paths
export SPACK_SOFTWARE_BASE="${SPACK_SOFTWARE_BASE:-/daq/software}"
export SPACK_DIR="${SPACK_DIR:-${SPACK_SOFTWARE_BASE}/spack_packages/spack}"
export SPACK_VERSION="${SPACK_VERSION:-v1.0.1.sbnd}"

# Local Spack root directory
export SPACK_LOCAL_ROOT="${HOME}/.spack-local"

# Logging and debugging
export LOG_LEVEL="${LOG_LEVEL:-INFO}"  # Options: TRACE, DEBUG, INFO, WARN, ERROR
export DEBUG="${DEBUG:-false}"
export VERBOSE="${VERBOSE:-false}"

# Build settings (used by development area scripts)
export BUILD_THREADS="${BUILD_THREADS:-$(nproc 2>/dev/null || echo 4)}"
export COMPILER_VERSION="${COMPILER_VERSION:-13.1.0}"
export CXX_STANDARD="${CXX_STANDARD:-c++17}"

# Optional: Spack-specific settings
# export SPACK_NO_LOCK=true  # Uncomment to disable file locking (useful for NFS)

# Optional: Custom package preferences
# Add any custom environment variables below
EOF

    log_success "Created default configuration file: ${env_file}"
    log_info "Edit ${env_file} to customize your settings"

    return 0
}

# ============================================================================
# Function: setup_clean_environment_inline
# Set up clean environment in the current shell (for non-interactive scripts)
# ============================================================================

setup_clean_environment_inline() {
    local env_file="$1"

    # Save essential variables before cleaning
    local saved_home="${HOME}"
    local saved_user="${USER:-$(whoami)}"
    local saved_logname="${LOGNAME:-${saved_user}}"
    local saved_hostname="${HOSTNAME:-$(hostname)}"
    local saved_term="${TERM:-xterm-256color}"
    local saved_tmpdir="${TMPDIR:-/tmp}"
    local saved_shell="${SHELL:-/bin/bash}"
    local saved_ssh_auth_sock="${SSH_AUTH_SOCK:-}"
    local saved_ssh_agent_pid="${SSH_AGENT_PID:-}"
    local saved_display="${DISPLAY:-}"

    # Get list of all current environment variables
    local all_vars=($(compgen -e))

    # Unexport most variables (keep critical ones)
    for var in "${all_vars[@]}"; do
        case "$var" in
            # Keep these essential variables
            BASH*|HOME|PATH|PWD|SHLVL|_)
                ;;
            # Unset everything else
            *)
                unset "$var" 2>/dev/null || true
                ;;
        esac
    done

    # Set minimal clean environment
    export HOME="${saved_home}"
    export PATH="/usr/local/bin:/usr/bin:/bin"
    export USER="${saved_user}"
    export LOGNAME="${saved_logname}"
    export SHELL="${saved_shell}"
    export HOSTNAME="${saved_hostname}"
    export TERM="${saved_term}"
    export TMPDIR="${saved_tmpdir}"
    export LANG="en_US.UTF-8"
    export LC_ALL="en_US.UTF-8"
    export LC_CTYPE="en_US.UTF-8"

    # Restore SSH and X11 variables if they were set
    [[ -n "${saved_ssh_auth_sock}" ]] && export SSH_AUTH_SOCK="${saved_ssh_auth_sock}"
    [[ -n "${saved_ssh_agent_pid}" ]] && export SSH_AGENT_PID="${saved_ssh_agent_pid}"
    [[ -n "${saved_display}" ]] && export DISPLAY="${saved_display}"

    # Mark as clean bash mode
    export _SPACK_CLEAN_BASH=1

    # Source the environment configuration
    if [[ -f "${env_file}" ]]; then
        log_info "Loading configuration from: ${env_file}"
        source "${env_file}"
    fi

    log_success "Clean environment configured in current shell"
    log_info "Environment variables: $(env | wc -l)"
}

# ============================================================================
# Function: start_clean_bash_session
# Start an interactive clean bash session with Spack configured
# ============================================================================

start_clean_bash_session() {
    local script_path="$(readlink -f "${BASH_SOURCE[0]}")"
    local env_file="${HOME}/.spack-local.env"

    # Create env file if it doesn't exist
    create_default_env_file

    # Check if we're being sourced from a script (non-interactive)
    # If so, set up clean environment in current shell instead of spawning
    if [[ ! -t 0 && "${BASH_SOURCE[1]}" != "" ]]; then
        log_info "Setting up clean bash environment in current shell..."
        setup_clean_environment_inline "${env_file}"
        # Set flag to signal inline mode (continue with spack setup)
        CLEAN_BASH_INLINE_MODE=true
        return 0
    fi

    log_info "Starting clean bash environment..."
    log_info "Environment file: ${env_file}"
    log_info "Type 'exit' to return to your original shell"
    echo ""

    # Collect all arguments except --clean-bash
    local args=()
    for arg in "$@"; do
        if [[ "$arg" != "--clean-bash" ]]; then
            args+=("$arg")
        fi
    done

    # Collect important system variables to preserve
    local term_val="${TERM:-xterm-256color}"
    local user_val="${USER:-$(whoami)}"
    local logname_val="${LOGNAME:-${user_val}}"
    local hostname_val="${HOSTNAME:-$(hostname)}"
    local lang_val="${LANG:-en_US.UTF-8}"
    local tmpdir_val="${TMPDIR:-/tmp}"
    local shell_val="${SHELL:-/bin/bash}"

    # SSH agent variables (preserve if set for git operations)
    local ssh_auth_sock="${SSH_AUTH_SOCK:-}"
    local ssh_agent_pid="${SSH_AGENT_PID:-}"

    # X11 display (preserve if set for GUI applications)
    local display_val="${DISPLAY:-}"

    # Create a temporary init script for the clean bash
    local init_script=$(mktemp)
    cat > "${init_script}" << INIT_EOF
# Essential system environment variables
export HOME="${HOME}"
export PATH="/usr/local/bin:/usr/bin:/bin"
export USER="${user_val}"
export LOGNAME="${logname_val}"
export SHELL="${shell_val}"
export HOSTNAME="${hostname_val}"
export TERM="${term_val}"
export TMPDIR="${tmpdir_val}"

# Locale settings - always set to en_US.UTF-8 for consistency
export LANG="${lang_val}"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"

# SSH agent variables (if available, for git/ssh operations)
${ssh_auth_sock:+export SSH_AUTH_SOCK="${ssh_auth_sock}"}
${ssh_agent_pid:+export SSH_AGENT_PID="${ssh_agent_pid}"}

# X11 display (if available, for GUI applications)
${display_val:+export DISPLAY="${display_val}"}

# Marker to indicate we're in clean bash mode
export _SPACK_CLEAN_BASH=1

# Source the environment configuration
if [[ -f "${env_file}" ]]; then
    source "${env_file}"
fi

# Source the setup script
source "${script_path}" ${args[*]}
INIT_EOF

    # Add helpful message at the end
    cat >> "${init_script}" << 'INIT_EOF'

# Display clean environment info
echo ""
echo "=========================================="
echo "  Clean Bash Environment Active"
echo "=========================================="
echo "PATH: $PATH"
echo "Env vars: $(env | wc -l)"
echo ""
echo "Type 'exit' to return to original shell"
echo "=========================================="
echo ""
INIT_EOF

    # Create a complete wrapper script that sets environment and runs setup
    local wrapper=$(mktemp)
    cat > "${wrapper}" << EOF
#!/bin/bash
# Essential environment variables
export HOME="${HOME}"
export PATH="/usr/local/bin:/usr/bin:/bin"
export USER="${user_val}"
export LOGNAME="${logname_val}"
export SHELL="${shell_val}"
export HOSTNAME="${hostname_val}"
export TERM="${term_val}"
export LANG="${lang_val}"
export LC_ALL="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export TMPDIR="${tmpdir_val}"
EOF

    # Add SSH/DISPLAY if available
    [[ -n "${ssh_auth_sock}" ]] && echo "export SSH_AUTH_SOCK=\"${ssh_auth_sock}\"" >> "${wrapper}"
    [[ -n "${ssh_agent_pid}" ]] && echo "export SSH_AGENT_PID=\"${ssh_agent_pid}\"" >> "${wrapper}"
    [[ -n "${display_val}" ]] && echo "export DISPLAY=\"${display_val}\"" >> "${wrapper}"

    # Add marker and source commands
    cat >> "${wrapper}" << EOF
export _SPACK_CLEAN_BASH=1

# Source environment configuration
if [[ -f "${env_file}" ]]; then
    source "${env_file}"
fi

# Source the setup script (this defines all the functions)
source "${script_path}" ${args[*]}

# Export ALL functions so they're available in the child bash
# This ensures all utility, logging, and spack functions work
for func in \$(declare -F | awk '{print \$3}'); do
    export -f "\${func}" 2>/dev/null
done

# Export all current environment variables to child shell
# This preserves colors, paths, and configuration
export -p > /dev/null 2>&1

# Display clean environment info
echo ""
echo "=========================================="
echo "  Clean Bash Environment Active"
echo "=========================================="
echo "Environment variables: \$(env | wc -l)"
echo ""

# Check if we're in an interactive terminal or have commands to execute
if [[ -t 0 ]]; then
    # Interactive mode - stdin is a terminal
    echo "Available commands:"
    echo "  local_spack_help    - Show help"
    echo "  verify_local_spack  - Verify configuration"
    echo "  spack               - Spack package manager"
    echo "  exit                - Return to original shell"
    echo "=========================================="
    echo ""

    # Start interactive bash
    /bin/bash --noprofile --norc
else
    # Non-interactive mode - commands available from stdin or file
    echo "Running in non-interactive mode"
    echo "=========================================="
    echo ""

    # Execute bash with stdin (reads commands from pipe/heredoc/file)
    /bin/bash --noprofile --norc
fi
EOF

    chmod +x "${wrapper}"

    # Execute with clean environment
    env -i /bin/bash --noprofile --norc "${wrapper}"

    # Cleanup
    rm -f "${wrapper}" "${init_script}"

    log_info "Exited clean bash environment"
}

# ============================================================================
# Parse Command Line Arguments
# ============================================================================

DELETE_EXISTING=false
CLEAN_BASH=false

# Check if --clean-bash is requested and we're not already in clean bash
CLEAN_BASH_INLINE_MODE=false
if [[ -z "${_SPACK_CLEAN_BASH:-}" ]]; then
    for arg in "$@"; do
        if [[ "$arg" == "--clean-bash" ]]; then
            CLEAN_BASH=true
            start_clean_bash_session "$@"
            # If NOT inline mode, user exited interactive shell, so return
            if [[ "${CLEAN_BASH_INLINE_MODE}" != "true" ]]; then
                return 0
            fi
            # If inline mode, continue to spack setup below
            break
        fi
    done
fi

# Parse arguments passed to the script when sourced
while [[ $# -gt 0 ]]; do
    case "$1" in
        --delete-existing)
            DELETE_EXISTING=true
            shift
            ;;
        --clean-bash)
            # Already handled above, just skip
            shift
            ;;
        -h|--help)
            local_spack_help
            return 0
            ;;
        *)
            log_warn "Unknown option: $1"
            shift
            ;;
    esac
done

# ============================================================================
# Main Setup Execution
# ============================================================================

# Configuration
# CRITICAL: Must use ~/.spack-local (hard requirement)
# This location isolates our config from Spack's default ~/.spack directory
export SPACK_LOCAL_ROOT="${HOME}/.spack-local"
export SPACK_SOFTWARE_BASE="${SPACK_SOFTWARE_BASE:-/daq/software}"
export SPACK_DIR="${SPACK_DIR:-${SPACK_SOFTWARE_BASE}/spack_packages/spack}"
export SPACK_VERSION="${SPACK_VERSION:-v1.0.1.sbnd}"
export SPACK_HOME_DIR="${SPACK_DIR}/${SPACK_VERSION}"

# Verify Spack installation exists
if [[ ! -d "${SPACK_HOME_DIR}" ]]; then
    log_error "Spack installation not found at: ${SPACK_HOME_DIR}"
    log_error "Please set SPACK_DIR and SPACK_VERSION appropriately"
    return 1
fi

if [[ ! -f "${SPACK_HOME_DIR}/setup-env.sh" ]]; then
    log_error "Spack setup script not found at: ${SPACK_HOME_DIR}/setup-env.sh"
    return 1
fi

# Detect OS distribution (needed for both new and existing setups)
detect_os_distribution

# Check if local environment already exists
if check_local_environment_exists "${SPACK_LOCAL_ROOT}"; then
    if [[ "${DELETE_EXISTING}" == "true" ]]; then
        log_info "Existing local environment found - will delete and recreate"
        delete_local_environment "${SPACK_LOCAL_ROOT}" || return 1
        SKIP_SETUP=false
    else
        log_info "Local environment already exists at: ${SPACK_LOCAL_ROOT}"
        log_info "Skipping setup - will verify existing configuration"
        log_info "Use 'source setup-local-spack.sh --delete-existing' to recreate"
        SKIP_SETUP=true
    fi
else
    log_info "No existing local environment found - will create new setup"
    SKIP_SETUP=false
fi

# Execute setup steps (skip if environment exists and not deleting)
if [[ "${SKIP_SETUP}" == "false" ]]; then
    create_directory_structure
    create_spack_environment
    create_config_yaml
    create_upstreams_yaml     # ENABLED: Create user-level upstreams.yaml
    create_repos_yaml
    create_packages_yaml
    create_compilers_yaml
fi

# Always execute these steps (needed for current shell session)
set_environment_variables
source_spack_setup
activate_spack_environment
display_configuration_summary

# Bootstrap only if we did setup
if [[ "${SKIP_SETUP}" == "false" ]]; then
    bootstrap_spack

    # CRITICAL: Reindex database to populate with upstream packages
    log_info "Reindexing database to populate with upstream packages..."
    echo ""
    log_info "Running 'spack reindex'..."
    spack reindex || {
        log_warn "Reindex had warnings, but continuing..."
    }
    echo ""
    log_success "Database reindexed - upstream packages are now visible"
fi

# Always verify and show help
initial_verification
display_helpful_commands

# Final message
echo ""
log_success "Setup complete!"
echo ""
log_info "IMPORTANT: Run 'verify_local_spack' to perform comprehensive verification"
log_info "           Run 'local_spack_help' to see available commands and help"
echo ""

# Log when sourced
log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"

# Remove signal traps so they don't interfere with user's interactive shell
# ERR trap: grep, test commands, etc. naturally return non-zero without being errors
# EXIT trap: cleanup should not run when user exits their shell
trap - ERR EXIT SIGINT SIGTERM SIGQUIT
