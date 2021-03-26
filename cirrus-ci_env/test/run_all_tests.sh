#!/bin/bash

set -e

cd $(dirname ${BASH_SOURCE[0]})
./test_cirrus-ci_env.py
./testbin-cirrus-ci_env.sh
./testbin-cirrus-ci_env-installer.sh

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
    echo "Lint/Style checking not supported under github actions: Skipping"
    exit 0
elif [[ -x $(type -P flake8-3) ]]; then
    cd ..
    flake8-3 --max-line-length=100 .
    flake8-3 --max-line-length=100 --extend-ignore=D101,D102 test
else
    echo "Can't find flake-8-3 binary, is script executing inside CI container?"
    exit 1
fi
