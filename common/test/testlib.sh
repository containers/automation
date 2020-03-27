#!/bin/bash

# Library of functions and values used by other unit-testing scripts.
# Not intended for direct execution.

# Set non-zero to enable
TEST_DEBUG=${TEST_DEBUG:-0}

# Unit-tests for library with a similar name
TEST_FILENAME=$(basename $0)  # prefix-replace needs this as a variable
SUBJ_FILENAME="${TEST_FILENAME#test-}"; unset TEST_FILENAME
TEST_DIR=$(dirname $0)/../lib

# Always run all tests, and keep track of failures.
FAILURE_COUNT=0

# Assume test script is set +e and this will be the last call
exit_with_status() {
    if ((FAILURE_COUNT)); then
        echo "Total Failures: $FAILURE_COUNT"
    else
        echo "All tests passed"
    fi
    set -e  # Force exit with exit code
    test "$FAILURE_COUNT" -eq 0
}

# Used internally by test_cmd to assist debugging and output file cleanup
_test_report() {
    local msg="$1"
    local inc_fail="$2"
    local outf="$3"

    if ((inc_fail)); then
        let 'FAILURE_COUNT++'
        echo -n "fail - "
    else
        echo -n "pass - "
    fi

    echo -n "$msg"

    if [[ -r "$outf" ]]; then
        # Ignore output when successful
        if ((inc_fail)) || ((TEST_DEBUG)); then
            echo " (output follows)"
            cat "$outf"
        fi
        rm -f "$outf"
    fi
    echo -e '\n' # Makes output easier to read
}

# Execute a test command or shell function, capture it's output and verify expectations.
# usage: test_cmd <description> <exp. exit code> <exp. output regex> <command> [args...]
# Notes: Expected exit code is not checked if blank.  Expected output will be verified blank
#        if regex is empty.  Otherwise, regex checks whitespace-squashed output.
test_cmd() {
    echo "Testing: ${1:-WARNING: No Test description given}"
    local e_exit="$2"
    local e_out_re="$3"
    shift 3

    if ((TEST_DEBUG)); then
        echo "# $@"
    fi

    # Using egrep vs file safer than shell builtin test
    local a_out_f=$(mktemp -p '' "tmp_${FUNCNAME[0]}_XXXXXXXX")
    local a_exit=0

    # Use a sub-shell to capture possible function exit call and all output
    ( set -e; "$@" &> $a_out_f )
    a_exit="$?"

    if [[ -n "$e_exit" ]] && [[ $e_exit -ne $a_exit ]]; then
        _test_report "Expected exit-code $e_exit but received $a_exit while executing $1" 1 "$a_out_f"
    elif [[ -z "$e_out_re" ]] && [[ -n "$(<$a_out_f)" ]]; then
        _test_report "Expecting no output from $@" 1 "$a_out_f"
    elif [[ -n "$e_out_re" ]]; then
        # Make matching to multi-line output easier
        tr -s '[:space:]' ' ' < "$a_out_f" > "${a_out_f}.oneline"; mv "${a_out_f}.oneline" "$a_out_f"
        if egrep -q "$e_out_re" "${a_out_f}"; then
            _test_report "Command $1 exited as expected with expected output" 0 "$a_out_f"
        else
            _test_report "Expecting regex '$e_out_re' match to whitespace-squashed output" 1 "$a_out_f"
        fi
    else # Pass
        _test_report "Command $1 exited as expected ($a_exit)" 0 "$a_out_f"
    fi
}
