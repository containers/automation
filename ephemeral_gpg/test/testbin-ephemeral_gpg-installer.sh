#!/bin/bash

# Load standardized test harness
source $(dirname $(realpath "${BASH_SOURCE[0]}"))/testlib.sh || exit 1

# Must go through the top-level install script that chains to ../.install.sh
INSTALL_SCRIPT=$(realpath "$TEST_DIR/../../bin/install_automation.sh")
TEMPDIR=$(mktemp -p "" -d "tmpdir_ephemeral_gpg_XXXXX")
trap "rm -rf $TEMPDIR" EXIT
TEST_PRIVATE_KEY_FILEPATH="$TEMPDIR/test_directory_not_file"
TEST_CMD="AUTOMATION_LIB_PATH=$TEMPDIR/automation/lib $TEMPDIR/automation/bin/ephemeral_gpg.sh"
unset PRIVATE_KEY_FILEPATH

##### MAIN() #####

test_cmd "Verify ephemeral_gpg can be installed under $TEMPDIR" \
    0 'Installation complete for.+installed ephemeral_gpg' \
    env INSTALL_PREFIX=$TEMPDIR $INSTALL_SCRIPT 0.0.0 ephemeral_gpg

test_cmd "Verify executing ephemeral_gpg.sh gives 'Expecting' error message" \
    2 'ERROR.+Expecting.+empty' \
    env $TEST_CMD

test_cmd "Verify creation of directory inside temporary install path is successful" \
    0 "mkdir: created.+$TEST_PRIVATE_KEY_FILEPATH" \
    mkdir -vp "$TEST_PRIVATE_KEY_FILEPATH"

test_cmd "Verify executing ephemeral_gpg.sh detects \$PRIVATE_GPG_FILEPATH directory" \
    2 'ERROR.+Expecting.+file' \
    env PRIVATE_KEY_FILEPATH=$TEST_PRIVATE_KEY_FILEPATH $TEST_CMD

test_cmd "Verify git_unattended_gpg.sh.in installed in library directory" \
    0 "" \
    test -r "$TEMPDIR/automation/lib/git_unattended_gpg.sh.in"

exit_with_status
