#!/bin/bash

source $(dirname $0)/testlib.sh || exit 1
source "$TEST_DIR"/"$SUBJ_FILENAME" || exit 2

test_message_text="This is the test text for a console_output library unit-test"

basic_tests() {
    local _fname=$1
    local _exp_exit=$2
    local _exp_word=$3

    [[ "$_fname" == "dbg" ]] || \
        test_cmd "At least 5-stars are shown on call to $_fname function" \
            $_exp_exit "\*{5}" \
            $_fname "$test_message_text"

    test_cmd "The word '$_exp_word' appears on call to $_fname function" \
        $_exp_exit "$_exp_word" \
        $_fname "$test_message_text"

    test_cmd \
        "A default message is shown when none provided" \
        $_exp_exit "$_exp_word.+\w+" \
        $_fname

    test_cmd "The message text appears on call to $_fname message" \
        $_exp_exit "$test_message_text" \
        $_fname "$test_message_text"

    test_cmd "The message text includes a the file, line number and testing function reference" \
        $_exp_exit "testlib.sh:[[:digit:]]+ in test_cmd()" \
        $_fname "$test_message_text"
}

for fname in warn die; do
    exp_exit=0
    exp_word="WARNING"
    if [[ "$fname" == "die" ]]; then
        exp_exit=1
        exp_word="ERROR"
    fi
    basic_tests $fname $exp_exit $exp_word
done

DEBUG=0
test_cmd \
    "The dbg function has no output when \$DEBUG is zero and no message is given" \
    0 "" \
    dbg

test_cmd \
    "The dbg function has no output when \$DEBUG is zero and a test message is given" \
    0 "" \
    dbg "$test_message_text"

DEBUG=1
basic_tests dbg 0 DEBUG

# script is set +e
exit_with_status
