#!/bin/bash

set -e

testdir=$(dirname $0)

for i in $testdir/*.t;do
    echo -e "\nExecuting $testdir/$i..." >&2
    $i
done
