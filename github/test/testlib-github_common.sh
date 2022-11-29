#!/bin/bash

source $(dirname $BASH_SOURCE[0])/testlib.sh

# This is necessary when executing from a Github Action workflow so it ignores
# all magic output sugar.
_MAGICTOKEN="TEST${RANDOM}TEST"  # must be randomly generated / unguessable
echo "::stop-commands::$_MAGICTOKEN"
trap "echo '::$_MAGICTOKEN::'" EXIT

unset ACTIONS_STEP_DEBUG
unset A_DEBUG
source $TEST_DIR/$SUBJ_FILENAME || exit 1  # can't continue w/o loaded library

test_cmd "No debug message shows when A_DEBUG and ACTIONS_STEP_DEBUG are undefined" \
    0 '' \
    dbg 'This debug message should not appear'

export A_DEBUG=1
test_cmd "A debug notice message shows when A_DEBUG is true" \
    0 '::notice file=.+,line=.+:: This is a debug message' \
    dbg "This is a debug message"
unset A_DEBUG

export ACTIONS_STEP_DEBUG="true"
test_cmd "A debug notice message shows when ACTIONS_STEP_DEBUG is true" \
    0 '::notice file=.+,line=.+:: This is also a debug message' \
    dbg "This is also a debug message"
unset ACTIONS_STEP_DEBUG
unset A_DEBUG

test_cmd "Warning messages contain github-action sugar." \
    0 '::warning file=.+,line=.+:: This is a test warning message' \
    warn 'This is a test warning message'

test_cmd "Error messages contain github-action sugar." \
    0 '::error file=.+,line=.+:: This is a test error message' \
    die 'This is a test error message' 0

unset GITHUB_OUTPUT_FUDGED
if [[ -z "$GITHUB_OUTPUT" ]]; then
    # Not executing under github-actions
    GITHUB_OUTPUT=$(mktemp -p '' tmp_$(basename ${BASH_SOURCE[0]})_XXXX)
    GITHUB_OUTPUT_FUDGED=1
fi

test_cmd "The set_out_var function normally produces no output" \
    0 '' \
    set_out_var TESTING_NAME TESTING VALUE

export A_DEBUG=1
test_cmd "The set_out_var function is debugable" \
    0 "::notice file=.+line=.+:: Setting Github.+'DEBUG_TESTING_NAME' to 'DEBUGGING TESTING VALUE'" \
    set_out_var DEBUG_TESTING_NAME DEBUGGING TESTING VALUE
unset A_DEBUG

test_cmd "Previous set_out_var function properly sets a step-output value" \
    0 'TESTING_NAME=TESTING VALUE' \
    cat $GITHUB_OUTPUT

# Must be the last commands in this file
if ((GITHUB_OUTPUT_FUDGED)); then rm -f "$GITHUB_OUTPUT"; fi
exit_with_status
