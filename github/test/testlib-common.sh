#!/bin/bash

source $(dirname $BASH_SOURCE[0])/testlib.sh

test_cmd "The library $TEST_DIR/$SUBJ_FILENAME loads" \
    0 '' \
    source $TEST_DIR/$SUBJ_FILENAME

source $TEST_DIR/$SUBJ_FILENAME


DEBUG=1
ACTIONS_STEP_DEBUG=true
test_cmd "The debug message prefix does _NOT_ use github actions command prefix" \
    0 '^((?!::debug::).)*' \
    dbg 'This is a test debug message'
unset ACTIONS_STEP_DEBUG
unset DEBUG

test_cmd "The warning message prefix is compatible with github actions commands" \
    0 '::warning:: This is a test warning message.+common/test/testlib.sh' \
    warn 'This is a test warning message'

test_cmd "The github actions command for setting output parameter is formatted as expected" \
    0 '::set-output name=TESTING_NAME::TESTING VALUE' \
    set_out_var TESTING_NAME TESTING VALUE

# Must be the last command in this file
exit_with_status
