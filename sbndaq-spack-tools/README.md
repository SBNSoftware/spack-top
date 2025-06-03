# Spack Development Environment Tools

This repository contains scripts for setting up and managing Spack development environments for DAQ software.

## Overview

The codebase provides tools for:

1. Setting up development environments for DAQ suite packages
2. Setting up development environments for individual DAQ projects
3. Building packages and generating buildcaches
4. Managing Spack configurations

## File Organization

The codebase is organized into the following components:

### Main Scripts

- **newSPACKDevArea.sh**: Sets up a development area for the DAQ suite
- **newSPACKProjArea.sh**: Sets up a development area for an individual project
- **build-anydaq-suite.sh**: Builds the DAQ suite packages
- **build-sbndaq-suite.sh**: Builds the SBNDAQ suite packages
- **build-artdaq-suite.sh**: Builds the ARTDAQ suite packages

### Configuration Files

- **newSPACKDevArea.env**: Configuration for the DAQ suite development area
- **newSPACKProjArea.env**: Configuration for the project development area
- **build-sbndaq-suite.env**: Configuration for building SBNDAQ suite
- **build-artdaq-suite.env**: Configuration for building ARTDAQ suite

### Core Libraries

- **common-functions.sh**: General utility functions used by all scripts
- **spack-functions.sh**: Spack-specific utility functions

### Modular Components

The functionality has been organized into modules in the `modules/` directory:

- **modules/config-functions.sh**: Configuration file management functions
- **modules/env-functions.sh**: Environment setup functions
- **modules/pkg-functions.sh**: Package management functions
- **modules/spack-unified.sh**: Unified interface for all modules

## Usage

### Setting up a DAQ Suite Development Area

```bash
./newSPACKDevArea-new.sh --dev-name YOURNAME
```

### Setting up a Project Development Area

```bash
./newSPACKProjArea-new.sh --dev-name YOURNAME
```

### Building Packages

Once inside a development area:

```bash
cd $DAQ_DEV_AREA
source setup.sh
spack install
```

## Configuration

Each script has an associated `.env` file that can be customized to configure:

- Package versions
- Qualifiers
- Compiler versions
- C++ standards
- Build options

See the comments in each `.env` file for details.