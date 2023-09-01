#!/bin/bash

# Simple shell utility to help validate several FQINs which should all have
# shared build-cache, have matching labels, and should all have been pushed
# w/in 3m of an indicated iso-8601 timestamp.
#
# Expected input is a file `check_fqins` where the first line is the push
# timestamp and remaining lines are the directory paths to locally skopeo
# synced images.

red="\e[1;31m"
cyn="\e[1;36m"
nor="\e[0m"

unset commit_arg
[[ $# -eq 0 ]] || \
  commit_arg="--commit $1"

# Assumes input timestamp can accurately convert into UTC
push_date=$(date -u -Iseconds -d $(head -1 ./check_fqins))
(
  set -x
  tail -n +2 ./check_fqins | xargs validate_image_cirrus.py -m $commit_arg -c "$push_date"
)
exit_code=$?
msg="##### EXIT $exit_code #####"
if [[ "$exit_code" -ne 0 ]]; then
  echo -e "$red$msg$nor"
else
  echo -e "$cyn$msg$nor"
fi
exit $exit_code
