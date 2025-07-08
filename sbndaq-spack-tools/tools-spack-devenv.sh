#!/bin/bash
# tools-spack-devenv.sh - This script is a collection of functions to aid SDNDAQ development using Spack.

elapsed-time() {
    local start_time
    local end_time
    local elapsed_seconds
    local hours
    local minutes
    local seconds
    
    start_time=$(date +%s)
    echo "Starting $1 at $(date)"
    
    "$@"
    local cmd_status=$?
    
    end_time=$(date +%s)
    elapsed_seconds=$((end_time - start_time))
    
    hours=$((elapsed_seconds / 3600))
    minutes=$(( (elapsed_seconds % 3600) / 60 ))
    seconds=$((elapsed_seconds % 60))
    
    echo "Finished $1 at $(date)"
    echo "Elapsed time: ${hours}h ${minutes}m ${seconds}s"
    
    return $cmd_status
}

print_commands() {
    echo "Available commands:"
    echo "  cd-spack-top             - Change to the top directory of the project"
    echo "  spack-env-activate       - Activate the spack environment"
    echo "  spack-concretize         - Run spack concretize"
    echo "  spack-install            - Install the project"
    echo "  spack-install-log        - Print the install log"
    echo "  spack-uninstall          - Uninstall the project"
    echo "  spack-test-run           - Run tests for the project"
    echo "  spack-test-log           - View the most recent test log file"
    echo "  spack-enter-build        - Enter the build environment"
    echo "  spack-install-and-test   - Install and test the project, delete databases, and run tests"
    echo "  delete-databases         - Delete the databases"
    echo "  mongo-db-start           - Start the database"
    echo "  mongo-db-stop            - Stop the database"
    echo "  mongo-run-command        - Run a command on the database"
    echo "  mongo-run-command-ssl    - Run a command on the database with SSL"
    echo "  elapsed-time             - Run a command and measure its execution time"
    echo ""
}

print_usage() {
    echo "Usage: source $(basename "${BASH_SOURCE[0]}") [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --config=<file>   Specify the configuration file (default: myspack.env)"
    echo "  --verbose         Print all SPACK_USER environment variables"
    echo "  --help, -h, /?    Display this help message"
    echo ""
    echo "This script must be sourced, not executed."
    echo ""
    print_commands
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "Error: This script must be sourced, not executed."
    print_usage
    exit 1
fi

# Default config file
CONFIG_FILE="my-spackenv-ALICE.env"
VERBOSE=false

MONGODB_URI="mongodb://localhost:27017/test_db"

DATABASE_CONFIG_DIR=/tmp/database/config

EXPERIMENT_NAME=$(echo "${MONGODB_URI##*/}" | sed 's/\?.*$//' | sed 's/_db$//' | grep -v '^$')

MONGODB_CLIENT_CERT="${DATABASE_CONFIG_DIR}/${EXPERIMENT_NAME}-mongodb-client-rw-cert.pem"
MONGODB_CA_CERT="${DATABASE_CONFIG_DIR}/${EXPERIMENT_NAME}-mongodb-ca.pem"
 
while [ $# -gt 0 ]; do
    case "$1" in
        --config=*)
            CONFIG_FILE="${1#*=}"
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h|\/?|\/h)
            print_usage
            return 0
            ;;
        *)
            echo "Error: Unknown option: $1"
            print_usage
            return 1
            ;;
    esac
done

check_required_vars() {
    local missing_vars=()
    for var in "$@"; do
        if [ -z "${!var}" ]; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -gt 0 ]; then
        echo "Error: The following required variables are missing or empty:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        return 1
    fi
    return 0
}

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
    if [ "$VERBOSE" = true ]; then
        echo "Sourced config file: $CONFIG_FILE"
    fi
else
    echo "Error: Config file '$CONFIG_FILE' not found"
    return 1
fi

if ! check_required_vars SPACK_DIR SPACK_VERSION DAQ_PKG_NAME DAQ_PKG_VERSIONS DEVNAME SPACK_DAQ_AREAS; then
    echo "Error: Missing required variables in $CONFIG_FILE"
    return 1
fi

export SPACK_HOME_DIR="${SPACK_DIR}/${SPACK_VERSION}"

if [ ! -d "$SPACK_HOME_DIR" ]; then
    echo "Error: Spack directory not found: $SPACK_HOME_DIR"
    return 1
fi

if [ -d "${SPACK_HOME_DIR}/sbndaq-spack-tools" ]; then
    export PATH=${SPACK_HOME_DIR}/sbndaq-spack-tools:${PATH}
fi

if [ ! -f "${SPACK_HOME_DIR}/setup-env.sh" ]; then
    echo "Error: Spack setup file not found: ${SPACK_HOME_DIR}/setup-env.sh"
    return 1
fi

export SPACK_DISABLE_LOCAL_CONFIG=true
source "${SPACK_HOME_DIR}/setup-env.sh"
export SPACK_DISABLE_LOCAL_CONFIG=true
unset SPACK_DISABLE_LOCAL_CONFIG

VERSION=$(echo "$DAQ_PKG_VERSIONS" | cut -d: -f1)
QUALIFIER=$(echo "$DAQ_PKG_VERSIONS" | cut -d: -f2)
COMPILER=$(echo "$DAQ_PKG_VERSIONS" | cut -d: -f3)
SQUALIFIER="s131"
STANDARD=$(echo "$DAQ_PKG_VERSIONS" | cut -d: -f4 | cut -d, -f1)

if [ -z "$VERSION" ] || [ -z "$COMPILER" ] || [ -z "$STANDARD" ]; then
    echo "Error: Failed to extract version, compiler, or standard from DAQ_PKG_VERSIONS"
    echo "DAQ_PKG_VERSIONS=$DAQ_PKG_VERSIONS"
    echo "Expected format: version:qualifier:compiler:standard"
    return 1
fi

OS_VERSION=$(uname -r)
if [[ $OS_VERSION == *"5.14"* ]]; then
    OS_VERSION="almalinux9"
elif [[ $OS_VERSION == *"3.10"* ]]; then
    OS_VERSION="scientific7"
else
    echo "Warning: Unknown OS version: $OS_VERSION"
    echo "Defaulting to almalinux9"
    OS_VERSION="almalinux9"
fi

select_existing_project_dir() {
    local pattern="_${DEVNAME}_${VERSION}"
    local matching_dirs=()
    
    if [ ! -d "${SPACK_DAQ_AREAS}" ]; then
        echo "Warning: Directory ${SPACK_DAQ_AREAS} does not exist."
        echo "Creating directory: ${SPACK_DAQ_AREAS}"
        mkdir -p "${SPACK_DAQ_AREAS}" || {
            echo "Error: Failed to create directory ${SPACK_DAQ_AREAS}"
            return 1
        }
    fi
    
    local tmp_file
    tmp_file=$(mktemp) || {
        echo "Error: Failed to create temporary file"
        return 1
    }
    
    find "${SPACK_DAQ_AREAS}" -maxdepth 1 -type d -name "*${pattern}" > "$tmp_file"
    
    while IFS= read -r dir; do
        if [ -n "$dir" ]; then
            matching_dirs+=("$(basename "$dir")")
        fi
    done < "$tmp_file"
    
    rm -f "$tmp_file"
    
    local count=${#matching_dirs[@]}
    
    if [ $count -eq 0 ]; then
        local current_date
        current_date=$(date +"%Y-%m-%d")
        echo "No existing project directories found. Using current date: $current_date"
        export SPACK_USER_PROJ_PREFIX="DAQ_${current_date}_${DEVNAME}"
        return 0
    fi
    
    if [ $count -eq 1 ]; then
        local dir_name="${matching_dirs[0]}"
        echo "Found one matching project directory: $dir_name"
        if [[ "${DAQ_PKG_NAME}" != *"suite"* ]]; then
            export SPACK_USER_PROJ_PREFIX="${dir_name%_${DAQ_PKG_NAME}_${VERSION}}"
        else
            export SPACK_USER_PROJ_PREFIX="${dir_name%_${VERSION}}"
        fi
        return 0
    fi
    
    echo "Found multiple matching project directories:"
    
    for i in "${!matching_dirs[@]}"; do
        echo "$((i+1))) ${matching_dirs[$i]}"
    done
    
    local selection
    while true; do
        echo -n "Enter selection (1-${count}): "
        read -r selection
        
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$count" ]; then
            local dir_name="${matching_dirs[$((selection-1))]}"
            if [[ "${DAQ_PKG_NAME}" != *"suite"* ]]; then
                export SPACK_USER_PROJ_PREFIX="${dir_name%_${DAQ_PKG_NAME}_${VERSION}}"
            else
                export SPACK_USER_PROJ_PREFIX="${dir_name%_${VERSION}}"
            fi
            return 0
        else
            echo "Invalid selection. Please enter a number between 1 and $count."
        fi
    done
}

if ! select_existing_project_dir; then
    echo "Error: Failed to select or create project directory"
    return 1
fi

export SPACK_USER_PROJ_NAME="${DAQ_PKG_NAME}"
export SPACK_USER_PROJ_VER="${VERSION}"
if [[ "${SPACK_USER_PROJ_NAME}" == *"suite"* ]]; then
    export SPACK_USER_VARIANT="${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}"
else
    export SPACK_USER_VARIANT="${OS_VERSION}-${COMPILER}-${STANDARD}"
fi

if [[ "${SPACK_USER_PROJ_NAME}" != *"suite"* ]]; then
    export SPACK_USER_PROJ_DIR=${SPACK_USER_PROJ_PREFIX}_${SPACK_USER_PROJ_NAME}_${SPACK_USER_PROJ_VER}
else
    export SPACK_USER_PROJ_DIR=${SPACK_USER_PROJ_PREFIX}_${SPACK_USER_PROJ_VER}
fi

echo "Selected Spack Project Directory: $SPACK_USER_PROJ_DIR"

export SPACK_USER_TOP_DIR=${SPACK_DAQ_AREAS}/${SPACK_USER_PROJ_DIR}
export SPACK_USER_CONFIG_PATH=${SPACK_USER_TOP_DIR}/spack

if [ ! -d "$SPACK_USER_TOP_DIR" ]; then
    echo "Creating directory: $SPACK_USER_TOP_DIR"
    mkdir -p "$SPACK_USER_TOP_DIR" || {
        echo "Error: Failed to create directory $SPACK_USER_TOP_DIR"
        return 1
    }
fi

if [ ! -d "$SPACK_USER_CONFIG_PATH" ]; then
    echo "Creating directory: $SPACK_USER_CONFIG_PATH"
    mkdir -p "$SPACK_USER_CONFIG_PATH" || {
        echo "Error: Failed to create directory $SPACK_USER_CONFIG_PATH"
        return 1
    }
fi

if [ "$VERBOSE" = true ]; then
    echo "SPACK_USER environment variables:"
    env | grep ^SPACK_USER | sort
fi

cd-spack-top() {
    if [ -d "${SPACK_USER_TOP_DIR}" ]; then
        cd "${SPACK_USER_TOP_DIR}" || {
            echo "Error: Failed to change directory to ${SPACK_USER_TOP_DIR}"
            return 1
        }
    else
        echo "Error: Directory does not exist: ${SPACK_USER_TOP_DIR}"
        return 1
    fi
}

spack-env-activate() {
    local current_dir
    current_dir=$(pwd)
    
    local env_dir="${SPACK_USER_TOP_DIR}/${SPACK_USER_VARIANT}"
    if [ ! -d "$env_dir" ]; then
        echo "Warning: Environment directory does not exist: $env_dir"
        echo "Creating directory: $env_dir"
        mkdir -p "$env_dir" || {
            echo "Error: Failed to create directory $env_dir"
            return 1
        }
    fi
    
    cd "$env_dir" || {
        echo "Error: Failed to change directory to $env_dir"
        return 1
    }
    
    spack env activate --prompt --dir . || {
        echo "Error: Failed to activate spack environment"
        cd "$current_dir" || true
        return 1
    }
    
    if [ "$1" != "--stay" ]; then
        cd "$current_dir" || {
            echo "Error: Failed to return to original directory: $current_dir"
            return 1
        }
    fi
}

spack-concretize() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    spack concretize "$@"
}

help() {
    print_usage
}

help_commands() {
    print_commands
}

spack-trace-init() {
    source $(which  trace_functions.sh )

    export TRACE_MSGMAX=2048
    export TRACE_NUMENTS=100000
    export TRACE_NAME=TRACE
    rm -f /tmp/trace_buffer_$USER;
    tinfo
    treset
}

spack-trace-show() {
    tshow
}

spack-trace-reset() {
    treset
}

spack-install() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    
    local threads
    if command -v nproc >/dev/null 2>&1; then
        threads=$(nproc)
    else
        threads=4
    fi

    local force_flag=""
    local yes_to_all_flag=""
    local args=()
    
    for arg in "$@"; do
        case "$arg" in
            -f|--force)
                force_flag="--overwrite"
                yes_to_all_flag="--yes-to-all"
                ;;
            -y|--yes-to-all)
                yes_to_all_flag="--yes-to-all"
                ;;
            -l|--log)
                log_file_flag="--log-file ${SPACK_USER_TOP_DIR}/spack-install.log --log-format junit"      
                ;;
            -j|--jobs)
                threads="$arg"
                ;;
            -k|--keep)
                keep_stage_flag="--keep-stage"
                ;;
            -p|--package)
                if [[ "${DAQ_PKG_NAME}" != *"suite"* ]]; then
                    only_package_flag="--only=package"
                else
                    echo "Warning: --package flag ignored for suite packages"
                fi
                ;;
            -t|--test)
                if [[ "${DAQ_PKG_NAME}" != *"suite"* ]]; then   
                    test_flag="--test=root"
                else
                    echo "Warning: --test flag ignored for suite packages"
                fi
                ;;
            *)
                args+=("$arg")
                ;;
        esac
    done

    spack install -j"$threads" $force_flag $yes_to_all_flag $log_file_flag $keep_stage_flag $only_package_flag $test_flag \
    --fresh-roots --use-buildcache=never \
    "${args[@]}" "${SPACK_USER_PROJ_NAME}"
}

spack-install-log() {
    if [ -f "${SPACK_USER_TOP_DIR}/spack-install.log" ]; then
        /usr/bin/cat "${SPACK_USER_TOP_DIR}/spack-install.log"
    else
        echo "Error: Log file does not exist: ${SPACK_USER_TOP_DIR}/spack-install.log"
    fi
}

spack-test-log() {
    local log_pattern="/tmp/artdaq/spack-stage/spack-stage-${SPACK_USER_PROJ_NAME}-${VERSION}-*/spack-build-*/Testing/Temporary/LastTest.log"
    
    local latest_log
    latest_log=$(/usr/bin/ls -t /tmp/artdaq/spack-stage/spack-stage-${SPACK_USER_PROJ_NAME}-${VERSION}-*/spack-build-*/Testing/Temporary/LastTest.log | head -1)
    
    if [ -n "$latest_log" ] && [ -f "$latest_log" ]; then
        echo "Viewing log file: $latest_log"
        less "$latest_log"
    else
        echo "Error: No test log files found matching pattern:"
        echo "$log_pattern"
        return 1
    fi
}

spack-clean() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    spack clean "$@"
}

spack-uninstall() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    spack uninstall --yes-to-all "$@" ${SPACK_USER_PROJ_NAME}
}

spack-exit() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    
    spack env deactivate

    cd "${SPACK_DAQ_AREAS}" || {
        echo "Error: Failed to return to original directory: ${SPACK_DAQ_AREAS}"
        return 1
    }
}

get-spack-stage-dir() {
    unset SPACK_STAGE_BUILD_DIR

    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    
    local latest_compile_commands
    latest_compile_commands=$(/usr/bin/ls -t /tmp/artdaq/spack-stage/spack-stage-${SPACK_USER_PROJ_NAME}-${VERSION}-*/spack-build-*/compile_commands.json | head -1)
    
    if [ -n "$latest_compile_commands" ] && [ -f "$latest_compile_commands" ]; then
        local stage_build_dir
        stage_build_dir=$(dirname "$latest_compile_commands")
        echo "Found build directory: $stage_build_dir"
        export SPACK_STAGE_BUILD_DIR="$stage_build_dir"
    else
        echo "Error: No build directory found"
        return 1
    fi
}

spack-enter-build() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    
    local build_dir_pattern="/tmp/artdaq/spack-stage/spack-stage-${SPACK_USER_PROJ_NAME}-${VERSION}-*/spack-build-*/compile_commands.json"
    local latest_compile_commands

    latest_compile_commands=$(/usr/bin/ls -t /tmp/artdaq/spack-stage/spack-stage-${SPACK_USER_PROJ_NAME}-${VERSION}-*/spack-build-*/compile_commands.json | head -1)
    
    get-spack-stage-dir
    return_code=$?

    if [ $return_code -eq 0 ] && [ -n "$SPACK_STAGE_BUILD_DIR" ]; then
        echo "Entering build environment in $SPACK_STAGE_BUILD_DIR"        
        spack build-env "${SPACK_USER_PROJ_NAME}" -- /bin/bash -c "cd '$SPACK_STAGE_BUILD_DIR' && echo 'Changed to build directory: \$(pwd)' && exec /usr/bin/bash"
    else
        echo "Warning: No compile_commands.json found. Entering build environment without changing directory."
        spack build-env "${SPACK_USER_PROJ_NAME}" -- /usr/bin/bash
    fi
}

spack-test-run() {
    command -v spack >/dev/null 2>&1 || {
        echo "Error: spack command not found"
        return 1
    }
    
    get-spack-stage-dir
    return_code=$?

    if [ $return_code -eq 0 ] && [ -n "$SPACK_STAGE_BUILD_DIR" ]; then
        echo "Found build directory: $SPACK_STAGE_BUILD_DIR"
        
        local args=()
        for arg in "$@"; do
            case "$arg" in
                -v|--verbose)
                    args+=("ARGS='-V'") 
                    ;;
            esac
        done
        
        echo "Running tests in build directory..."
        spack build-env "${SPACK_USER_PROJ_NAME}" -- /bin/bash -c "cd '$SPACK_STAGE_BUILD_DIR' && make -j1 test ${args[@]}"
        
        local test_status=$?
        if [ $test_status -eq 0 ]; then
            echo "Tests completed successfully."
        else
            echo "Tests failed with status $test_status."
        fi
        
        return $test_status
    else
        echo "Error: No build directory found. Please build the package first."
        echo "Running standard spack test run instead..."
        spack test run "${SPACK_USER_PROJ_NAME}" "$@"
    fi
}

mongo-db-start() {
    command -v mongod >/dev/null 2>&1 || {
        echo "Error: mongod command not found"
        return 1
    }

    get-spack-stage-dir
    return_code=$?

    if [ $return_code -eq 0 ] && [ -n "$SPACK_STAGE_BUILD_DIR" ]; then
        echo "Found build directory: $SPACK_STAGE_BUILD_DIR"
    else
        echo "Error: No build directory found"
        return 1
    fi
    
    if [ -n "$MONGODB_URI" ]; then
        mongo_port=27017
        mongo_bind_ip="127.0.0.1"
    else
        mongo_port=$(echo "$MONGODB_URI" | grep -oP ':\K[^/]+')
        mongo_bind_ip=$(echo "$MONGODB_URI" | grep -oP ':\K[^/]+')
    fi

    mongo_wiredTigerCacheSizeGB=0.5
    mongo_data_dir="${SPACK_STAGE_BUILD_DIR}/databases/mongodb"
    mongo_log_file="${SPACK_STAGE_BUILD_DIR}/databases/mongodb.log"
    mongo_pid_file="${SPACK_STAGE_BUILD_DIR}/databases/mongodb.pid"


    mongo_options=" --fork --logpath $mongo_log_file \
        --dbpath $mongo_data_dir --pidfilepath $mongo_pid_file \
        --port $mongo_port --bind_ip $mongo_bind_ip \
        --wiredTigerCacheSizeGB $mongo_wiredTigerCacheSizeGB \
        --tlsMode=disabled --noauth --logappend "

    if [ -d "$mongo_data_dir" ]; then
        echo "Found MongoDB directory: $mongo_data_dir"
        mongod $mongo_options
    else
        echo "Error: No MongoDB directory found"
        return 1
    fi
}

mongo-db-stop() {
    command -v mongod >/dev/null 2>&1 || {
        echo "Error: mongod command not found"
        return 1
    }

    get-spack-stage-dir
    return_code=$?

    if [ $return_code -eq 0 ] && [ -n "$SPACK_STAGE_BUILD_DIR" ]; then
        echo "Found build directory: $SPACK_STAGE_BUILD_DIR"
    else
        echo "Error: No build directory found"
        return 1
    fi

    mongo_pid_file="${SPACK_STAGE_BUILD_DIR}/databases/mongodb.pid"
    if [ -f "$mongo_pid_file" ]; then
        echo "Found MongoDB PID file: $mongo_pid_file"
        kill -15 $(/usr/bin/cat "$mongo_pid_file")
    else
        echo "Error: No MongoDB PID file found"
        killall mongod
        return 1
    fi
}

delete-databases() {
    mongo-db-stop
    get-spack-stage-dir
    return_code=$?

    if [ $return_code -eq 0 ] && [ -n "$SPACK_STAGE_BUILD_DIR" ]; then
        echo "Found build directory: $SPACK_STAGE_BUILD_DIR"
    else
        echo "Error: No build directory found"
        rm -rf "${SPACK_STAGE_BUILD_DIR}/databases"
        return 1
    fi
}

mongo-run-command() {
    command -v mongosh >/dev/null 2>&1 || {
        echo "Error: mongosh command not found"
        return 1
    }
    local command_to_run=${1:-"db.runCommand({listCollections: 1.0, authorizedCollections: true, nameOnly:true})"}
    
    local mongo_options="--quiet"
    if [ ! -f "$command_to_run" ]; then
        mongo_options="$mongo_options --json=relaxed --eval"
    fi
        
    mongosh $MONGODB_URI $mongo_options "$command_to_run"
    
    if [ $? -ne 0 ]; then
        echo "Error: Failed to run command"
        return 1
    fi    
}


mongo-run-command-ssl() {
    command -v mongosh >/dev/null 2>&1 || {
        echo "Error: mongosh command not found"
        return 1
    }
    if [ -n "$MONGODB_URI" ] && [ -n "$MONGODB_CLIENT_CERT" ] && [ -n "$MONGODB_CA_CERT" ]; then
        echo "Running command with SSL"

        local command_to_run=${1:-"db.runCommand({listCollections: 1.0, authorizedCollections: true, nameOnly:true})"}
        
        local mongo_options="--quiet"
        if [ ! -f "$command_to_run" ]; then
            mongo_options="$mongo_options --json=relaxed --eval"
        fi

        mongosh "${MONGODB_URI}&authSource=\$external&authMechanism=MONGODB-X509" --tls \
            --tlsCertificateKeyFile ${MONGODB_CLIENT_CERT} --tlsCAFile ${MONGODB_CA_CERT} \
            $mongo_options "$command_to_run"
    else
        echo "Error: Missing required environment variables, MONGODB_URI, MONGODB_CLIENT_CERT, MONGODB_CA_CERT"
        return 1
    fi
}

spack-install-and-test() {
    delete-databases
    spack-install -k "$@"
    delete-databases
    spack-test-run
}

if [ "$VERBOSE" = true ]; then
    echo ""
    print_commands
fi

echo "Changing to ${SPACK_USER_TOP_DIR}"
cd "${SPACK_USER_TOP_DIR}"
echo "Spack development environment loaded successfully." 
spack -V


spack-load-project() {
    echo "Loading project ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}"
    if [ -f "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.pkgs.txt" ]; then
        echo "Installing packages from ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.pkgs.txt"
        /usr/bin/cat "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.pkgs.txt" |grep -v "\[[\^e]\]"
    else
        echo "The file ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.pkgs.txt does not exist"
    fi

    if [ ! -f "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.build_lock.txt" ]; then
        echo "Building ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}"
        spack-env-activate
        spack-concretize
        elapsed-time spack-install "$@"
        touch "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.build_lock.txt"
    else
        spack-env-activate
        spack-concretize
        echo "Build lock file ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}.build_lock.txt exists, skipping build"
    fi
}

spack-load-suite() {
    echo "Loading suite ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}"
    if [ -f "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.pkgs.txt" ]; then
        echo "Installing packages from ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.pkgs.txt"
        /usr/bin/cat "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.pkgs.txt" |grep -v "\[[\^e]\]"
    else
        echo "The file ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.pkgs.txt does not exist"
    fi

    if [ ! -f "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.build_lock.txt" ]; then
        echo "Building ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}"
        spack-env-activate
        spack-concretize
        elapsed-time spack-install "$@"
        touch "${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.build_lock.txt"
    else
        spack-env-activate
        spack-concretize
        echo "Build lock file ${SPACK_USER_PROJ_NAME}-${VERSION}-${OS_VERSION}-${COMPILER}-${STANDARD}-${SQUALIFIER}.build_lock.txt exists, skipping build"
    fi
}

if [[ "${DAQ_PKG_NAME}" == *"suite"* ]]; then
    spack-load-suite
else
    spack-load-project
fi

alias spack-load-env="source $(basename "${BASH_SOURCE[0]}")"

print_commands
