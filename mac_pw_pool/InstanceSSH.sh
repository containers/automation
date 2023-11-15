#!/bin/bash

set -eo pipefail

# Helper for humans to access an existing instance.  It depends on:
#
# * You know the instance-id value.
# * All requirements listed in the top `LaunchInstances.sh` comment.
# * The local ssh-agent is able to supply the appropriate private key.

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

SSH="ssh $SSH_ARGS"  # N/B: library default nulls stdin

[[ -n "$1" ]] || \
    die "Must provide EC2 instance ID as first argument"
instance_id="${1:-EmptyID}"
shift

inst_json=$($AWS ec2 describe-instances --instance-ids "$instance_id")
pub_dns=$(jq -r -e '.Reservations?[0]?.Instances?[0]?.PublicDnsName?' <<<"$inst_json")
if [[ -z "$pub_dns" ]] || [[ "$pub_dns" == "null" ]]; then
    die "Instance '$1' does not exist, or have a public DNS address allocated (yet)."
fi

$SSH ec2-user@$pub_dns "$@"
