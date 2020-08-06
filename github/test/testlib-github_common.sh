#!/bin/bash

source $(dirname $BASH_SOURCE[0])/testlib.sh

# This is necessary when executing from a Github Action workflow so it ignores
# all magic output tokens
echo "::stop-commands::TESTING"
trap "echo '::TESTING::'" EXIT

test_cmd "The library $TEST_DIR/$SUBJ_FILENAME loads" \
    0 '' \
    source $TEST_DIR/$SUBJ_FILENAME

DEBUG=1
ACTIONS_STEP_DEBUG=true
# Should update $DEBUG value
source $TEST_DIR/$SUBJ_FILENAME || exit 1  # can't continue w/o loaded library

test_cmd "The debug message prefix is compatible with github actions commands" \
    0 '::debug:: This is a test debug message.+common/test/testlib.sh' \
    dbg 'This is a test debug message'

unset ACTIONS_STEP_DEBUG
unset DEBUG
# Should update $DEBUG value
source $TEST_DIR/$SUBJ_FILENAME

test_cmd "No debug message shows when ACTIONS_STEP_DEBUG is undefined" \
    0 '' \
    dbg 'This debug message should not appear'

test_cmd "The warning message prefix is compatible with github actions commands" \
    0 '::warning:: This is a test warning message.+testlib-github_common.sh' \
    warn 'This is a test warning message'

test_cmd "The github actions command for setting output parameter is formatted as expected" \
    0 '::set-output name=TESTING_NAME::TESTING VALUE' \
    set_out_var TESTING_NAME TESTING VALUE

# Must be the last command in this file
exit_with_status
