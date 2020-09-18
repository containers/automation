#!/bin/bash

set -e

testdir=$(dirname $0)

# CI systems are missing important packages needed for this tool; so
# we'll have to rely on Ed testing manually
perl_check() {
    perl -M"$1" -e '1' &> /dev/null && return
    echo "perl $1 unavailable, skipping $testdir" >&2
    exit 0
}

perl_check Test::More
perl_check YAML::XS

for i in $testdir/*.t;do
    echo -e "\nExecuting $testdir/$i..." >&2
    $i
done
