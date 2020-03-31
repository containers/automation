#!/bin/bash

# Unit-tests for installation script with common scripts/libraries.
# Also verifies test script is derived from library filename

TEST_DIR=$(realpath "$(dirname ${BASH_SOURCE[0]})/../../bin")
source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
INSTALLER_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"
TEST_INSTALL_ROOT=$(mktemp -p '' -d "tmp_$(basename $0)_XXXXXXXX")
trap "rm -rf $TEST_INSTALL_ROOT" EXIT

# Receives special treatment in the installer script
export INSTALL_PREFIX="$TEST_INSTALL_ROOT/testing"

test_cmd \
    "The installer exits non-zero with a helpful message when run without a version argument" \
    2 "Error.+version.+install.+\0.\0.\0" \
    $INSTALLER_FILEPATH

test_cmd \
    "The installer detects an argument which is clearly not a symantic version number" \
    4 "Error.+not.+valid version number" \
    $INSTALLER_FILEPATH "not a version number"

test_cmd \
    "The inetaller exits non-zero with a helpful message about an non-existant version" \
    128 "fatal.+v99.99.99.*not found" \
    $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer detects incompatible future installer source version by an internal mechanism" \
    10 "Error.+incompatible.+99.99.99" \
    env _MAGIC_JUJU=TESTING$(uuidgen)TESTING $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer successfully installs and configures into \$INSTALL_PREFIX" \
    0 "Installation complete" \
    $INSTALLER_FILEPATH 0.0.0

test_cmd \
    "The installer correctly removes/reinstalls \$TEST_INSTALL_ROOT" \
    0 "Warning: Removing existing installed version" \
    $INSTALLER_FILEPATH 0.0.0

test_cmd \
    "The re-installed version has AUTOMATION_VERSION file matching the current version" \
    0 "$(git describe HEAD)" \
    cat "$INSTALL_PREFIX/automation/AUTOMATION_VERSION"

load_example_environment() {
    local _args="$@"
    # Don't disturb testing
    (
        source "$INSTALL_PREFIX/automation/environment" || return 99
        echo "AUTOMATION_LIB_PATH ==> ${AUTOMATION_LIB_PATH:-UNDEFINED}"
        echo "PATH ==> ${PATH:-EMPTY}"
        [[ -z "$_args" ]] || $_args
    )
}

execute_in_example_environment() {
    load_example_environment "$@"
}

test_cmd \
    "The example environment defines AUTOMATION_LIB_PATH" \
    0 "AUTOMATION_LIB_PATH ==> $INSTALL_PREFIX/automation/lib" \
    load_example_environment

test_cmd \
    "The example environment appends to \$PATH" \
    0 "PATH ==> .+:$INSTALL_PREFIX/automation/bin" \
    load_example_environment

test_cmd \
    "The installed installer, can update itself to the latest upstream version" \
    0 "Installation complete for v[0-9]+\.[0-9]+\.[0-9]+" \
    execute_in_example_environment $SUBJ_FILENAME latest

# Must be last call
exit_with_status
