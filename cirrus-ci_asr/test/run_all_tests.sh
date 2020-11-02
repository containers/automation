#!/bin/bash

# Stupid-simple, very basic "can it run" test

set -e

if [[ "$CIRRUS_CI" != "true" ]]; then
    echo -e "\nSkipping: Test must be executed under Cirrus-CI\n"
    exit 0
fi

cd "$(dirname ${BASH_SOURCE[0]})/../"
pip3 install --user --requirement ./requirements.txt
echo "Testing cirrus-ci_asr.py $CIRRUS_REPO_OWNER $CIRRUS_REPO_NAME $CIRRUS_CHANGE_IN_REPO"
./cirrus-ci_asr.py $CIRRUS_REPO_OWNER $CIRRUS_REPO_NAME $CIRRUS_CHANGE_IN_REPO
