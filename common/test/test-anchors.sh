#!/bin/bash

# Unit-tests for library script in the current directory
# Also verifies test script is derived from library filename

source $(dirname $0)/testlib.sh || exit 1
source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

test_cmd "Library $SUBJ_FILENAME is not executable" \
    0 "" \
    test ! -x "$SCRIPT_PATH/$SUBJ_FILENAME"

test_cmd "The unit-test and library files not in same directory" \
    0 "" \
    test "$COMMON_LIB_PATH" != "$SCRIPT_PATH"

test_cmd "This common unit-test has relative lib path identical to common_lib_path" \
    0 "" \
    test "$COMMON_LIB_PATH" == "$SCRIPT_LIB_PATH"

test_cmd "The repository root contains a .git directory" \
    0 "" \
    test -d "$REPO_ROOT/.git"

for path_var in COMMON_LIB_PATH REPO_ROOT SCRIPT_PATH SCRIPT_LIB_PATH; do
    test_cmd "\$$path_var is defined and non-empty: ${!path_var}" \
        0 "" \
        test -n "${!path_var}"
    test_cmd "\$$path_var referrs to existing directory" \
        0 "" \
        test -d "${!path_var}"
done

test_cmd "Able to create a temporary directory using '$MKTEMP_FORMAT'" \
    0 "/tmp/.tmp_test-anchors.sh" \
    mktemp -p '' -d "$MKTEMP_FORMAT"

test_cmd "Able to remove temporary directory" \
    0 "" \
    rm -rf "/tmp/.tmp_test-anchors.sh*"

# Must be last call
exit_with_status
