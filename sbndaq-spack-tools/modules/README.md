# Spack Development Environment Modules

This directory contains modular components for the Spack development environment scripts.

## Module Organization

The code is organized into the following modules:

- **common-functions.sh**: Core utility functions used across other modules
- **config-functions.sh**: Functions for creating and managing configuration files
- **env-functions.sh**: Functions for setting up the Spack environment
- **pkg-functions.sh**: Functions for package management (checkout, build, etc.)
- **build-functions.sh**: Functions for building packages and managing build processes
- **buildcache-functions.sh**: Functions for managing Spack buildcaches
- **suite-functions.sh**: Functions for DAQ suite-specific operations
- **spack-unified.sh**: Main entry point that combines all modules
- **logging-functions.sh**: Functions for logging and output formatting
- **signal-functions.sh**: Functions for handling signals and cleanup operations
- **ossupport-functions.sh**: Functions for OS detection, user interaction, and platform compatibility
- **build-anydaq-suite.sh**: Common functions for building DAQ packages across different suites

## Purpose and Benefits

This modular approach provides several benefits:

1. **Reduced Duplication**: Common functionality is shared between scripts
2. **Easier Maintenance**: Changes to shared functionality only need to be made in one place
3. **Better Organization**: Code is organized by purpose rather than by script
4. **Smaller File Sizes**: Each module is kept under 600 lines for better readability
5. **Improved Testability**: Modules can be tested independently

## Using the Modules

The modules are designed to be sourced by scripts that need their functionality:

```bash
source "${SCRIPT_DIR}/modules/spack-unified.sh"
```

The `spack-unified.sh` module sources all other required modules, so it's generally the only one you need to include directly.

## Main Scripts

The repository contains several main scripts that use these modules:

- **newSPACKDevArea.sh**: Sets up a Spack development area for DAQ suite development
- **newSPACKProjArea.sh**: Sets up a Spack development area for specific DAQ project development
- **build-sbndaq-suite.sh**: Manages the build process for sbndaq-suite packages
- **build-artdaq-suite.sh**: Manages the build process for artdaq-suite packages

## Main Functions

### Common Utilities
- `format_path_name`: Formats paths with architecture, compiler, and qualifier information
- `format_spack_qualifiers`: Formats qualifiers for Spack commands
- `parse_spack_qualifiers`: Parses qualifier strings into components
- `get_qualifier_e_version`: Converts GCC versions to e-version qualifiers
- `load_build_config`: Loads configuration from a file with validation

### Logging Functions
- `log_debug`, `log_info`, `log_warn`, `log_error`: Log messages at different severity levels
- `log_success`: Log success messages
- `log_command`: Log and record commands being executed
- `ensure_log_directory`, `cleanup_logs`, `rotate_logs`: Manage log files

### Signal Handling
- `setup_signal_handlers`: Configures signal handlers for graceful script termination
- `handle_error`: Comprehensive error handling with stack traces and reporting
- `add_cleanup_function`: Register custom functions to be executed during cleanup
- `cleanup_on_exit`: Executes all registered cleanup functions

### OS Support Functions
- `get_os_name`, `get_distro_type`: Detect operating system and distribution
- `get_cpu_count`: Determine available CPU cores in a platform-independent way
- `ask_for_continue`, `read_with_timeout`, `validate_input`: User interaction functions
- `execute_with_sudo`: Execute commands with elevated privileges when necessary
- `is_user_allowed`, `is_host_allowed`: Security validation functions

### Environment Setup
- `initialize_spack_environment`: Initializes the Spack environment
- `setup_development_environment`: Sets up a development environment
- `setup_daq_development_area`: Sets up a DAQ development area for either 'suite' or 'proj' types

### Package Management
- `setup_development_packages`: Sets up packages for development
- `build_packages`: Builds packages in a development environment

### Build Functions
- `install_package`: Installs a package with specified parameters
- `build_package_version`: Builds a package version with all dependencies
- `run_daq_build`: Runs the DAQ build process with configuration

### Buildcache Functions
- `generate_package_spec`: Generates package specification files
- `generate_package_hashes`: Generates package hashes for buildcache
- `push_to_buildcache`: Pushes packages to buildcache
- `update_buildcache_index`: Updates the buildcache index

### Suite Functions
- `run_artdaq_build`: Runs the artdaq-suite build process
- `run_sbndaq_build`: Runs the sbndaq-suite build process
- `create_artdaq_default_config`: Creates default configuration for artdaq-suite
- `create_sbndaq_default_config`: Creates default configuration for sbndaq-suite

See each module's documentation for more detailed information about the available functions. 