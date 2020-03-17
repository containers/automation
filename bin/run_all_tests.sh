#!/bin/bash

# Convenience script for executing all tests in every 'test' subditrectory

set -e

this_script_filepath="$(realpath $0)"
runner_script_filename="$(basename $0)"

for test_subdir in $(find "$(realpath $(dirname $0)/../)" -type d -name test | sort -r); do
    test_runner_filepath="$test_subdir/$runner_script_filename"
    if [[ -x "$test_runner_filepath" ]] && [[ "$test_runner_filepath" != "$this_script_filepath" ]]; then
        echo -e "\nExecuting $test_runner_filepath..." > /dev/stderr
        $test_runner_filepath
    else
        echo -e "\nWARNING: Skipping $test_runner_filepath" > /dev/stderr
    fi
done

echo "Successfully executed all $runner_script_filename scripts"
