# Spack Development Environment Tools

Comprehensive Spack-based development environment management for DAQ software projects.

## Overview

This repository provides a complete toolkit for managing Spack-based development workflows for DAQ (Data Acquisition) software. It includes modular components for environment setup, package building, buildcache management, and local Spack database configuration.

### Key Capabilities

1. **DAQ Development Environments**: Create isolated Spack environments for suite or project development
2. **Local Spack Database**: Configure local database with shared package access (no locking conflicts)
3. **Package Building**: Build and manage DAQ packages with dependency resolution
4. **Buildcache Management**: Generate and publish binary packages
5. **Configuration Management**: Automated Spack configuration file generation
6. **Interactive Tools**: Helper functions for development workflow

## Quick Start

### Local Spack Setup (Recommended)

For users without write access to the shared Spack database:

```bash
# Set up local Spack database with shared package access
source sbndaq-spack-tools/setup-local-spack.sh

# Verify the setup (recommended)
verify_local_spack

# Get help
local_spack_help
```

See [LOCAL-SPACK-SETUP.md](LOCAL-SPACK-SETUP.md) for comprehensive documentation.

### DAQ Suite Development

Create a development area for the entire DAQ suite:

```bash
./sbndaq-spack-tools/newSPACKDevArea.sh --dev-name ALICE
```

### Individual Project Development

Create a development area for a specific package:

```bash
./sbndaq-spack-tools/newSPACKProjArea.sh --dev-name ALICE --pkg-name artdaq-core
```

## Repository Structure

```
sbndaq-spack-tools/
├── README.md                       # This file
├── LOCAL-SPACK-SETUP.md            # Local Spack database documentation
│
├── modules/                        # Modular function libraries
│   ├── README.md                   # Module documentation
│   ├── logging-functions.sh        # Logging utilities
│   ├── signal-functions.sh         # Signal handling and cleanup
│   ├── ossupport-functions.sh      # OS detection and user interaction
│   ├── common-functions.sh         # Core utilities
│   ├── config-functions.sh         # Configuration file management
│   ├── env-functions.sh            # Environment initialization
│   ├── pkg-functions.sh            # Package management
│   ├── build-functions.sh          # Build orchestration
│   ├── buildcache-functions.sh     # Buildcache management
│   ├── suite-functions.sh          # DAQ suite-specific functions
│   ├── spack-unified.sh            # Unified development area setup
│   ├── build-anydaq-suite.sh       # DAQ suite build wrapper
│   └── pull-git-branches.sh        # Git repository management
│
├── Main Scripts
├── newSPACKDevArea.sh              # Create DAQ suite development area
├── newSPACKProjArea.sh             # Create project development area
├── build-sbndaq-suite.sh           # Build sbndaq-suite packages
├── build-artdaq-suite.sh           # Build artdaq-suite packages
├── rsync-build-cache.sh            # Mirror buildcache to remote host
├── os-name.sh                      # OS detection utility
├── tools-spack-devenv.sh           # Interactive development helpers
│
├── Local Spack Setup
├── setup-local-spack.sh            # Local database setup (SOURCE)
│
└── Configuration Files
    ├── newSPACKDevArea.env         # Suite development defaults
    ├── newSPACKProjArea.env        # Project development defaults
    ├── build-sbndaq-suite.env      # SBNDAQ build configuration
    ├── build-artdaq-suite.env      # ARTDAQ build configuration
    └── rsync-build-cache.env       # Rsync configuration
```

## Main Scripts

### Development Environment Setup

#### **newSPACKDevArea.sh**
Create a complete DAQ suite development environment.

**Usage**:
```bash
./newSPACKDevArea.sh --dev-name <name> [options]
```

**Options**:
- `--dev-name <name>` - Developer name (required)
- `--config <file>` - Configuration file (default: newSPACKDevArea.env)
- `--non-interactive` - Run without prompts
- `--verbose` - Enable verbose output

**What it creates**:
- Spack environment with DAQ suite packages
- Configuration files (config.yaml, repos.yaml, etc.)
- Development package checkouts
- Activation script (setup.sh)

**Configuration**: `newSPACKDevArea.env`

---

#### **newSPACKProjArea.sh**
Create a development environment for a specific package.

**Usage**:
```bash
./newSPACKProjArea.sh --dev-name <name> --pkg-name <package> [options]
```

**Options**:
- `--dev-name <name>` - Developer name (required)
- `--pkg-name <package>` - Package name (required)
- `--pkg-version <version>` - Package version
- `--config <file>` - Configuration file (default: newSPACKProjArea.env)
- `--non-interactive` - Run without prompts

**What it creates**:
- Focused Spack environment for single package
- Package source checkout
- Development configuration
- Activation script

**Configuration**: `newSPACKProjArea.env`

---

### Package Building

#### **build-sbndaq-suite.sh**
Build and publish sbndaq-suite packages to buildcache.

**Usage**:
```bash
# Executed
./build-sbndaq-suite.sh [--config <file>]

# Or sourced
source build-sbndaq-suite.sh
run_sbndaq_build <config-file>
```

**Configuration**: `build-sbndaq-suite.env`

**Process**:
1. Load configuration
2. Initialize Spack environment
3. Build sbndaq-suite packages
4. Generate buildcache
5. Update buildcache index
6. Optionally mirror to remote host

---

#### **build-artdaq-suite.sh**
Build and publish artdaq-suite packages to buildcache.

**Usage**:
```bash
./build-artdaq-suite.sh [--config <file>]
```

**Configuration**: `build-artdaq-suite.env`

**Similar process to build-sbndaq-suite.sh**

---

### Utility Scripts

#### **rsync-build-cache.sh**
Mirror directories and files to remote host via SSH using rsync.

**Usage**:
```bash
./rsync-build-cache.sh [--config <file>]
```

**Configuration**: `rsync-build-cache.env`

**Requires**:
- SSH gateway and target host configuration
- List of paths to sync (RSYNC_LIST)
- SSH keys for authentication

**Process**:
1. Test SSH connectivity through gateway
2. Create remote directories
3. Rsync directories and files
4. Verify transfer

---

#### **os-name.sh**
Detect OS name based on kernel version.

**Usage**:
```bash
./os-name.sh
```

**Output**: `scientific7` or `almalinux9`

---

#### **tools-spack-devenv.sh**
Interactive development environment helper functions.

**Usage**:
```bash
# Must be sourced
source tools-spack-devenv.sh <config-file>
```

**Provides functions**:
- `cd-spack-top` - Navigate to project directory
- `spack-env-activate` - Activate Spack environment
- `spack-install` - Install packages with custom options
- `spack-enter-build` - Enter build environment
- `spack-test-run` - Run tests
- `mongo-db-start`, `mongo-db-stop` - MongoDB management
- `delete-databases` - Clean test databases
- `elapsed-time` - Time command execution

**Configuration**: User-provided config file (my-spackenv-*.env)

---

### Local Spack Setup Scripts

#### **setup-local-spack.sh** ⭐
Configure local Spack database with shared package access via upstreams.

**Purpose**: Avoid locking conflicts with shared database while accessing shared packages.

**Usage**:
```bash
# MUST be sourced (not executed)
source sbndaq-spack-tools/setup-local-spack.sh
```

**What it does**:
1. Creates `~/.spack-local/` directory structure (including `/install` and `/config` subdirectories)
2. Creates Spack environment at `~/.spack-local/environments/default/`
3. Generates local configuration files in `~/.spack-local/config/`
4. Configures upstreams for shared packages (in both user config and environment)
5. Sets environment variables (`SPACK_USER_CONFIG_PATH`, `SPACK_USER_CACHE_PATH`, etc.)
6. Sources Spack setup and automatically activates environment
7. Bootstraps Spack dependencies (clingo, gnupg, patchelf)
8. Runs `spack reindex` to populate local database with upstream metadata

**Provides functions**:
- `local_spack_help()` - Display help information
- `verify_local_spack()` - Run comprehensive verification

**Configuration**:
- Local database: `~/.spack-local/install/.spack-db/` (read-write)
- Local install tree: `~/.spack-local/install/`
- Config directory: `~/.spack-local/config/` (isolated)
- Environment: `~/.spack-local/environments/default/`
- Shared packages: `/daq/software/spack_packages/` (read-only via upstreams)
- No locking conflicts
- Binary relocation support via `__spack_path_placeholder__` paths

**See**: [LOCAL-SPACK-SETUP.md](LOCAL-SPACK-SETUP.md)

---

## Configuration Files

Configuration files use environment variables to customize behavior.

### Common Variables

All .env files support:

```bash
# Spack Installation
SPACK_DIR="/daq/software/spack_packages/spack"
SPACK_VERSION="v1.0.1.sbnd"
SPACK_SOFTWARE_BASE="/daq/software"

# Architecture
SPACK_MICRO_ARCH="x86_64_v2"

# Build Settings
BUILD_THREADS=8
COMPILER_VERSION="13.1.0"
CXX_STANDARD="c++17"

# Control Flags
NON_INTERACTIVE=false
VERBOSE=false
DEBUG=false
```

### Suite-Specific Configuration

**build-sbndaq-suite.env** and **build-artdaq-suite.env** include:
- Package versions
- Build qualifiers
- Buildcache mirrors
- Package dependencies

### Rsync Configuration

**rsync-build-cache.env** includes:
- SSH gateway and target hosts
- SSH user
- Paths to sync
- Rsync options

## Module System

The repository uses a modular architecture. See [modules/README.md](modules/README.md) for detailed documentation.

### Module Hierarchy

```
logging-functions.sh (base)
  ├── signal-functions.sh
  └── ossupport-functions.sh
      └── common-functions.sh
          ├── config-functions.sh
          ├── env-functions.sh
          ├── pkg-functions.sh
          ├── buildcache-functions.sh
          └── build-functions.sh
              └── suite-functions.sh
```

### Key Modules

- **logging-functions.sh**: Colored logging with severity levels
- **signal-functions.sh**: Graceful shutdown and error handling
- **common-functions.sh**: Core utilities (argument parsing, qualifiers, paths)
- **config-functions.sh**: Spack configuration file generation
- **env-functions.sh**: Environment initialization
- **pkg-functions.sh**: Package management and Git checkout
- **build-functions.sh**: Build orchestration
- **suite-functions.sh**: DAQ suite-specific builds

## Usage Workflows

### Workflow 1: Local Spack Setup for Regular Users

For users without write access to shared Spack database:

```bash
# 1. Set up local database with shared package access
source sbndaq-spack-tools/setup-local-spack.sh

# 2. Verify setup (highly recommended)
verify_local_spack

# 3. Use Spack normally
spack find                    # List packages (local + shared)
spack install zlib            # Install to local database
spack config get config       # View configuration

# 4. Get help
local_spack_help
```

### Workflow 2: DAQ Suite Development

For developing the complete DAQ suite:

```bash
# 1. Optional: Set up local Spack database first
source sbndaq-spack-tools/setup-local-spack.sh

# 2. Create development area
./sbndaq-spack-tools/newSPACKDevArea.sh --dev-name ALICE

# 3. Activate environment
cd ~/daqarea/ALICE
source setup.sh

# 4. Build packages
spack install
```

### Workflow 3: Individual Package Development

For developing a specific package:

```bash
# 1. Create project area
./sbndaq-spack-tools/newSPACKProjArea.sh \
    --dev-name ALICE \
    --pkg-name artdaq-core \
    --pkg-version v3_12_00

# 2. Activate environment
cd ~/daqarea/ALICE
source setup.sh

# 3. Make changes to source
cd artdaq-core

# 4. Build
spack install
```

### Workflow 4: Building and Publishing Packages

For maintainers publishing builds:

```bash
# 1. Build sbndaq-suite
./sbndaq-spack-tools/build-sbndaq-suite.sh

# 2. Mirror to remote host (if configured)
./sbndaq-spack-tools/rsync-build-cache.sh

# 3. Verify buildcache
spack buildcache list
```

## Advanced Topics

### Custom Configuration

Create custom .env files:

```bash
# Copy default configuration
cp newSPACKDevArea.env my-custom.env

# Edit as needed
vim my-custom.env

# Use custom configuration
./newSPACKDevArea.sh --config my-custom.env
```

### Source vs. Execute

**MUST be sourced** (sets environment variables):
- setup-local-spack.sh
- tools-spack-devenv.sh
- Any script that modifies current shell environment

**MUST be executed** (standalone scripts):
- newSPACKDevArea.sh
- newSPACKProjArea.sh
- build-sbndaq-suite.sh
- build-artdaq-suite.sh
- os-name.sh

**Can be sourced or executed**:
- rsync-build-cache.sh

### Interactive vs. Non-Interactive Mode

All scripts support non-interactive mode:

```bash
./newSPACKDevArea.sh --dev-name ALICE --non-interactive
```

This is useful for:
- CI/CD pipelines
- Batch processing
- Automated deployments

### Logging and Debugging

Enable debug logging:

```bash
# Environment variable
export DEBUG=true
export LOG_LEVEL=DEBUG

# Or in configuration file
DEBUG=true
LOG_LEVEL=DEBUG

# Run script
./newSPACKDevArea.sh --dev-name ALICE
```

Logs are written to:
- `$LOGS_DIR/<script-name>-<timestamp>.log`
- Commands logged to: `$LOGS_DIR/cmds-<timestamp>.log`

### Signal Handling

All scripts handle signals gracefully:
- **SIGINT (Ctrl+C)**: Cleanup and exit
- **SIGTERM**: Graceful shutdown
- **SIGQUIT**: Immediate exit with cleanup
- **ERR**: Error handler with stack trace

Cleanup functions:
- Close file handles
- Remove temporary files
- Reset terminal state
- Log final status

## Troubleshooting

### Common Issues

**Issue**: Spack command not found after sourcing setup-local-spack.sh

**Solution**:
```bash
# Check Spack installation exists
ls -la /daq/software/spack_packages/spack/v1.0.1.sbnd/

# Verify environment variables
echo $SPACK_USER_CONFIG_PATH
echo $SPACK_ROOT

# Try sourcing again with verbose output
VERBOSE=true source setup-local-spack.sh
```

---

**Issue**: Permission denied accessing shared database

**Solution**: Use local Spack setup:
```bash
source sbndaq-spack-tools/setup-local-spack.sh
verify_local_spack
```

---

**Issue**: Package build fails

**Solution**:
```bash
# Check log files
ls -ltr $LOGS_DIR/

# View last log
tail -100 $LOGS_DIR/*.log

# Enable debug mode
DEBUG=true spack install <package>
```

---

**Issue**: Configuration file not found

**Solution**:
```bash
# Check default location
ls -la sbndaq-spack-tools/*.env

# Specify full path
./newSPACKDevArea.sh --config /full/path/to/config.env
```

## Development and Extension

### Adding New Features

1. **Create new module** in `modules/` directory
2. **Follow module standards** (see modules/README.md)
3. **Add source guard** to prevent multiple sourcing
4. **Document functions** with comments
5. **Update dependency hierarchy**
6. **Add to appropriate parent module**
7. **Update this README**

### Testing Changes

```bash
# Test syntax
bash -n script.sh

# Test with debug mode
DEBUG=true ./script.sh

# Test in isolated environment
docker run -it --rm -v $(pwd):/work ubuntu:20.04
```

### Code Style

All scripts follow these conventions:
- Bash strict mode: `set -o errexit -o nounset -o pipefail`
- Source guards with exported variables
- Execution checks for appropriate usage
- Comprehensive error handling
- Signal handlers for cleanup
- Consistent logging with severity levels

## Requirements

### System Requirements

- Bash 4.0 or higher
- Git
- Spack installation (typically at /daq/software/spack_packages/spack)
- Network access for Git operations and package downloads

### Optional Tools

- `strace` - For database access verification
- `rsync` - For buildcache mirroring
- SSH access - For remote buildcache publishing

## Environment Variables Reference

### Spack Variables

- `SPACK_DIR` - Spack installation directory
- `SPACK_VERSION` - Spack version tag
- `SPACK_SOFTWARE_BASE` - Base directory for software
- `SPACK_ROOT` - Spack root (auto-set)
- `SPACK_USER_CONFIG_PATH` - User configuration directory
- `SPACK_USER_CACHE_PATH` - User cache directory
- `SPACK_BOOTSTRAP_ROOT` - Bootstrap directory
- `SPACK_NO_LOCK` - Disable file locking
- `SPACK_MICRO_ARCH` - Target microarchitecture

### Build Variables

- `BUILD_THREADS` - Parallel build jobs
- `COMPILER_VERSION` - GCC version
- `CXX_STANDARD` - C++ standard (c++11, c++17, etc.)

### Control Flags

- `NON_INTERACTIVE` - Disable prompts
- `VERBOSE` - Enable verbose output
- `DEBUG` - Enable debug logging
- `WITH_CLEANUP` - Enable cleanup on exit
- `LOG_LEVEL` - Logging level (TRACE, DEBUG, INFO, WARN, ERROR)

### Path Variables

- `LOGS_DIR` - Log file directory
- `DAQ_DEV_AREA` - Development area path
- `BUILDCACHE_PATH` - Buildcache mirror path

## Support and Documentation

- **Module Documentation**: [modules/README.md](modules/README.md)
- **Local Spack Setup**: [LOCAL-SPACK-SETUP.md](LOCAL-SPACK-SETUP.md)
- **Spack Documentation**: https://spack.readthedocs.io/

## Best Practices

1. **Always use local Spack setup** if you don't have write access to shared database
2. **Run verification** after setup: `verify_local_spack`
3. **Use non-interactive mode** for automation
4. **Enable debug logging** when troubleshooting
5. **Review configuration files** before running builds
6. **Use version control** for custom configurations
7. **Test in development area** before publishing to buildcache
8. **Document custom configurations** for team members

## License

See repository license file.

## Contributing

When contributing:
1. Follow existing code style and conventions
2. Add appropriate documentation
3. Update README files
4. Test changes thoroughly
5. Add source guards and execution checks
6. Include error handling
7. Add logging statements
