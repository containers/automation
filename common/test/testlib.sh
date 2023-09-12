#!/bin/bash

# Library of functions and values used by other unit-testing scripts.
# Not intended for direct execution.

# Set non-zero to enable
TEST_DEBUG=${TEST_DEBUG:-0}

# Test subject filename and directory name are derived from test-script filename
SUBJ_FILENAME=$(basename $0)
if [[ "$SUBJ_FILENAME" =~ "testlib-" ]]; then
    SUBJ_FILENAME="${SUBJ_FILENAME#testlib-}"
    TEST_DIR="${TEST_DIR:-$(dirname $0)/../lib}"
elif [[ "$SUBJ_FILENAME" =~ "testbin-" ]]; then
    SUBJ_FILENAME="${SUBJ_FILENAME#testbin-}"
    TEST_DIR="${TEST_DIR:-$(dirname $0)/../bin}"
else
    echo "Unable to handle script filename/prefix '$SUBJ_FILENAME'"
    exit 9
fi

# Always run all tests, and keep track of failures.
FAILURE_COUNT=0

# Duplicated from common/lib/utils.sh to not create any circular dependencies
copy_function() {
    local src="$1"
    local dst="$2"
    test -n "$(declare -f "$1")" || return
    eval "${_/$1/$2}"
}

rename_function() {
    local from="$1"
    local to="$2"
    copy_function "$@" || return
    unset -f "$1"
}

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
        rm -f "$outf" "$outf.oneline"
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
        echo "# $@" > /dev/stderr
    fi

    # Using grep vs file safer than shell builtin test
    local a_out_f=$(mktemp -p '' "tmp_${FUNCNAME[0]}_XXXXXXXX")
    local a_exit=0

    # Use a sub-shell to capture possible function exit call and all output
    set -o pipefail
    ( set -e; "$@" 0<&- |& tee "$a_out_f" | tr -s '[:space:]' ' ' &> "${a_out_f}.oneline")
    a_exit="$?"
    if ((TEST_DEBUG)); then
        echo "Command/Function call exited with code: $a_exit"
    fi

    if [[ -n "$e_exit" ]] && [[ $e_exit -ne $a_exit ]]; then
        _test_report "Expected exit-code $e_exit but received $a_exit while executing $(basename $1)" "1" "$a_out_f"
    elif [[ -z "$e_out_re" ]] && [[ -n "$(<$a_out_f)" ]]; then
        _test_report "Expecting no output from $*" "1" "$a_out_f"
    elif [[ -n "$e_out_re" ]]; then
        if ((TEST_DEBUG)); then
            echo "Received $(wc -l $a_out_f | awk '{print $1}') output lines of $(wc -c $a_out_f | awk '{print $1}') bytes total"
        fi
        if grep -Eq "$e_out_re" "${a_out_f}.oneline"; then
            _test_report "Command $(basename $1) exited as expected with expected output" "0" "$a_out_f"
        else
            _test_report "Expecting regex '$e_out_re' match to (whitespace-squashed) output" "1" "$a_out_f"
        fi
    else # Pass
        _test_report "Command $(basename $1) exited as expected ($a_exit)" "0" "$a_out_f"
    fi
}
