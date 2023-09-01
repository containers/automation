#!/bin/bash

set -e

# Companion/wrapper around check_fqins.sh for use in cases where the
# org.opencontainers.image.revision label is missing but the push
# date is known (first line of the `check_fqins` file).
#
# Requires the first/only arument to be the path of a repository clone
# to check.  Walks commits preceeding the date given (in `check_fqins`),
# repeatedly calling check_fqins.sh until it exits cleanly or no match
# is found.

prior_commits=10  # Search backwards this many commits
commits_before=$(date -u -Idate -d $(head -1 check_fqins))
# Stop checking commits if this regex matches the output
stop_on_rx='Cirrus timestamp.+((No relevant)|(Over \+))'

cd "$1"
declare -a possible_commits
# Note: List returned from git will be going backwards in time
possible_commits=( $(TZ=UTC0 git log --pretty=oneline --no-show-signature \
                   --until "$commits_before" \
                   --grep "^Merge pull request" \
                   | awk '{print $1}' | head -$prior_commits) )
cd -

echo "Attempting to validate up to $prior_commits commits merged before $commits_before"
for commit in "${possible_commits[@]}"; do
  unset output
  if output=$(check_fqins.sh $commit); then
    echo "$output"
    break
  elif grep -E "$stop_on_rx"<<<"$output"; then
    echo "$output"
    echo "Stopping, above result needs verbose and/or manual checking."
    break
  fi
  echo "Next commit..."
done
