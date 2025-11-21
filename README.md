# ICARUS & SBND DAQ Software Environment

<div align="center">

**Spack-Based Package Management and Development Environment**

*Short-Baseline Neutrino Program | Fermi National Accelerator Laboratory*

---
</div>

---

## Overview

This repository provides a comprehensive Spack-based software management ecosystem for the **ICARUS** and **SBND** experiments, part of Fermilab's Short-Baseline Neutrino (SBN) Program. The SBN Program investigates neutrino oscillations and searches for sterile neutrinos using three liquid argon time projection chamber (LArTPC) detectors located along the Booster Neutrino Beam.

### Repository Capabilities

This integrated software environment provides:

- **Unified Package Management** - Spack-based installation and dependency resolution for DAQ software stacks
- **Development Workflows** - Streamlined tools for suite and individual package development
- **Binary Distribution** - Buildcache infrastructure for rapid deployment across experiment computing resources
- **Local & Shared Configurations** - Flexible database management supporting both collaborative and isolated development
- **Quality Assurance** - Modular architecture with comprehensive logging, error handling, and verification tools

## Repository Architecture

### Directory Structure

```
spack/v1.0.1.sbnd/
│
├── NULL/                          # [Submodule] Spack Core
│   ├── bin/spack                  # Spack command-line interface
│   ├── lib/spack/                 # Core Spack libraries
│   ├── var/spack/repos/           # Built-in package recipes
│   └── README.md                  # Spack documentation
│
├── sbndaq-spack-tools/            # ICARUS/SBND Development Tools
│   ├── README.md                  # Comprehensive tools documentation
│   ├── modules/                   # Modular function libraries
│   │   ├── README.md              # Module architecture guide
│   │   ├── logging-functions.sh   # Logging and output utilities
│   │   ├── signal-functions.sh    # Error handling and cleanup
│   │   ├── config-functions.sh    # Configuration file generation
│   │   ├── env-functions.sh       # Environment initialization
│   │   ├── pkg-functions.sh       # Package management
│   │   ├── build-functions.sh     # Build orchestration
│   │   └── suite-functions.sh     # DAQ suite-specific workflows
│   │
│   ├── Main Scripts
│   ├── setup-local-spack.sh       # Local Spack database configuration
│   ├── newSPACKDevArea.sh         # Create DAQ suite development area
│   ├── newSPACKProjArea.sh        # Create single package development area
│   ├── build-sbndaq-suite.sh      # Build sbndaq-suite packages
│   ├── build-artdaq-suite.sh      # Build artdaq-suite packages
│   ├── rsync-build-cache.sh       # Binary cache distribution
│   └── tools-spack-devenv.sh      # Interactive development helpers
│
├── spack-repos/                   # [Submodule] SBN Package Repositories
│   └── sbn-spack/                 # ICARUS/SBND package definitions
│       ├── packages/              # Custom package recipes
│       └── README.md              # Package repository documentation
│
├── fermi-spack-tools/             # [Submodule] Fermilab Spack Tools
│   └── ...                        # Fermilab-specific utilities
│
├── spack-mpd/                     # [Submodule] Multi-Package Development
│   └── ...                        # MPD repository management tools
│
├── .gitmodules                    # Submodule configuration
└── README.md                      # This file
```

### Git Submodules

This repository integrates multiple components via Git submodules:

| Submodule | Repository | Purpose |
|-----------|------------|---------|
| **NULL** | [`SBNSoftware/spack`](https://github.com/SBNSoftware/spack) | SBN-customized Spack core with experiment-specific patches and configurations |
| **spack-repos** | [`SBNSoftware/spack-repos`](https://github.com/SBNSoftware/spack-repos) | ICARUS/SBND package definitions for artdaq, sbndaq, and dependencies |
| **fermi-spack-tools** | [`FNALssi/fermi-spack-tools`](https://github.com/FNALssi/fermi-spack-tools) | Fermilab Scientific Software Infrastructure tools and utilities |
| **spack-mpd** | [`eflumerf/spack-mpd`](https://github.com/eflumerf/spack-mpd) | Multi-package development (MPD) repository management |

**Initialize submodules**:
```bash
git submodule update --init --recursive
```

## Quick Start Guides

### Prerequisites

Before beginning, ensure you have:
- Access to ICARUS or SBND computing resources (GPVMs, build nodes, or interactive nodes)
- Git configured with appropriate credentials
- Bash shell (version 4.0+)
- Basic familiarity with command-line operations

### Use Case 1: Standard User - Local Spack Configuration

**Scenario**: You need to install DAQ software but don't have write access to the shared Spack database.

**Solution**: Configure a personal Spack environment with shared package access:

```bash
# Navigate to the Spack installation
cd /daq/software/spack_packages/spack/v1.0.1.sbnd

# Initialize local Spack database (creates ~/.spack-local/)
source sbndaq-spack-tools/setup-local-spack.sh

# Verify configuration (recommended)
verify_local_spack

# View available ICARUS/SBND packages
spack list sbndaq
spack list artdaq

# Install packages to your local environment
spack install sbndaq-suite@v1_11_00
```

**Benefits**:
- No database locking conflicts with other users
- Access to all shared packages via upstreams
- Personal package installations in `~/.spack-local/install/`
- Isolated configuration in `~/.spack-local/config/`

**Documentation**: [Local Spack Setup Guide](sbndaq-spack-tools/README.md#local-spack-setup-recommended)

---

### Use Case 2: DAQ Developer - Full Suite Development

**Scenario**: You're developing multiple interconnected packages in the ICARUS/SBND DAQ software stack.

**Solution**: Create a comprehensive development area for the entire DAQ suite:

```bash
# Create development environment (example: developer name "ALICE")
./sbndaq-spack-tools/newSPACKDevArea.sh --dev-name ALICE

# Navigate to created environment
cd ~/DAQ_SPACK_DevAreas/DAQ_2025-10-07_ALICE_v1_11_00/DAQInterface

# Activate the Spack environment
source setup_daqinterface_spackenv.sh

# Your development packages are now checked out and ready
# Example: modify source in checked-out packages
cd ../srcs/sbndaq-artdaq
# ... make your changes ...

# Build with your modifications
spack install

**What gets created**:
- Spack environment at `~/DAQ_SPACK_DevAreas/<dev-name>/`
- Development checkouts of artdaq-suite and sbndaq-suite packages
- Configuration files (config.yaml, repos.yaml, upstreams.yaml)
- Activation script (setup.sh)

**Documentation**: [DAQ Suite Development Workflow](sbndaq-spack-tools/README.md#workflow-2-daq-suite-development)

---

### Use Case 3: Release Manager - Build & Distribute Binaries

**Scenario**: You're responsible for building and distributing official software releases.

**Solution**: Use the automated build and distribution scripts:

```bash
# Build sbndaq-suite with all dependencies
./sbndaq-spack-tools/build-sbndaq-suite.sh

# Alternatively, build artdaq-suite
./sbndaq-spack-tools/build-artdaq-suite.sh

# Generate binary cache for distribution
# (buildcache automatically created during build)

# Mirror buildcache to remote repositories
./sbndaq-spack-tools/rsync-build-cache.sh

# Verify buildcache availability
spack buildcache list
```

**Documentation**: [Build & Publish Workflow](sbndaq-spack-tools/README.md#workflow-4-building-and-publishing-packages)

---

## Software Components

### ICARUS/SBND DAQ Software Stack

The DAQ software for ICARUS and SBND is organized into interconnected suites:

#### artdaq Suite
**Purpose**: Core DAQ framework developed by Fermilab Scientific Computing Division

**Key Packages**:
- `artdaq-core` - Core data acquisition framework and data types
- `artdaq` - DAQ application framework and utilities
- `artdaq-utilities` - Common utilities and tools
- `artdaq-core-demo` - Example DAQ applications

**Repository**: Built-in Spack packages + SBN extensions

---

#### sbndaq Suite
**Purpose**: ICARUS and SBND-specific DAQ applications and board readers

**Key Packages**:
- `sbndaq-artdaq` - SBN-specific artdaq extensions
- `sbndaq-artdaq-core` - SBN data types and core components
- `sbndaq` - Top-level integration package

**Repository**: [spack-repos/sbn-spack/](spack-repos/sbn-spack/)

---

### Technical Documentation

| Component | Description | Documentation |
|-----------|-------------|---------------|
| **Spack Core** | SBN-customized Spack package manager | [NULL/README.md](NULL/README.md) · [Official Docs](https://spack.readthedocs.io/) |
| **Development Tools** | ICARUS/SBND workflow automation | [sbndaq-spack-tools/README.md](sbndaq-spack-tools/README.md) |
| **Module System** | Modular function libraries | [sbndaq-spack-tools/modules/README.md](sbndaq-spack-tools/modules/README.md) |
| **Package Repository** | SBN package definitions | [spack-repos/sbn-spack/README.md](spack-repos/sbn-spack/README.md) |
| **Fermi Tools** | Fermilab infrastructure integration | [fermi-spack-tools/](fermi-spack-tools/) |
| **MPD Tools** | Multi-package development utilities | [spack-mpd/](spack-mpd/) |

### External Resources

- **SBN Program**: https://sbn.fnal.gov/
- **ICARUS Experiment**: https://icarus.fnal.gov/
- **SBND Experiment**: https://sbnd.fnal.gov/
- **Fermilab Computing**: https://computing.fnal.gov/
- **artdaq Documentation**: https://cdcvs.fnal.gov/redmine/projects/artdaq/wiki
- **Spack Official Documentation**: https://spack.readthedocs.io/

---

## Key Features

### 1. Isolated Development Environments
Create reproducible, isolated environments for DAQ software development without affecting shared installations or other developers.

### 2. Multi-Version Package Management
Install and maintain multiple versions of the same package simultaneously, essential for supporting both ICARUS and SBND with potentially different software versions.

### 3. Binary Package Distribution (Buildcache)
Accelerate deployments using pre-built binary packages, reducing compilation time from hours to minutes.

### 4. Dependency Resolution
Automatic resolution of complex dependency chains across artdaq, sbndaq, and third-party packages (ROOT, Boost, etc.).

### 5. Platform Compatibility
Supports multiple Linux distributions used across SBN computing infrastructure:
- Scientific Linux 7 (legacy systems)
- AlmaLinux 9 (current standard)

### 6. Upstream Package Sharing
Access shared packages in `/daq/software/spack_packages/` while maintaining personal installations, eliminating redundant builds and conserving disk space.

---

## Environment Variables

### Core Spack Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SPACK_DIR` | Spack installation directory | `/daq/software/spack_packages/spack` |
| `SPACK_VERSION` | Spack version tag | `v1.0.1.sbnd` |
| `SPACK_ROOT` | Spack root (auto-set) | `$SPACK_DIR/$SPACK_VERSION` |
| `SPACK_USER_CONFIG_PATH` | User configuration directory | `~/.spack-local/config` |
| `SPACK_MICRO_ARCH` | Target microarchitecture | `x86_64_v2` |

### Build Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `BUILD_THREADS` | Parallel build jobs | `8` |
| `COMPILER_VERSION` | GCC version | `13.1.0` |
| `CXX_STANDARD` | C++ standard | `c++17` |

### Control Flags

| Variable | Description | Default |
|----------|-------------|---------|
| `NON_INTERACTIVE` | Disable prompts | `false` |
| `VERBOSE` | Enable verbose output | `false` |
| `DEBUG` | Enable debug logging | `false` |

**See**: [Environment Variables Reference](sbndaq-spack-tools/README.md#environment-variables-reference)

---


## Best Practices

1. **Always use local Spack setup** if you lack write access to shared database
2. **Run verification after setup**: `verify_local_spack`
3. **Use non-interactive mode** for automation and CI/CD
4. **Enable debug logging** when troubleshooting
5. **Review configuration files** before running builds
6. **Test in development area** before publishing to buildcache
7. **Document custom configurations** for team members

**See**: [Best Practices Guide](sbndaq-spack-tools/README.md#best-practices)

---

## Getting Help

### Documentation Resources

- **This README** - High-level overview and navigation
- [Spack Core Documentation](NULL/README.md) - Spack package manager
- [SBN Development Tools](sbndaq-spack-tools/README.md) - DAQ development workflows
- [Module System Documentation](sbndaq-spack-tools/modules/README.md) - Modular components
- [Official Spack Documentation](https://spack.readthedocs.io/) - Comprehensive Spack guide

### Interactive Help

```bash
# Spack help
spack help
spack help --all
spack help --spec

# Local Spack setup help
source sbndaq-spack-tools/setup-local-spack.sh
local_spack_help

# Script usage
./sbndaq-spack-tools/newSPACKDevArea.sh --help
./sbndaq-spack-tools/newSPACKProjArea.sh --help
```

---

## Contributing

When contributing to this repository:

1. Follow existing code style and conventions
2. Add appropriate documentation
3. Update README files for new features
4. Test changes thoroughly
5. Include error handling and logging
6. Follow module standards for new modules

**See**: [Module Standards](sbndaq-spack-tools/modules/README.md#module-standards)

---
## About

This repository provides the Spack-based development environment for the Short-Baseline Neutrino (SBN) Data Acquisition system.

**Spack Version**: v1.0.1.sbnd
**Platform**: Linux (Scientific Linux 7, AlmaLinux 9)
**Architecture**: x86_64_v2

For more information about Spack, see the [official Spack repository](https://github.com/spack/spack).
