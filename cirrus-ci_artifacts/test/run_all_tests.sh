#!/bin/bash

if [[ "$CIRRUS_CI" != "true" ]]; then
    echo -e "\nSkipping: Test must be executed under Cirrus-CI\n"
    exit 0
fi

TESTDIR=$(dirname ${BASH_SOURCE[0]})

cd "$TESTDIR/../"
pip3 install --user --requirement ./requirements.txt

cd "$TESTDIR"
./test_cirrus-ci_artifacts.py
