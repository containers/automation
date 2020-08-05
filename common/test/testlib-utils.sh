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

test_cmd "The contains function operates as expected for the normal case" \
    0 "" \
    contains 3 1 2 3 4 5

test_cmd "The contains function operates as expected for the negative case" \
    1 "" \
    contains 42 1 2 3 4 5

test_cmd "The contains function operates as expected despite whitespace" \
    0 "" \
    contains 'foo bar' "foobar" "foo" "foo bar" "bar"

test_cmd "The contains function operates as expected despite whitespace, negative case" \
    1 "" \
    contains 'foo bar' "foobar" "foo" "baz" "bar"

test_cmd "The err_retry function retries three times for true + exit(0)" \
    126 "Attempt 3 of 3" \
    err_retry 3 10 0 true

test_cmd "The err_retry function retries three times for false, exit(1)" \
    126 "Attempt 3 of 3" \
    err_retry 3 10 1 false

test_cmd "The err_retry function catches an exit 42 in [1, 2, 3, 42, 99, 100, 101]" \
    42 "exit.+42" \
    err_retry 3 10 "1 2 3 42 99 100 101" exit 42

test_cmd "The err_retry function retries 2 time for exit 42 in [1, 2, 3, 99, 100, 101]" \
    42 "exit.+42" \
    err_retry 2 10 "1 2 3 99 100 101" exit 42

test_cmd "The err_retry function retries 1 time for false, non-zero exit" \
    1 "Attempt 2 of 2" \
    err_retry 2 10 "" false

# script is set +e
exit_with_status
