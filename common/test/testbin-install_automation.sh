#!/bin/bash

# Unit-tests for installation script with common scripts/libraries.
# Also verifies test script is derived from library filename

TEST_DIR=$(realpath "$(dirname ${BASH_SOURCE[0]})/../../bin")
source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
INSTALLER_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"
TEST_INSTALL_ROOT=$(mktemp -p '' -d "testing_$(basename $0)_XXXXXXXX")
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
    "The installer exits non-zero with a helpful message about an non-existent version" \
    128 "fatal.+v99.99.99.*not found" \
    $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer successfully installs the oldest tag" \
    0 "installer version 'v1.0.0'.+exec.+AUTOMATION_REPO_BRANCH=main.+Installation complete" \
    $INSTALLER_FILEPATH 1.0.0

test_cmd \
    "The oldest installed installer's default branch was modified" \
    0 "" \
    grep -Eqm1 '^AUTOMATION_REPO_BRANCH=.+main' "$INSTALL_PREFIX/automation/bin/$SUBJ_FILENAME"

test_cmd \
    "The installer detects incompatible future installer source version by an internal mechanism" \
    10 "Error.+incompatible.+99.99.99" \
    env _MAGIC_JUJU=TESTING$(uuidgen)TESTING $INSTALLER_FILEPATH 99.99.99

test_cmd \
    "The installer successfully installs and configures into \$INSTALL_PREFIX" \
    0 "Installation complete" \
    $INSTALLER_FILEPATH 0.0.0

for required_file in environment AUTOMATION_VERSION; do
    test_cmd \
        "The installer created the file $required_file in $INSTALL_PREFIX/automation" \
        0 "" \
        test -r "$INSTALL_PREFIX/automation/$required_file"
done

test_cmd \
    "The installer correctly removes/reinstalls \$TEST_INSTALL_ROOT" \
    0 "Warning: Removing existing installed version" \
    $INSTALLER_FILEPATH 0.0.0

test_cmd \
    "The re-installed version has AUTOMATION_VERSION file matching the current version" \
    0 "$(git describe HEAD)" \
    cat "$INSTALL_PREFIX/automation/AUTOMATION_VERSION"

test_cmd \
    "The installer script doesn't redirect to 'stderr' anywhere." \
    1 "" \
    grep -q '> /dev/stderr' $INSTALLER_FILEPATH

load_example_environment() {
    local _args="$@"
    # Don't disturb testing
    (
        source "$INSTALL_PREFIX/automation/environment" || return 99
        echo "AUTOMATION_LIB_PATH ==> ${AUTOMATION_LIB_PATH:-UNDEFINED}"
        echo "PATH ==> ${PATH:-EMPTY}"
        [[ -z "$_args" ]] || A_DEBUG=1 $_args
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
    0 "Finalizing successful installation of version v" \
    execute_in_example_environment $SUBJ_FILENAME latest

# Ensure cleanup
rm -rf $TEST_INSTALL_ROOT

# Must be last call
exit_with_status
