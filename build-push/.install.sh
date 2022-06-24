#!/bin/bash

# Installs 'build-push' script system-wide.  NOT intended to be used directly
# by humans, should only be used indirectly by running
# ../bin/install_automation.sh <ver> build-push

set -eo pipefail

source "$AUTOMATION_LIB_PATH/anchors.sh"
source "$AUTOMATION_LIB_PATH/console_output.sh"

INSTALL_PREFIX=$(realpath $AUTOMATION_LIB_PATH/..)
# Assume the directory this script is in, represents what is being installed
INSTALL_NAME=$(basename $(dirname ${BASH_SOURCE[0]}))
AUTOMATION_VERSION=$(automation_version)
[[ -n "$AUTOMATION_VERSION" ]] || \
    die "Could not determine version of common automation libs, was 'install_automation.sh' successful?"

echo "Installing $INSTALL_NAME version $(automation_version) into $INSTALL_PREFIX"

unset INST_PERM_ARG
if [[ $UID -eq 0 ]]; then
    INST_PERM_ARG="-o root -g root"
fi

cd $(dirname $(realpath "${BASH_SOURCE[0]}"))
install -v $INST_PERM_ARG -D -t "$INSTALL_PREFIX/bin" ./bin/*

echo "Successfully installed $INSTALL_NAME"
