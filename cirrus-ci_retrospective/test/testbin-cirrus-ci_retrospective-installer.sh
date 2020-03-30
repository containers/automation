#!/bin/bash

# Load standardized test harness
source $(dirname "${BASH_SOURCE[0]}")/testlib.sh || exit 1

# Must go through the top-level install script that chains to ../.install.sh
INSTALL_SCRIPT=$(realpath "$TEST_DIR/../../bin/install_automation.sh")
TEMPDIR=$(mktemp -p "" -d "tmpdir_cirrus-ci_retrospective_XXXXX")
trap "rm -rf $TEMPDIR" EXIT

test_cmd "Verify cirrus-ci_retrospective can be installed under $TEMPDIR" \
    0 'Installation complete for.+installed cirrus-ci_retrospective' \
    env INSTALL_PREFIX=$TEMPDIR $INSTALL_SCRIPT 0.0.0 cirrus-ci_retrospective

test_cmd "Verify executing cirrus-ci_retrospective.sh gives 'Expecting' error message" \
    2 '::error::.+Expecting' \
    env AUTOMATION_LIB_PATH=$TEMPDIR/automation/lib $TEMPDIR/automation/bin/cirrus-ci_retrospective.sh

exit_with_status
