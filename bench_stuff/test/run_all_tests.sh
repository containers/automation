#!/bin/bash

set -e

TESTDIR=$(dirname ${BASH_SOURCE[0]})

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
    echo "Lint/Style checking not supported under github actions: Skipping"
    exit 0
fi

if [[ -x $(type -P flake8-3) ]]; then
    cd "$TESTDIR"
    set -a
    virtualenv testvenv
    source testvenv/bin/activate
    testvenv/bin/python -m pip install --upgrade pip
    pip3 install --requirement ../requirements.txt
    set +a

    ./test_bench_stuff.py -v

    cd ..
    flake8-3 --max-line-length=100 ./bench_stuff.py
    flake8-3 --max-line-length=100 --extend-ignore=D101,D102,D103,D105 test/test_bench_stuff.py
else
    echo "Can't find flake-8-3 binary, is script executing inside CI container?"
    exit 1
fi
