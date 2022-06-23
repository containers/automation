#!/bin/bash

TESTDIR=$(dirname ${BASH_SOURCE[0]})
cd "$TESTDIR"

set -a
virtualenv testvenv
source testvenv/bin/activate
testvenv/bin/python -m pip install --upgrade pip
pip3 install --requirement ../requirements.txt
set +a

./test_cirrus-ci_artifacts.py
