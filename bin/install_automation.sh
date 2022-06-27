#!/bin/bash

set -e
set +x

# Installs and configures common automation scripts and libraries in
# the environment where it was executed.  Intended to be downloaded
# and executed by root in the target environment.  It is assumed
# the following dependencies are already installed:
#
# bash
# coreutils
# curl
# git
# install

AUTOMATION_REPO_URL=${AUTOMATION_REPO_URL:-https://github.com/containers/automation.git}
AUTOMATION_REPO_BRANCH=${AUTOMATION_REPO_BRANCH:-main}
# This must be hard-coded for executing via pipe to bash
SCRIPT_FILENAME=install_automation.sh
# When non-empty, contains the installation source-files
INSTALLATION_SOURCE="${INSTALLATION_SOURCE:-}"
# The source version requested for installing
AUTOMATION_VERSION="$1"
shift || true  # ignore if no more args
# Set non-zero to enable
A_DEBUG=${A_DEBUG:-0}
# Save some output eyestrain (if script can be found)
OOE=$(realpath $(dirname "${BASH_SOURCE[0]}")/../common/bin/ooe.sh 2>/dev/null || echo "")
# Sentinel value representing whatever version is present in the local repository
MAGIC_LOCAL_VERSION='0.0.0'
# Needed for unit-testing
DEFAULT_INSTALL_PREFIX=/usr/local/share
INSTALL_PREFIX="${INSTALL_PREFIX:-$DEFAULT_INSTALL_PREFIX}"
INSTALL_PREFIX="${INSTALL_PREFIX%%/}"  # Make debugging path problems easier
# When installing as root, allow sourcing env. vars. from this file
INSTALL_ENV_FILEPATH="${INSTALL_ENV_FILEPATH:-/etc/automation_environment}"
# Used internally here and in unit-testing, do not change without a really, really good reason.
_ARGS="$@"
_MAGIC_JUJU=${_MAGIC_JUJU:-XXXXX}
_DEFAULT_MAGIC_JUJU=d41d844b68a14ee7b9e6a6bb88385b4d

msg() { echo -e "${1:-No Message given}"; }

dbg() { if ((A_DEBUG)); then msg "\n# $1"; fi }

# On 5/14/2021 the default branch was renamed to 'main'.
# Since prior versions of the installer reference the old
# default branch, the version-specific installer could fail.
# Work around this with some inline editing of the downloaded
# script, before re-exec()ing it.
fix_branch_ref() {
    local filepath="$1"
    if [[ ! -w "$filepath" ]]; then
        msg "Error updating default branch name in installer script at '$filepath'"
        exit 19
    fi
    sed -i -r -e \
        's/^(AUTOMATION_REPO_BRANCH.+)master/\1main/' \
        "$filepath"
}

# System-wide access to special environment, not used during installer testing.
install_environment() {
    msg "##### Installing automation environment file."
    local inst_perm_arg=""
    if [[ $UID -eq 0 ]]; then
        inst_perm_arg="-o root -g root"
    fi
    install -v $inst_perm_arg -D -t "$INSTALL_PREFIX/automation/" "$INSTALLATION_SOURCE/environment"
    if [[ $UID -eq 0 ]]; then
        # Since INSTALL_PREFIX can vary, this path must be static / hard-coded
        # so callers always know where to find it, when installed globally (as root)
        msg "##### Installing automation env. vars. into $INSTALL_ENV_FILEPATH"
        cat "$INSTALLATION_SOURCE/environment" >> "$INSTALL_ENV_FILEPATH"
    fi
}

install_automation() {
    local actual_inst_path="$INSTALL_PREFIX/automation"
    msg "\n##### Installing the 'common' component into '$actual_inst_path'"

    if [[ ! -x "$INSTALLATION_SOURCE/bin/$SCRIPT_FILENAME" ]]; then
        msg "Bug: install_automation() called with invalid \$INSTALLATION_SOURCE '$INSTALLATION_SOURCE'"
        exit 17
    fi

    # Assume temporary source dir is valid, clean it up on exit
    trap "rm -rf $INSTALLATION_SOURCE" EXIT

    if [[ "$actual_inst_path" == "/automation" ]]; then
        msg "Bug: install_automation() refusing install into the root of a filesystem"
        exit 18
    fi

    if [[ "$AUTOMATION_VERSION" == "$MAGIC_LOCAL_VERSION" ]] || [[ "$AUTOMATION_VERSION" == "latest" ]]; then
        msg "BUG: Actual installer requires actual version number, not '$AUTOMATION_VERSION'"
        exit 16
    fi

    local inst_perm_arg="-o root -g root"
    local am_root=0
    if [[ $UID -eq 0 ]]; then
        dbg "Will try to install and configure system-wide"
        am_root=1
    else
       msg "Warning: Not installing as root, this is not recommended other than for testing purposes"
       inst_perm_arg=""
    fi
    # Allow re-installing different versions, clean out old version if found
    if [[ -d "$actual_inst_path" ]] && [[ -r "$actual_inst_path/AUTOMATION_VERSION" ]]; then
        local installed_version=$(cat "$actual_inst_path/AUTOMATION_VERSION")
        msg "Warning: Removing existing installed version '$installed_version'"
        rm -rvf "$actual_inst_path"
    elif [[ -d "$actual_inst_path" ]]; then
        msg "Error: Unable to deal with unknown contents of '$actual_inst_path',"
        msg "       the file AUTOMATION_VERSION not found, manual removal required."
        exit 12
    fi

    cd "$INSTALLATION_SOURCE/common"
    install -v $inst_perm_arg -D -t "$actual_inst_path/bin" $INSTALLATION_SOURCE/common/bin/*
    install -v $inst_perm_arg -D -t "$actual_inst_path/lib" $INSTALLATION_SOURCE/common/lib/*
    install -v $inst_perm_arg -D -t "$actual_inst_path/bin" $INSTALLATION_SOURCE/bin/$SCRIPT_FILENAME

    dbg "Configuring environment file $INSTALLATION_SOURCE/environment"
    cat <<EOF>"$INSTALLATION_SOURCE/environment"
# Added on $(date --iso-8601=minutes) by $actual_inst_path/bin/$SCRIPT_FILENAME"
# Any manual modifications will be lost upon upgrade or reinstall.
export AUTOMATION_LIB_PATH="$actual_inst_path/lib"
export PATH="$PATH:$actual_inst_path/bin"
EOF
}

exec_installer() {
    # Actual version string may differ from $AUTOMATION_VERSION argument
    local version_arg
    # Prior versions spelled it '$TEMPDIR'
    INSTALLATION_SOURCE="${INSTALLATION_SOURCE:-$TEMPDIR}"
    if [[ -z "$INSTALLATION_SOURCE" ]] || \
       [[ ! -d "$INSTALLATION_SOURCE" ]]; then

        msg "Error: exec_installer() expected $INSTALLATION_SOURCE to exist"
        exit 13
    fi

    msg "Preparing to execute automation installer for requested version '$AUTOMATION_VERSION'"

    # Special-case, use existing source repository
    if [[ "$AUTOMATION_VERSION" == "$MAGIC_LOCAL_VERSION" ]]; then
        dbg "Will try to use installer from local repository $PWD"
        cd $(realpath "$(dirname ${BASH_SOURCE[0]})/../")
        # Make sure it really is a git repository
        if [[ ! -r "./.git/config" ]]; then
            msg "Error: Must execute $SCRIPT_FILENAME from repository clone when specifying version 0.0.0."
            exit 6
        fi
        # Allow installer to clean-up  as with updated source
        dbg "Copying repository into '$INSTALLATION_SOURCE'"
        cp --archive ./* ./.??* "$INSTALLATION_SOURCE/."
    else  # Retrieve the requested version (tag) of the source code
        version_arg="v$AUTOMATION_VERSION"
        if [[ "$AUTOMATION_VERSION" == "latest" ]]; then
            version_arg=$AUTOMATION_REPO_BRANCH
        fi
        msg "Attempting to clone branch/tag '$version_arg'"
        dbg "Cloning from $AUTOMATION_REPO_URL into $INSTALLATION_SOURCE"
        git clone --quiet --branch "$version_arg" \
            --config advice.detachedHead=false \
            "$AUTOMATION_REPO_URL" "$INSTALLATION_SOURCE"
    fi

    dbg "Now working from '$INSTALLATION_SOURCE'"
    cd "$INSTALLATION_SOURCE"
    if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
        msg "Retrieving complete remote details to unshallow temp. copy of local clone"
        $OOE git fetch --unshallow --tags --force
    elif ! git describe HEAD &> /dev/null; then
        msg "Retrieving complete remote version information for temp. copy of local clone"
        $OOE git fetch --tags --force
    else
        msg "Using local version information in temp. copy of local clone"
    fi
    version_arg=$(git describe HEAD)

    # Full path is required so script can find and install itself
    DOWNLOADED_INSTALLER="$INSTALLATION_SOURCE/bin/$SCRIPT_FILENAME"
    if [[ -x "$DOWNLOADED_INSTALLER" ]]; then
        fix_branch_ref "$DOWNLOADED_INSTALLER"
        msg "Executing installer version '$version_arg'\n"
        dbg "Using \$INSTALL_PREFIX '$INSTALL_PREFIX'; installer '$DOWNLOADED_INSTALLER'"
        # Execution likely trouble-free, cancel removal on exit
        trap EXIT
        # _MAGIC_JUJU set to signal actual installation work should commence
        set -x
        exec env \
            A_DEBUG="$A_DEBUG" \
            INSTALLATION_SOURCE="$INSTALLATION_SOURCE" \
            INSTALL_PREFIX="$INSTALL_PREFIX" \
            AUTOMATION_REPO_URL="$AUTOMATION_REPO_URL" \
            AUTOMATION_REPO_BRANCH="$AUTOMATION_REPO_BRANCH" \
            _MAGIC_JUJU="$_DEFAULT_MAGIC_JUJU" \
            /bin/bash "$DOWNLOADED_INSTALLER" "$version_arg" $_ARGS
    else
        msg "Error: '$DOWNLOADED_INSTALLER' does not exist or is not executable"
        # Allow exi
        exit 8
    fi
}

check_args() {
    local arg_rx="^($AUTOMATION_REPO_BRANCH)|^(latest)|^(v?[0-9]+\.[0-9]+\.[0-9]+(-.+)?)"
    dbg "Debugging enabled; Command-line was '$0${AUTOMATION_VERSION:+ $AUTOMATION_VERSION}${_ARGS:+ $_ARGS}'"
    dbg "Argument validation regular-expression '$arg_rx'"
    if [[ -z "$AUTOMATION_VERSION" ]]; then
        msg "Error: Must specify the version number to install, as the first argument."
        msg "       Use version '$MAGIC_LOCAL_VERSION' to install from local source."
        msg "       Use version 'latest' to install from current upstream"
        exit 2
    elif ! echo "$AUTOMATION_VERSION" | egrep -q "$arg_rx"; then
            msg "Error: '$AUTOMATION_VERSION' does not appear to be a valid version number"
            exit 4
    elif [[ -z "$_ARGS" ]] && [[ "$_MAGIC_JUJU" == "XXXXX" ]]; then
        msg "Warning: Installing 'common' component only.  Additional component(s) may be"
        msg "         specified as arguments.  Valid components depend on the version."
    fi
}

##### MAIN #####

check_args

if [[ "$_MAGIC_JUJU" == "XXXXX" ]]; then
    dbg "Operating in source prep. mode"
    INSTALLATION_SOURCE=$(mktemp -p '' -d "tmp_${SCRIPT_FILENAME}_XXXXXXXX")
    dbg "Using temporary directory '$INSTALLATION_SOURCE'"
    # version may be invalid or clone could fail or some other error
    trap "rm -rf $INSTALLATION_SOURCE" EXIT
    exec_installer # Try to obtain version from source then run it
elif [[ "$_MAGIC_JUJU" == "$_DEFAULT_MAGIC_JUJU" ]]; then
    dbg "Operating in actual install mode for '$AUTOMATION_VERSION'"
    dbg "from \$INSTALLATION_SOURCE '$INSTALLATION_SOURCE'"
    install_automation

    # Validate the common library can load
    source "$INSTALL_PREFIX/automation/lib/anchors.sh"

    # Allow subcomponent installers to modify environment file before it's installed"
    msg "##### Installation complete for 'common' component"

    # Additional arguments specify subdirectories to check and chain to their installer script
    for arg in $_ARGS; do
        msg "\n##### Installing the '$arg' component"
        CHAIN_TO="$INSTALLATION_SOURCE/$arg/.install.sh"
        if [[ -r "$CHAIN_TO" ]]; then
            # Cannot assume common was installed system-wide
            env AUTOMATION_LIB_PATH=$AUTOMATION_LIB_PATH \
                AUTOMATION_VERSION=$AUTOMATION_VERSION \
                INSTALLATION_SOURCE=$INSTALLATION_SOURCE \
                A_DEBUG=$A_DEBUG \
                MAGIC_JUJU=$_MAGIC_JUJU \
                $CHAIN_TO
            msg "##### Installation complete for '$arg' subcomponent"
        else
            msg "Warning: Cannot find installer for $CHAIN_TO"
        fi
    done

    install_environment

    # Signify finalization of installation process
    (
        echo -n "##### Finalizing successful installation of version "
        echo -n "$AUTOMATION_VERSION" | tee "$AUTOMATION_LIB_PATH/../AUTOMATION_VERSION"
        echo " of 'common'${_ARGS:+,  and subcomponents: $_ARGS}"
    )
else # Something has gone horribly wrong
    msg "Error: The installer script is incompatible with version $AUTOMATION_VERSION"
    msg "Please obtain and use a newer version of $SCRIPT_FILENAME which supports ID $_MAGIC_JUJU"
    exit 10
fi

dbg "Clean exit."
