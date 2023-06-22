#!/bin/bash

# Unit-tests for library script in the current directory
# Also verifies test script is derived from library filename

source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

test_cmd "Library $SUBJ_FILENAME is not executable" \
    0 "" \
    test ! -x "$SCRIPT_PATH/$SUBJ_FILENAME"

for var in OS_RELEASE_VER OS_RELEASE_ID OS_REL_VER; do
    test_cmd "The variable \$$var is defined and non-empty" \
        0 "" \
        test -n "${!var}"
done

for var in OS_RELEASE_VER OS_REL_VER; do
    NODOT=$(tr -d '.' <<<"${!var}")
    test_cmd "The '.' character does not appear in \$$var" \
        0 "" \
        test "$NODOT" == "${!var}"
done

for OS_RELEASE_ID in 'debian' 'ubuntu'; do
  (
    export _TEST_UID=$RANDOM  # Normally $UID is read-only
    source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

    test_cmd "The '\$SUDO' env. var. is non-empty when \$_TEST_UID is non-zero" \
        0 "" \
        test -n "$SUDO"

    test_cmd "The '\$SUDO' env. var. contains 'noninteractive' when '\$_TEST_UID' is non-zero" \
        0 "noninteractive" \
        echo "$SUDO"
  )
done

# Must be last call
exit_with_status
