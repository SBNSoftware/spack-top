# Spack Development Environment Modules

This directory contains modular components for the Spack development environment scripts used in DAQ software development.

## Overview

The modules provide a clean, maintainable architecture for complex Spack-based workflows. Each module focuses on a specific domain (logging, signals, OS support, configuration, etc.) and can be independently tested and maintained.

## Module Architecture

### Base Modules (No Dependencies)

#### **logging-functions.sh**
Centralized logging with colored output and log level management.

**Purpose**: Provide consistent logging across all scripts with support for multiple output destinations and severity levels.

**Key Functions**:
- `log_trace()`, `log_debug()`, `log_info()`, `log_warn()`, `log_error()` - Severity-based logging
- `log_success()` - Success message logging with visual indicators
- `log_command()` - Log commands with automatic file tracking
- `ensure_log_directory()` - Create and manage log directories
- `cleanup_logs()`, `rotate_logs()` - Log maintenance
- `has_24bit_color_support()` - Terminal capability detection

**Configuration Variables**:
- `LOG_LEVEL` - Minimum log level (TRACE, DEBUG, INFO, WARN, ERROR)
- `LOGS_DIR` - Log file directory
- `CMDS_FILE` - Command log file
- `MAX_LOGS` - Maximum log files to retain

**Color Support**: Auto-detects 24-bit, 256-color, and ANSI color support

**Source Guard**: `_LOGGING_FUNCTIONS_SH_`

---

### Level 1 Modules (Depend on logging-functions.sh)

#### **signal-functions.sh**
Signal handling and cleanup operations.

**Purpose**: Graceful shutdown, error handling, and resource cleanup.

**Key Functions**:
- `setup_signal_handlers()` - Configure traps for INT, TERM, QUIT, ERR
- `handle_sigint()`, `handle_sigterm()`, `handle_sigquit()` - Signal-specific handlers
- `handle_error()` - Error handler with stack traces and exit code reporting
- `cleanup_on_exit()` - Execute registered cleanup functions
- `add_cleanup_function()` - Register custom cleanup callbacks
- `close_open_handles()` - Close file descriptors
- `reset_signal_handlers()` - Restore default signal behavior

**Configuration Variables**:
- `WITH_CLEANUP` - Enable/disable cleanup on exit (true/false)

**Features**:
- Stack trace generation on errors
- Multiple cleanup function registration
- Graceful handling of interrupts
- Resource cleanup (file handles, temp files)

**Source Guard**: `_SIGNAL_FUNCTIONS_SH_`

**Dependencies**: logging-functions.sh

---

#### **ossupport-functions.sh**
OS detection, user interaction, and platform compatibility.

**Purpose**: Abstract platform differences and provide consistent user interaction.

**Key Functions**:

*OS Detection*:
- `get_distro_type()` - Detect distribution (scientific7/almalinux9)
- `get_os_name()` - Get OS name from kernel version
- `get_cpu_count()` - Platform-independent CPU core count

*User Interaction*:
- `ask_for_continue()` - Interactive yes/no prompts
- `read_with_timeout()` - Timed input reading
- `validate_input()` - Input validation with custom validators

*Privileged Execution*:
- `execute_with_sudo()` - Run commands with sudo
- `execute_with_ksu()` - Run commands with ksu (Kerberos)

*Access Control*:
- `is_user_allowed()` - Check if user is in allowed list
- `is_host_allowed()` - Check if host is in allowed list

**Configuration Variables**:
- `NON_INTERACTIVE` - Disable interactive prompts
- `ALLOW_USERS` - Comma-separated list of allowed users
- `ALLOW_HOSTS` - Comma-separated list of allowed hosts

**Source Guard**: `_OSSUPPORT_FUNCTIONS_SH_`

**Dependencies**: logging-functions.sh

---

### Level 2 Modules (Depend on common-functions.sh)

#### **common-functions.sh**
Core utility functions used across all scripts.

**Purpose**: Foundational utilities for argument parsing, qualifier handling, configuration loading, and Spack integration.

**Key Functions**:

*Configuration*:
- `load_build_config()` - Load and validate .env configuration files
- `find_default_config_file()` - Locate configuration files

*Argument Parsing*:
- `parse_arguments()` - Parse command-line arguments with validation
- `print_usage()` - Generate usage information

*Qualifier Management*:
- `format_spack_qualifiers()` - Format qualifiers for Spack commands
- `parse_spack_qualifiers()` - Parse qualifier components
- `get_qualifier_e_version()` - Convert GCC version to e-qualifier
- `get_s_qualifier()` - Extract s-qualifier (compiler standard)
- `get_cxxstd_qualifier()` - Extract C++ standard qualifier

*Path Management*:
- `format_path_name()` - Generate standardized paths with arch/compiler/qualifiers

*Interactive Selection*:
- `get_version()` - Interactive version selection from list

**Configuration Variables**:
- `COMMON_ENVFILE` - Default configuration file name
- Standard flags: `NON_INTERACTIVE`, `VERBOSE`, `DEBUG`

**Source Guard**: `_COMMON_FUNCTIONS_SH_`

**Dependencies**: logging-functions.sh, signal-functions.sh, ossupport-functions.sh

**Execution Check**: Warns if executed instead of sourced

---

#### **config-functions.sh**
Spack configuration file creation and management.

**Purpose**: Generate Spack configuration files (config.yaml, upstreams.yaml, compilers.yaml, etc.) for development environments.

**Key Functions**:
- `create_config_files()` - Create complete set of Spack config files
- `create_upstreams_yaml()` - Create upstreams configuration for shared packages
- `create_config_yaml()` - Create main Spack configuration
- `create_repos_yaml()` - Create repository configuration
- `create_packages_yaml()` - Create package preferences
- `create_compilers_yaml()` - Create compiler configuration
- `create_clang_format()` - Create .clang-format for code formatting
- `create_mpd_repo()` - Create MPD repository structure
- `create_default_config()` - Generate default .env configuration files

**Configuration Files Generated**:
- `config.yaml` - Install tree, cache, build settings
- `upstreams.yaml` - Shared package locations
- `repos.yaml` - Package repositories
- `packages.yaml` - Package preferences and external packages
- `compilers.yaml` - Compiler definitions
- `.clang-format` - Code formatting rules

**Source Guard**: `_CONFIG_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh

---

#### **env-functions.sh**
Spack environment initialization and management.

**Purpose**: Initialize Spack environments, create development environments, and manage Spack database.

**Key Functions**:
- `initialize_spack_environment()` - Initialize Spack with compiler and architecture detection
- `setup_development_environment()` - Create and configure development environment
- `ensure_mirror_directories()` - Validate buildcache mirror directories
- `reindex_spack_database()` - Rebuild Spack database index
- `add_package_to_environment()` - Add package specs to active environment

**Environment Setup**:
- Detects OS distribution and architecture
- Configures compiler (GCC version)
- Sets up Spack directories and paths
- Creates environment with proper configuration

**Configuration Variables**:
- `SPACK_DIR` - Spack installation directory
- `SPACK_VERSION` - Spack version (e.g., v1.0.1.sbnd)
- `SPACK_MICRO_ARCH` - Target microarchitecture
- `BUILD_THREADS` - Number of build threads

**Source Guard**: `_ENV_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh, config-functions.sh

---

#### **pkg-functions.sh**
Package installation, Git checkout, and buildcache management.

**Purpose**: Manage package versions, checkout source code, build packages, and create buildcaches.

**Key Functions**:

*Version Selection*:
- `select_package_version()` - Interactive or automatic version selection

*Development Setup*:
- `setup_development_packages()` - Set up packages for local development
- `checkout_package()` - Git checkout with branch/tag/commit strategies
- `download_package_source()` - Download package source code

*Building*:
- `build_packages()` - Build packages with interactive error recovery

*Buildcache*:
- `generate_package_buildcache()` - Create buildcache for installed package
- `update_buildcache()` - Update buildcache index

**Git Strategies**:
1. Try specified branch first
2. Fall back to tag if branch doesn't exist
3. Fall back to commit hash if tag doesn't exist

**Configuration Variables**:
- `ENABLE_GIT_PUSH` - Enable automatic git push after checkout

**Source Guard**: `_PKG_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh

---

#### **buildcache-functions.sh**
Buildcache generation, management, and publishing.

**Purpose**: Create and manage Spack buildcaches for binary package distribution.

**Key Functions**:
- `generate_package_spec()` - Generate package specification file
- `generate_package_hashes()` - Generate package hashes for buildcache
- `push_to_buildcache()` - Push packages to buildcache mirror
- `update_buildcache_index()` - Update buildcache index.json

**Buildcache Workflow**:
1. Generate spec file for package
2. Generate hashes for all dependencies
3. Push packages to mirror
4. Update index for mirror discovery

**Source Guard**: `_BUILDCACHE_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh

---

### Level 3 Modules (High-Level Orchestration)

#### **build-functions.sh**
High-level build orchestration and package installation.

**Purpose**: Coordinate the complete build process including package installation, dependency resolution, and buildcache generation.

**Key Functions**:
- `install_package()` - Install single package with comprehensive logging
- `build_package_version()` - Build package version with all dependencies
- `run_daq_build()` - Execute complete DAQ build process from configuration

**Build Process**:
1. Load configuration
2. Initialize Spack environment
3. Set up development packages
4. Build packages with dependency resolution
5. Generate buildcache
6. Update buildcache index

**Source Guard**: `_BUILD_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh, config-functions.sh, env-functions.sh, buildcache-functions.sh

---

#### **suite-functions.sh**
DAQ suite-specific build orchestration (artdaq-suite and sbndaq-suite).

**Purpose**: Provide specialized build workflows for DAQ software suites.

**Key Functions**:
- `create_artdaq_default_config()` - Generate default artdaq-suite configuration
- `create_sbndaq_default_config()` - Generate default sbndaq-suite configuration
- `run_artdaq_build()` - Execute artdaq-suite build process
- `run_sbndaq_build()` - Execute sbndaq-suite build process
- `print_usage()` - Suite-specific usage information

**Suite Configurations**:
- Package versions and dependencies
- Compiler settings
- Build qualifiers
- Buildcache mirrors

**Source Guard**: `_SUITE_FUNCTIONS_SH_`

**Dependencies**: common-functions.sh, build-functions.sh

---

#### **spack-unified.sh**
Unified DAQ development area setup for both suite and project types.

**Purpose**: Main entry point for creating DAQ development environments, supporting both full suite development and individual project development.

**Key Functions**:
- `setup_daq_development_area()` - Main setup function (takes "suite" or "proj" parameter)
- `activate_daq_development_area()` - Activate existing environment
- `print_usage()` - Comprehensive usage information

**Setup Process**:
1. Parse arguments and load configuration
2. Initialize Spack environment
3. Create configuration files
4. Set up development packages
5. Create activation script

**Supports Two Modes**:
- **Suite Mode**: Full DAQ suite development (artdaq-suite, sbndaq-suite)
- **Project Mode**: Individual package development

**Source Guard**: `_SPACK_UNIFIED_SH_`

**Dependencies**: common-functions.sh, config-functions.sh, env-functions.sh, pkg-functions.sh

---

### Utility Scripts

#### **build-anydaq-suite.sh**
Common wrapper for DAQ suite builds.

**Purpose**: Source all dependencies needed for DAQ suite builds. Simple wrapper that loads common and suite functions.

**Dependencies**: common-functions.sh, suite-functions.sh

**Usage**: Sourced by build-artdaq-suite.sh and build-sbndaq-suite.sh

---

#### **pull-git-branches.sh**
Git repository update and rebase utility.

**Purpose**: Fetch, pull, and optionally rebase Git repositories.

**Key Functions**:
- `get_current_branch()` - Get current Git branch
- `list_branches()` - List all local and remote branches
- `handle_repo()` - Fetch, pull, and rebase repository

**Usage**: Execute directly (not sourced)

**Interactive**: Prompts for confirmation before operations

---

## Dependency Hierarchy

```
Base Layer:
  logging-functions.sh (no dependencies)

Level 1 (logging only):
  ├── signal-functions.sh
  └── ossupport-functions.sh

Level 2 (common utilities):
  common-functions.sh
    ├── Depends on: logging, signal, ossupport
    └── Used by all higher-level modules

Level 3 (specialized functions):
  ├── config-functions.sh    (common)
  ├── env-functions.sh        (common, config)
  ├── pkg-functions.sh        (common)
  └── buildcache-functions.sh (common)

Level 4 (orchestration):
  ├── build-functions.sh      (common, config, env, buildcache)
  └── suite-functions.sh      (common, build)

Level 5 (entry points):
  ├── spack-unified.sh        (common, config, env, pkg)
  └── build-anydaq-suite.sh   (common, suite)
```

## Using the Modules

### Sourcing Modules

Modules use source guards to prevent multiple sourcing:

```bash
#!/usr/bin/env bash

# Source required modules
SCRIPT_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "${SCRIPT_DIR}/modules/logging-functions.sh"
source "${SCRIPT_DIR}/modules/signal-functions.sh"

# Setup signal handlers
setup_signal_handlers

# Use logging
log_info "Starting script..."
```

### Source Guards

Each module exports a guard variable to prevent multiple sourcing:

```bash
if [[ "${_MODULE_NAME_SH_:-0}" -eq 1 ]]; then
    return 0
fi
export _MODULE_NAME_SH_=1
```

### Execution Checks

Modules that should only be sourced (not executed) include execution checks:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script should be sourced, not executed."
    exit 1
fi
```

## Module Standards

All modules follow these conventions:

1. **Bash Strict Mode**: Use `set -o errexit`, `set -o nounset`, `set -o pipefail`
2. **Source Guards**: Prevent multiple sourcing with exported variables
3. **Execution Checks**: Warn or error if executed instead of sourced
4. **Signal Handlers**: Call `setup_signal_handlers` for graceful shutdown
5. **Debug Logging**: Log when sourced with `log_debug "Sourced $(basename "${BASH_SOURCE[0]}")"`
6. **Documentation**: Header comments with purpose and usage
7. **Function Documentation**: Comment blocks for key functions

## Configuration Files

Associated .env files for main scripts:

- `newSPACKDevArea.env` - DAQ suite development area configuration
- `newSPACKProjArea.env` - Project development area configuration
- `build-artdaq-suite.env` - artdaq-suite build configuration
- `build-sbndaq-suite.env` - sbndaq-suite build configuration
- `rsync-build-cache.env` - Buildcache rsync configuration

## Environment Variables

### Common Variables

- `SPACK_DIR` - Spack installation directory (e.g., /daq/software/spack_packages/spack)
- `SPACK_VERSION` - Spack version (e.g., v1.0.1.sbnd)
- `SPACK_SOFTWARE_BASE` - Base software directory (e.g., /daq/software)
- `SPACK_MICRO_ARCH` - Target microarchitecture (e.g., x86_64_v2)

### Build Variables

- `BUILD_THREADS` - Number of parallel build jobs
- `COMPILER_VERSION` - GCC version (e.g., 13.1.0)
- `CXX_STANDARD` - C++ standard (e.g., c++17)

### Control Flags

- `NON_INTERACTIVE` - Disable interactive prompts
- `VERBOSE` - Enable verbose output
- `DEBUG` - Enable debug logging
- `WITH_CLEANUP` - Enable cleanup on exit

## Testing Modules

To test individual modules:

```bash
# Source the module
source modules/logging-functions.sh

# Test logging
log_info "Test message"
log_success "Success!"
log_error "Error message"

# Test with different log levels
LOG_LEVEL=DEBUG
log_debug "Debug message"
```

## Adding New Modules

When creating new modules:

1. Choose appropriate level in dependency hierarchy
2. Add source guard and execution check
3. Document purpose and key functions
4. Include in spack-unified.sh or appropriate parent module
5. Add to this README with description
6. Follow naming convention: `*-functions.sh`

## Module Size Guidelines

- Keep modules under 600 lines for readability
- Split large modules by functional domain
- Use helper functions to reduce complexity
- Extract common patterns into shared utilities

## See Also

- **Main README**: `../README.md` - Overview of entire tool suite
- **Local Spack Setup**: `../LOCAL-SPACK-SETUP.md` - Local database configuration
- **Main Scripts**: `../newSPACKDevArea.sh`, `../newSPACKProjArea.sh`, etc.
