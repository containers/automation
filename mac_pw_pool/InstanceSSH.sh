#!/bin/bash

set -eo pipefail

# Helper for humans to access an existing instance.  It depends on:
#
# * You know the instance-id value.
# * All requirements listed in the top `LaunchInstances.sh` comment.
# * The local ssh-agent is able to supply the appropriate private key.

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

# Enable access to VNC if it's running
# ref: https://repost.aws/knowledge-center/ec2-mac-instance-gui-access
SSH="ssh $SSH_ARGS -L 5900:localhost:5900"  # N/B: library default nulls stdin

[[ -n "$1" ]] || \
    die "Must provide EC2 instance ID as first argument"
instance_id="${1:-EmptyID}"
shift

inst_json=$($AWS ec2 describe-instances --instance-ids "$instance_id")
pub_dns=$(jq -r -e '.Reservations?[0]?.Instances?[0]?.PublicDnsName?' <<<"$inst_json")
if [[ -z "$pub_dns" ]] || [[ "$pub_dns" == "null" ]]; then
    die "Instance '$1' does not exist, or have a public DNS address allocated (yet)."
fi

echo "+ $SSH ec2-user@$pub_dns \"$*\"" >> /dev/stderr
$SSH ec2-user@$pub_dns "$@"
