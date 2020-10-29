#!/bin/bash

# Convenience script for executing all tests in every 'test' subditrectory

set -e

if [[ "$CIRRUS_CI" == "true" ]]; then
    echo "Running under Cirrus-CI: Exporting all \$CIRRUS_* variables"
    # Allow tests access to details presented by Cirrus-CI
    for env_var in $(awk 'BEGIN{for(v in ENVIRON) print v}' | grep -E "^CIRRUS_")
    do
        echo "    $env_var=${!env_var}"
        export $env_var="${!env_var}"
    done
fi

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
