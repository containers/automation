#!/bin/bash

# Convenience script for executing all tests

set -e

cd $(dirname $0)
for testscript in test???-*.sh; do
    echo -e "\nExecuting $testscript..." > /dev/stderr
    ./$testscript
done
