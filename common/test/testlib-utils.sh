#!/bin/bash

source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
source "$TEST_DIR"/"$SUBJ_FILENAME" || exit 2

test_function_one(){
    echo "This is test function one"
}

test_function_two(){
    echo "This is test function two"
}

test_cmd "The copy_function produces no output, while copying test_function_two" \
    0 "" \
    copy_function test_function_two test_function_three

# test_cmd executes the command-under-test inside a sub-shell
copy_function test_function_two test_function_three
test_cmd "The copy of test_function_two has identical behavior as two." \
    0 "This is test function two" \
    test_function_three

test_cmd "The rename_function produces no output, while renaming test_function_one" \
    0 "" \
    rename_function test_function_one test_function_three

# ""
rename_function test_function_one test_function_three
test_cmd "The rename_function removed the source function" \
    127 "command not found" \
    test_function_one

test_cmd "The behavior of test_function_three matches renamed test_function_one" \
    0 "This is test function one" \
    test_function_three

# script is set +e
exit_with_status
