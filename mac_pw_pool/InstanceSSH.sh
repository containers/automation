#!/bin/bash

set -eo pipefail

# Helper for humans to access an existing instance.  It depends on:
#
# * You know the instance-id or name.
# * All requirements listed in the top `LaunchInstances.sh` comment.
# * The local ssh-agent is able to supply the appropriate private key.

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

SSH="ssh $SSH_ARGS"  # N/B: library default nulls stdin
if nc -z localhost 5900; then
    # Enable access to VNC if it's running
    # ref: https://repost.aws/knowledge-center/ec2-mac-instance-gui-access
    SSH+=" -L 5900:localhost:5900"
fi

[[ -n "$1" ]] || \
    die "Must provide EC2 instance ID as first argument"

case "$1" in
    i-*)
      inst_json=$($AWS ec2 describe-instances --instance-ids "$1") ;;
    *)
      inst_json=$($AWS ec2 describe-instances --filter "Name=tag:Name,Values=$1") ;;
esac

shift

pub_dns=$(jq -r -e '.Reservations?[0]?.Instances?[0]?.PublicDnsName?' <<<"$inst_json")
if [[ -z "$pub_dns" ]] || [[ "$pub_dns" == "null" ]]; then
    die "Instance '$1' does not exist, or have a public DNS address allocated (yet)."
fi

echo "+ $SSH ec2-user@$pub_dns $*" >> /dev/stderr
exec $SSH ec2-user@$pub_dns "$@"
