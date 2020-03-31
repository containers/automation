#!/bin/bash

set -e
set +x

# Installs and configures common automation scripts and libraries in
# the environment where it was executed.  Intended to be downloaded
# and executed by root in the target environment.  It is assumed
# the following dependencies are already installed:
#
# bash
# core-utils
# curl
# git
# install

AUTOMATION_REPO_URL=${AUTOMATION_REPO_URL:-https://github.com/containers/automation.git}
AUTOMATION_REPO_BRANCH=${AUTOMATION_REPO_BRANCH:-master}
# This must be hard-coded for executing via pipe to bash
SCRIPT_FILENAME=install_automation.sh
# The source version requested for installing
AUTOMATION_VERSION="$1"
shift || true  # ignore if no more args
# Set non-zero to enable
DEBUG=${DEBUG:-0}
# Save some output eyestrain (if script can be found)
OOE=$(realpath $(dirname "${BASH_SOURCE[0]}")/../common/bin/ooe.sh 2>/dev/null || echo "")
# Sentinel value representing whatever version is present in the local repository
MAGIC_LOCAL_VERSION='0.0.0'
# Needed for unit-testing
DEFAULT_INSTALL_PREFIX=/usr/local/share
INSTALL_PREFIX="${INSTALL_PREFIX:-$DEFAULT_INSTALL_PREFIX}"
# Used internally here and in unit-testing, do not change without a really, really good reason.
_ARGS="$@"
_MAGIC_JUJU=${_MAGIC_JUJU:-XXXXX}
_DEFAULT_MAGIC_JUJU=d41d844b68a14ee7b9e6a6bb88385b4d

msg() { echo -e "${1:-No Message given}" > /dev/stderr; }

dbg() { if ((DEBUG)); then msg "\n# $1"; fi }

# Represents specific installer behavior, should that ever need to change
d41d844b68a14ee7b9e6a6bb88385b4d() {
    TEMPDIR=$(realpath "$(dirname $0)/../")
    trap "rm -rf $TEMPDIR" EXIT
    dbg "Will clean up \$TEMPDIR upon script exit"

    if [[ "$AUTOMATION_VERSION" == "$MAGIC_LOCAL_VERSION" ]] || [[ "$AUTOMATION_VERSION" == "latest" ]]; then
        msg "BUG: Actual installer requires actual version number, not '$AUTOMATION_VERSION'"
        exit 16
    fi

    local actual_inst_path="$INSTALL_PREFIX/automation"
    # Name Hack: if/when installed globally, should work for both Fedora and Debian-based
    spp="etc/profile.d/zz_automation.sh"
    local sys_profile_path="${actual_inst_path}/$spp"
    local inst_perm_arg="-o root -g root"
    local am_root=0
    if [[ $UID -eq 0 ]]; then
        dbg "Will try to install and configure system-wide"
        am_root=1
        sys_profile_path="/$spp"
    else
       msg "Warning: Not installing as root, this is not recommended other than for testing purposes"
       inst_perm_arg=""
    fi
    # Allow re-installing different versions, clean out old version if found
    if [[ -d "$actual_inst_path" ]] && [[ -r "$actual_inst_path/AUTOMATION_VERSION" ]]; then
        local installed_version=$(cat "$actual_inst_path/AUTOMATION_VERSION")
        msg "Warning: Removing existing installed version '$installed_version'"
        rm -rvf "$actual_inst_path"
        if ((am_root)); then
            msg "Warning: Removing any existing, system-wide environment configuration"
            rm -vf "/$spp"
        fi
    elif [[ -d "$actual_inst_path" ]]; then
        msg "Error: Unable to deal with unknown contents of '$actual_inst_path', manual removal required"
        msg "       Including any relevant lines in /$spp"
        exit 12
    fi

    msg "Installing common scripts/libraries version '$AUTOMATION_VERSION' into '$actual_inst_path'"

    cd "$TEMPDIR/common"
    install -v $inst_perm_arg -D -t "$actual_inst_path/bin" ./bin/*
    install -v $inst_perm_arg -D -t "$actual_inst_path/lib" ./lib/*

    cd "$actual_inst_path"
    dbg "Configuring example environment in $actual_inst_path/environment"
    cat <<EOF>"./environment"
# Added on $(date --iso-8601=minutes) by $actual_inst_path/bin/$SCRIPT_FILENAME"
export AUTOMATION_LIB_PATH="$actual_inst_path/lib"
export PATH="\${PATH:+\$PATH:}$actual_inst_path/bin"
EOF
    if ((am_root)); then
        msg "Installing example environment files system-wide"
        install -v $inst_perm_arg --no-target-directory "./environment" "/$spp"
    fi

    echo -n "Installation complete for " > /dev/stderr
    echo "$AUTOMATION_VERSION" | tee "./AUTOMATION_VERSION" > /dev/stderr
}

exec_installer() {
    # Actual version string may differ from $AUTOMATION_VERSION argument
    local version_arg
    if [[ -z "$TEMPDIR" ]] || [[ ! -d "$TEMPDIR" ]]; then
        msg "Error: exec_installer() expected $TEMPDIR to exist"
        exit 13
    fi

    msg "Preparing to execute automation installer for requested version '$AUTOMATION_VERSION'"

    # Special-case, use existing source repository
    if [[ "$AUTOMATION_VERSION" == "$MAGIC_LOCAL_VERSION" ]]; then
        cd $(realpath "$(dirname ${BASH_SOURCE[0]})/../")
        dbg "Will try to use installer from local repository $PWD"
        # Make sure it really is a git repository
        if [[ ! -r "./.git/config" ]]; then
            msg "ErrorL Must execute $SCRIPT_FILENAME from a repository clone."
            exit 6
        fi
        # Allow installer to clean-up TEMPDIR as with updated source
        dbg "Copying repository into \$TEMPDIR"
        cp --archive ./* ./.??* "$TEMPDIR/."
    else  # Retrieve the requested version (tag) of the source code
        version_arg="v$AUTOMATION_VERSION"
        if [[ "$AUTOMATION_VERSION" == "latest" ]]; then
            version_arg=$AUTOMATION_REPO_BRANCH
        fi
        msg "Attempting to clone branch/tag '$version_arg'"
        dbg "Cloning from $AUTOMATION_REPO_URL into \$TEMPDIR"
        git clone --quiet --branch "$version_arg" \
            --config advice.detachedHead=false \
            "$AUTOMATION_REPO_URL" "$TEMPDIR/."
    fi

    dbg "Now working from \$TEMPDIR"
    cd "$TEMPDIR"
    msg "Retrieving complete version information for temp. repo. clone"
    if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
        $OOE git fetch --unshallow --tags --force
    else
        $OOE git fetch --tags --force
    fi
    msg "Attempting to rettrieve actual version based on all configured remotes"
    version_arg=$(git describe HEAD)

    # Full path is required so script can find and install itself
    DOWNLOADED_INSTALLER="$TEMPDIR/bin/$SCRIPT_FILENAME"
    if [[ -x "$DOWNLOADED_INSTALLER" ]]; then
        msg "Executing install for actial version '$version_arg'"
        dbg "Using \$INSTALL_PREFIX '$INSTALL_PREFIX'; installer $DOWNLOADED_INSTALLER"
        exec env \
            DEBUG="$DEBUG" \
            TEMPDIR="$TEMPDIR" \
            INSTALL_PREFIX="$INSTALL_PREFIX" \
            AUTOMATION_REPO_URL="$AUTOMATION_REPO_URL" \
            AUTOMATION_REPO_BRANCH="$AUTOMATION_REPO_BRANCH" \
            _MAGIC_JUJU="$_DEFAULT_MAGIC_JUJU" \
            /bin/bash "$DOWNLOADED_INSTALLER" "$version_arg" $_ARGS
    else
        msg "Error: '$DOWNLOADED_INSTALLER' does not exist or is not executable" > /dev/stderr
        # Allow exi
        exit 8
    fi
}

check_args() {
    local arg_rx="^($AUTOMATION_REPO_BRANCH)|^(latest)|^(v?[0-9]+\.[0-9]+\.[0-9]+(-.+)?)"
    dbg "Debugging enabled; Command-line was '$0${AUTOMATION_VERSION:+ $AUTOMATION_VERSION}${_ARGS:+ $_ARGS}'"
    dbg "Argument validation regular-expresion '$arg_rx'"
    if [[ -z "$AUTOMATION_VERSION" ]]; then
        msg "Error: Must specify the version number to install, as the first and only argument."
        msg "       Use version '$MAGIC_LOCAL_VERSION' to install from local source."
        msg "       Use version 'latest' to install from current upstream"
        exit 2
    elif ! echo "$AUTOMATION_VERSION" | egrep -q "$arg_rx"; then
            msg "Error: '$AUTOMATION_VERSION' does not appear to be a valid version number"
            exit 4
    fi
}


##### MAIN #####

check_args

if [[ "$_MAGIC_JUJU" == "XXXXX" ]]; then
    dbg "Operating in source prep. mode"
    TEMPDIR=$(mktemp -p '' -d "tmp_${SCRIPT_FILENAME}_XXXXXXXX")
    dbg "Using temporary directory '$TEMPDIR'"
    trap "rm -rf $TEMPDIR" EXIT  # version may be invalid or clone could fail or some other error
    exec_installer # Try to obtain version from source then run it
elif [[ "$_MAGIC_JUJU" == "$_DEFAULT_MAGIC_JUJU" ]]; then
    dbg "Operating in actual install mode (ID $_MAGIC_JUJU)"
    # Running from $TEMPDIR in requested version of source
    $_MAGIC_JUJU

    # Validate the common library can load
    source "$INSTALL_PREFIX/automation/lib/anchors.sh"

    # Additional arguments specify subdirectories to check and chain to their installer script
    for arg in $_ARGS; do
        CHAIN_TO="$TEMPDIR/$arg/.install.sh"
        if [[ -r "$CHAIN_TO" ]]; then
            msg "     "
            msg "Chaining to additional install script for $arg"
            # Cannot assume common was installed system-wide
            env AUTOMATION_LIB_PATH=$AUTOMATION_LIB_PATH \
                DEBUG=$DEBUG \
                /bin/bash $CHAIN_TO
        else
            msg "Warning: Cannot find installer for $CHAIN_TO"
        fi
    done
else # Something has gone horribly wrong
    msg "Error: The executed installer script is incompatible with source version $AUTOMATION_VERSION"
    msg "Please obtain and use a newer version of $SCRIPT_FILENAME which supports ID $_MAGIC_JUJU"
    exit 10
fi

dbg "Clean exit."
