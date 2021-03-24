#!/bin/bash

# Load standardized test harness
SCRIPT_DIRPATH=$(dirname "${BASH_SOURCE[0]}")
source $SCRIPT_DIRPATH/testlib.sh || exit 1

# Must go through the top-level install script that chains to ../.install.sh
TEST_DIR=$(realpath "$SCRIPT_DIRPATH/../")
INSTALL_SCRIPT=$(realpath "$TEST_DIR/../bin/install_automation.sh")
TEMPDIR=$(mktemp -p "" -d "tmpdir_cirrus-ci_env_XXXXX")

test_cmd "Verify cirrus-ci_env can be installed under $TEMPDIR" \
    0 'Installation complete for.+cirrus-ci_env' \
    env INSTALL_PREFIX=$TEMPDIR $INSTALL_SCRIPT 0.0.0 cirrus-ci_env

test_cmd "Verify executing cirrus-ci_env.py gives 'usage' error message" \
    2 'cirrus-ci_env.py: error: the following arguments are required:' \
    $TEMPDIR/automation/bin/cirrus-ci_env.py

trap "rm -rf $TEMPDIR" EXIT
exit_with_status
