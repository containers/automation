#!/bin/bash

set -e

if [[ "$GITHUB_ACTIONS" == "true" ]]; then
    # At time of this commit, the version of skopeo in GHA ubuntu
    # is too old.  Does not have support for --preserve-digests
    echo "CI Testing not supported under github actions: Skipping"
    exit 0
fi

if [[ ! -x $(type -P flake8-3) ]]; then
  echo "Can't find flake8-3 binary, is script executing inside correct CI container?"
  exit 1
fi

cd $(dirname "${BASH_SOURCE[0]}")/../
flake8-3 --color=always --max-line-length=120 --ignore=D401 ./validate_image_cirrus.py

cd $(dirname "${BASH_SOURCE[0]}")
for testscript in test???-*.sh; do
    echo -e "\nExecuting $testscript..." > /dev/stderr
    ./$testscript
done
