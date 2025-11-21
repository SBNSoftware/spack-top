# Local Spack Setup - Local Database with Shared Packages

This guide explains how to use Spack with a **local database** while accessing **shared packages**, avoiding locking and permission issues with `/daq/software/spack_packages/.spack-db/`.

## Overview

The `setup-local-spack.sh` script creates a Spack environment with:

- ✅ **Local database** in `~/.spack-local/install/.spack-db/` (read-write, no locking issues)
- ✅ **Shared packages** from `/daq/software/spack_packages/` (read-only via upstreams)
- ✅ All configuration files in `~/.spack-local/config/` (isolated directory)
- ✅ New packages installed to `~/.spack-local/install/`
- ✅ All caches in `~/.spack-local/cache/`
- ✅ Bootstrap materials in `~/.spack-local/bootstrap/`
- ✅ **Environment-based configuration** for upstreams support
- ❌ **No write access** to `/daq/software/spack_packages/.spack-db/`

## Key Benefits

1. **Access shared packages** - Use existing installations from `/daq/software/spack_packages/`
2. **No locking conflicts** - Local database eliminates permission and locking issues
3. **Independent tracking** - Your local database tracks what you use
4. **Install locally** - Add new packages to your local space without affecting shared installation

## Quick Start

```bash
# Source the setup script
source sbndaq-spack-tools/setup-local-spack.sh

# Get help (shows available commands and configuration)
local_spack_help

# Verify the setup (recommended - runs 9 comprehensive checks)
verify_local_spack

# Install a test package
spack install zlib

# Verify database location (will be created on first package install)
find ~/.spack-local/install -name ".spack-db" -type d
```

**Note**: The database path includes `__spack_path_placeholder__` directories due to Spack's binary relocation mechanism. This is normal and expected behavior.

## Detailed Usage

### 1. Initial Setup

Source the setup script to configure your environment:

```bash
source sbndaq-spack-tools/setup-local-spack.sh
```

This script will:
1. Create `~/.spack-local/` directory structure (including `/install` and `/config` subdirectories)
2. Create Spack environment with upstreams configuration at `~/.spack-local/environments/default/`
3. Generate local configuration files in `~/.spack-local/config/`
4. Set environment variables for isolation (`SPACK_USER_CONFIG_PATH`, etc.)
5. Source the shared Spack installation
6. **Automatically activate** the Spack environment
7. Run bootstrap commands:
   - `spack -b find -lpfv` - Initialize bootstrap
   - `spack bootstrap now` - Install clingo, gnupg, patchelf
   - `spack solve zlib` - Test solver
8. **Run `spack reindex`** - Populate local database with upstream package metadata

### 2. Verify Setup

After sourcing setup-local-spack.sh, use the integrated verification function:

```bash
verify_local_spack
```

**Verification performs 9 comprehensive checks**:
1. Spack command availability
2. Environment variables (SPACK_USER_CONFIG_PATH, etc.)
3. Configuration files existence
4. Upstreams configuration (shared package access)
5. Install tree configuration
6. Database location
7. Bootstrap configuration
8. Cache configuration
9. Database access patterns (using strace)

### 3. Use Spack Normally

After setup, use Spack commands as usual:

```bash
# Find packages
spack find

# Install packages
spack install <package>

# Get package info
spack info <package>

# View configuration
spack config get config
```

## Available Functions

After sourcing `setup-local-spack.sh`, these functions become available in your shell:

### **local_spack_help()**
Display comprehensive help information.

```bash
local_spack_help
```

Shows:
- Overview of the local Spack setup
- Available commands
- Configuration paths
- Verification recommendations
- Helpful Spack commands
- Important notes

### **verify_local_spack()**
Run comprehensive verification of your local Spack setup.

```bash
verify_local_spack
```

Performs 9 checks and reports:
- `✓` Success for each passing check
- `✗` Failure for any issues found
- Summary with error/warning count
- Exit code 0 (success) or 1 (errors)

## Directory Structure

After running the setup script, you'll have:

```
~/.spack-local/
├── install/                                          # ⭐ INSTALL TREE ROOT
│   ├── __spack_path_placeholder__/                  # Binary relocation padding
│   │   └── __spack_path_placeholder__/
│   │       └── __spack_path_placeholder__/
│   │           └── __spack_pat/
│   │               ├── .spack-db/                   # ⭐ LOCAL DATABASE (read-write)
│   │               │   ├── index.json               # Package metadata
│   │               │   ├── index_verifier           # Database integrity
│   │               │   ├── prefix_lock              # Lock file
│   │               │   └── prefix_failures          # Failure tracking
│   │               └── <package>-<version>-<hash>/  # Locally-built packages
│   │                   ├── bin/
│   │                   ├── lib/
│   │                   └── ...
│   └── bin/                                         # Symlinks to package binaries
├── config/                                          # ⭐ CONFIG DIRECTORY (REQUIRED)
│   ├── config.yaml              # Main config with install_tree settings
│   ├── upstreams.yaml           # ⭐ CRITICAL - Links to shared packages
│   ├── repos.yaml               # Repository configuration
│   └── linux/
│       └── almalinux9/          # OS-specific configs
│           ├── packages.yaml    # Package preferences
│           └── None/
│               └── compilers.yaml  # Compiler configuration
├── environments/                                    # ⭐ SPACK ENVIRONMENT (REQUIRED)
│   └── default/
│       ├── spack.yaml           # Environment config with upstreams
│       └── spack.lock           # Environment lock file
├── cache/                       # Miscellaneous cache
├── bootstrap/                   # Bootstrap materials
├── stages/                      # Build stages
└── sources/                     # Source tarballs
```

**Important Notes**:
- **`__spack_path_placeholder__` directories**: Created by Spack's binary relocation mechanism (due to `padded_length: 128` setting). This is **normal and expected**.
- **Database location**: `~/.spack-local/install/__spack_path_placeholder__/.../.spack-db/` (within install tree)
- **Config files**: All in `~/.spack-local/config/` subdirectory (required for `SPACK_USER_CONFIG_PATH`)
- **Environment**: Spack environment at `~/.spack-local/environments/default/` (required for upstreams support)

## Key Configuration Files

### config.yaml

Sets the local install tree for new packages and local database:

```yaml
config:
  install_tree:
    root: ~/.spack-local/install  # ⭐ Local packages and .spack-db location (note /install)
    padded_length: 128            # Creates __spack_path_placeholder__ for binary relocation

  build_stage:
    - ~/.spack-local/stages

  source_cache: ~/.spack-local/sources

  misc_cache: ~/.spack-local/cache

  bootstrap: ~/.spack-local/bootstrap

  locks: false  # Disable file locking for NFS compatibility
```

The `install_tree.root` setting determines where:
- **New packages** are installed locally (`~/.spack-local/install/`)
- The **local .spack-db** database is created (within the install tree)
- Spack stores your local installation tracking

**Important**: The `/install` subdirectory is critical to separate package installations from configuration files.

### upstreams.yaml ⭐ CRITICAL FILE

This is the **key file** that enables read-only access to shared packages. It's configured in **both** user-level config and the environment (belt-and-suspenders approach):

**User-level config** (`~/.spack-local/config/upstreams.yaml`):
```yaml
upstreams:
  shared-spack:
    install_tree: /daq/software/spack_packages
```

**Environment config** (`~/.spack-local/environments/default/spack.yaml`):
```yaml
spack:
  specs: []
  view: false

  upstreams:
    shared-spack:
      install_tree: /daq/software/spack_packages

  config:
    install_tree:
      root: ~/.spack-local/install
    locks: false
```

**How it works:**
- Spack **reads** packages from `/daq/software/spack_packages/`
- But maintains **your own database** in `~/.spack-local/install/.spack-db/`
- You can see and use shared packages without write access
- No locking conflicts with `/daq/software/spack_packages/.spack-db/`
- When you run `spack find`, you see packages from **both** upstream and local
- **Environment must be activated** for upstreams to work (done automatically by script)

**Why both locations?**
- User-level config: `SPACK_USER_CONFIG_PATH` pointing to `~/.spack-local/config/`
- Environment config: Required for upstreams support in Spack 1.0.0.dev0
- This ensures upstreams work regardless of configuration scope

### Environment Variables

The script sets these environment variables for complete isolation:

```bash
# Where Spack reads configuration files
export SPACK_USER_CONFIG_PATH="${HOME}/.spack-local/config"

# Where Spack stores cache
export SPACK_USER_CACHE_PATH="${HOME}/.spack-local/cache"

# Where Spack stores bootstrap materials
export SPACK_BOOTSTRAP_ROOT="${HOME}/.spack-local/bootstrap"

# Enable local config
export SPACK_DISABLE_LOCAL_CONFIG=false

# Disable file locks (useful for NFS)
export SPACK_NO_LOCK=true
```

## Bootstrap Process

The script automatically runs these bootstrap commands:

### 1. `spack -b find -lpfv`

Initializes the bootstrap process by:
- Creating bootstrap directory structure
- Finding packages with paths, flags, and variants
- The `-b` flag forces bootstrapping

### 2. `spack bootstrap now`

Installs Spack's internal dependencies:
- `clingo` - Dependency solver
- `gnupg` - GPG for package verification
- `patchelf` - Binary patching utility

### 3. `spack solve zlib`

Tests the solver by:
- Running the dependency solver on a simple package
- Verifying the bootstrap was successful
- Not actually installing anything

### 4. `spack reindex` ⭐ CRITICAL STEP

**Purpose**: Populate the local database with metadata from existing packages in upstream.

**What it does**:
- Scans all packages in the configured install trees (including upstreams)
- Reads package metadata from installed package directories
- Populates local database (`~/.spack-local/install/.spack-db/`) with package information
- Creates local index without writing to shared database
- Enables `spack find` to show both shared and local packages

**Why it's critical**:
- Without reindex, `spack find` won't show upstream packages properly
- Database queries will be incomplete
- Package dependency resolution may fail
- Builds may attempt to reinstall packages that already exist

**When to run**:
- After initial setup (done automatically by script)
- When new packages are installed to shared location (and you want to see them)
- When database appears out of sync

**Important**: `spack reindex` only READS from `/daq/software/spack_packages/` - it never writes to it. All database writes go to `~/.spack-local/install/.spack-db/`.

## Customization

You can customize the setup by setting environment variables before sourcing:

```bash
# Use a different local root directory
export SPACK_LOCAL_ROOT="${HOME}/my-custom-spack"

# Use a different Spack version
export SPACK_VERSION="v1.0.2.sbnd"

# Then source the script
source sbndaq-spack-tools/setup-local-spack.sh
```

## Verifying Isolation

### Method 1: Check Configuration

```bash
# Check local install tree
spack config get config:install_tree:root
# Should output: ~/.spack-local

# Check upstream configuration
spack config get upstreams
# Should show: /daq/software/spack_packages
```

### Method 2: Check Database Location

```bash
# Check local database (note: may be under __spack_path_placeholder__ path)
find ~/.spack-local/install -name ".spack-db" -type d
# Should show: ~/.spack-local/install/__spack_path_placeholder__/.../.spack-db/

# List database contents
ls -la ~/.spack-local/install/__spack_path_placeholder__/__spack_path_placeholder__/__spack_path_placeholder__/__spack_pat/.spack-db/
# Should show: index.json, index_verifier, prefix_lock, prefix_failures

# Verify no write access to shared database
strace -e trace=openat spack find 2>&1 | grep ".spack-db"
# Should only show O_RDONLY (read-only) flags
# Should NOT show O_WRONLY or O_RDWR for shared database
```

### Method 3: Check Package Sources

```bash
# List all packages (from both local and upstream)
spack find

# Show where packages are located
spack find -lp zlib
# Shared packages (upstream) show: [^] marker and path /daq/software/spack_packages/...
# Local packages show: [+] marker and path ~/.spack-local/install/__spack_path_placeholder__/.../
```

### Method 4: Install a Test Package

```bash
# Install a package that doesn't exist in upstream
spack install 'zlib@1.2.12'  # Specific version not in upstream

# Or install with variant not in upstream
spack install 'bzip2+pic'    # +pic variant if upstream has ~pic

# Check installation location
spack find -lp bzip2
# New package should be in ~/.spack-local/install/__spack_path_placeholder__/.../
# Should show [+] marker (local build) not [^] (upstream)
```

### Method 5: Run Verification Function

```bash
verify_local_spack
# Should report "All checks passed!"
# Verifies:
# - Local database location
# - Upstream configuration
# - No write access to shared DB
```

## Troubleshooting

### Issue: Spack trying to write to shared database

**Solution:** Verify upstreams configuration:

```bash
echo $SPACK_USER_CONFIG_PATH
# Should show: ~/.spack-local/config

# Check if upstreams.yaml exists
cat ~/.spack-local/config/upstreams.yaml

# Should contain:
# upstreams:
#   shared-spack:
#     install_tree: /daq/software/spack_packages
```

### Issue: Bootstrap fails

**Solution:** Bootstrap manually:

```bash
spack bootstrap disable github-actions-v0.4
spack bootstrap root ~/.spack-local/bootstrap
spack bootstrap now
```

### Issue: Permission errors

**Solution:** Ensure you own the local directory:

```bash
ls -ld ~/.spack-local
# Should show your username

# Fix if needed
chmod -R u+w ~/.spack-local/
```

### Issue: NFS lock errors

**Solution:** Disable locks:

```bash
export SPACK_NO_LOCK=true
# Or in config.yaml:
#   locks: false
```

## Re-sourcing the Script

You can source the script multiple times safely:

```bash
# In a new terminal
source sbndaq-spack-tools/setup-local-spack.sh
```

The script will:
- Reuse existing configuration files
- Not recreate directories
- Reset environment variables
- Re-run bootstrap (which is idempotent)

## Cleaning Up

To remove the local Spack setup (keeps shared packages intact):

```bash
# This only removes YOUR local database and packages
rm -rf ~/.spack-local/
```

To temporarily disable the local setup:

```bash
unset SPACK_USER_CONFIG_PATH
unset SPACK_USER_CACHE_PATH
unset SPACK_BOOTSTRAP_ROOT

# Note: This reverts to default behavior, which may try to use shared DB
```

## Integration with Existing Scripts

To use this setup with existing DAQ development scripts:

```bash
# First source the local setup
source sbndaq-spack-tools/setup-local-spack.sh

# Then use your DAQ scripts
source sbndaq-spack-tools/newSPACKDevArea.sh --dev-name ALICE
```

**Note:** The local setup takes precedence because `SPACK_USER_CONFIG_PATH` is set.

## Understanding Upstreams Behavior

When using upstreams, `spack find` shows packages from **both** sources:

```bash
$ spack find
==> In environment /home/user/.spack-local/environments/default

==> 150 installed packages  # From /daq/software/spack_packages/ (upstream)
-- linux-almalinux9-x86_64_v2 / gcc@13.1.0 ----------
[^] artdaq@...     # [^] marker indicates upstream package
[^] boost@...
[^] cmake@...
...

==> 5 installed packages    # From ~/.spack-local/install/ (local)
-- linux-almalinux9-x86_64_v2 / gcc@13.1.0 ----------
[+] zlib@1.2.13    # [+] marker indicates locally-built package
...
```

**Key behaviors:**
1. **Upstream packages are read-only** - you can use them but not modify
2. **`[^]` marker** indicates package from upstream, **`[+]` marker** indicates locally-built package
3. **Spack ALWAYS prefers upstream packages** when they match the spec
4. **`--fresh` flag does NOT override upstreams** - this is documented Spack behavior
5. Installing an existing package **locally** requires using a different variant/version than upstream
6. Your local database tracks which upstream packages you've used

**Example - Upstreams Precedence:**
```bash
# If upstream has: bzip2@1.0.8~debug~pic+shared
$ spack install --fresh bzip2
# Result: Reuses from upstream (even with --fresh)

# To force local build, use different variant:
$ spack install 'bzip2+pic'
# Result: Builds locally because +pic doesn't match upstream's ~pic
```

**Binary Relocation (`__spack_path_placeholder__`)**:
Due to `padded_length: 128` in config.yaml, Spack creates paths with padding:
- `~/.spack-local/install/__spack_path_placeholder__/.../bzip2-1.0.8-uptszez/`
- This enables binaries to be relocated after installation
- This is **normal and expected behavior** - not a bug!

## Comparison: Local DB vs. Shared DB

| Aspect | Local DB Setup (`~/.spack-local/`) | Shared DB (`/daq/software/`) |
|--------|-----------------------------------|------------------------------|
| Database Location | `~/.spack-local/install/.spack-db/` (read-write) | `/daq/software/spack_packages/.spack-db/` (read-only for users) |
| Shared Packages | Accessible via upstreams (read-only) | Direct access |
| Config Files | `~/.spack-local/config/` (isolated) | System-wide |
| Install Tree | `~/.spack-local/install/` | `/daq/software/spack_packages/` (requires permissions) |
| New Packages | `~/.spack-local/install/` | `/daq/software/spack_packages/` (requires permissions) |
| Environment | `~/.spack-local/environments/default/` | System environment |
| Locking Issues | None - your own DB | Potential conflicts |
| Permission Issues | None - your own space | May require special permissions |
| Disk Space (local) | Minimal (only new packages) | None |
| Disk Space (shared) | Uses shared packages | All packages shared |
| Package Markers | `[+]` for local, `[^]` for upstream | `[+]` for all packages |

## Advanced Usage

### Using with Spack Environments

```bash
# Create an environment
spack env create myenv
spack env activate myenv

# Install packages
spack add zlib
spack install

# Everything still goes to ~/.spack-local/
```

### Viewing All Configuration

```bash
# View merged configuration from all sources
spack config blame config

# View just the install tree setting
spack config get config:install_tree
```

### Checking Database Content

```bash
# List all installed packages with database info
spack find -lpdf

# Show database statistics
spack find --show-full-compiler
```

## Function-Based Architecture

The `setup-local-spack.sh` script uses a modular function-based architecture for maintainability and extensibility.

### Internal Functions

These functions are called automatically during setup:

**Directory and Configuration**:
- `create_directory_structure()` - Create ~/.spack-local/ structure
- `create_config_yaml()` - Generate config.yaml
- `create_upstreams_yaml()` - Configure upstreams for shared packages
- `create_repos_yaml()` - Generate repos.yaml
- `create_packages_yaml()` - Generate packages.yaml
- `create_compilers_yaml()` - Generate compilers.yaml

**Environment Setup**:
- `set_environment_variables()` - Set SPACK_USER_* variables
- `source_spack_setup()` - Source Spack setup script
- `bootstrap_spack()` - Bootstrap Spack dependencies

**Display and Verification**:
- `display_configuration_summary()` - Show configuration summary
- `display_helpful_commands()` - Show helpful commands
- `initial_verification()` - Quick initial checks

### User-Facing Functions

These functions are available after sourcing:

**Help System**:
- `local_spack_help()` - Display comprehensive help

**Verification**:
- `verify_local_spack()` - Run 9 comprehensive checks

### Architecture Benefits

1. **Modular Design**: Each function has a single responsibility
2. **Testability**: Functions can be tested independently
3. **Maintainability**: Easy to update individual components
4. **Extensibility**: New functions can be added without modifying existing code
5. **Readability**: Clear function names document the setup process
6. **Reusability**: Functions can be called multiple times if needed

### Dependencies

The script uses shared modules from `sbndaq-spack-tools/modules/`:
- **logging-functions.sh**: Provides `log_info()`, `log_success()`, `log_error()`, etc.
- **signal-functions.sh**: Provides `setup_signal_handlers()` for graceful cleanup

This ensures consistent logging and error handling across all DAQ development tools.

## Integration with DAQ Development Tools

The local Spack setup integrates seamlessly with other DAQ development tools:

### Using with newSPACKDevArea.sh

```bash
# 1. Set up local Spack database
source sbndaq-spack-tools/setup-local-spack.sh

# 2. Verify setup
verify_local_spack

# 3. Create DAQ development area
./sbndaq-spack-tools/newSPACKDevArea.sh --dev-name ALICE

# The dev area will use your local database configuration
```

### Using with newSPACKProjArea.sh

```bash
# 1. Set up local Spack database
source sbndaq-spack-tools/setup-local-spack.sh

# 2. Create project area for specific package
./sbndaq-spack-tools/newSPACKProjArea.sh \
    --dev-name ALICE \
    --pkg-name artdaq-core

# The project area inherits local database settings
```

### Priority of Configuration

When using local Spack setup with DAQ development tools:

1. **Local configuration takes precedence** due to `SPACK_USER_CONFIG_PATH`
2. **Upstreams configuration** provides read-only access to shared packages
3. **Development area configs** supplement local configuration
4. **New packages install to** `~/.spack-local/` not shared location

This ensures your local database is always used, preventing locking conflicts.

## References

- **Module Documentation**: [modules/README.md](modules/README.md)
- **Main README**: [README.md](README.md)
- **Spack Configuration Docs**: https://spack.readthedocs.io/en/latest/configuration.html
- **Spack Upstreams**: https://spack.readthedocs.io/en/latest/chain.html
- **Spack Environments**: https://spack.readthedocs.io/en/latest/environments.html
- **Spack Bootstrap**: https://spack.readthedocs.io/en/latest/bootstrapping.html

## Support

If you encounter issues:

1. **Get help**: Run `local_spack_help`
2. **Run verification**: Run `verify_local_spack`
3. **Check configuration**: `spack config get config`
4. **Check upstreams**: `spack config get upstreams`
5. **View debug info**: `spack debug report`
6. **Check environment**: `env | grep SPACK`
7. **View logs**: Check setup script output

### Getting More Information

```bash
# After sourcing setup-local-spack.sh:

# Display help
local_spack_help

# Run verification
verify_local_spack

# Check what Spack sees
spack config blame config        # Show where config values come from
spack find -lpdf                 # List all packages with paths
env | grep SPACK                 # Show Spack environment variables
```
