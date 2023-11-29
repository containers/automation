#!/bin/bash

# Setup and launch Cirrus-CI PW Pool node.  It must be called
# with the env. var. `$POOLTOKEN` set.  It is assumed to be
# running on a fresh AWS EC2 mac2.metal instance as `ec2-user`
# The instance must have both "metadata" and "Allow tags in
# metadata" options enabled.  The instance must set the
# "terminate" option for "shutdown behavior".
#
# Script accepts a single argument: The number of hours to
# delay self-termination (including 0).

set -eo pipefail

GVPROXY_RELEASE_URL="https://github.com/containers/gvisor-tap-vsock/releases/latest/download/gvproxy-darwin"

COMPLETION_FILE="$HOME/.setup.done"
STARTED_FILE="$HOME/.setup.started"

date -u -Iseconds >> "$STARTED_FILE"

msg() { echo "##### ${1:-No message message provided}"; }
die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }

[[ -n "$POOLTOKEN" ]] || \
    die "Must be called with non-empty \$POOLTOKEN set."

[[ ! -r "$COMPLETION_FILE" ]] || \
    die "Appears setup script already ran at '$(cat $COMPLETION_FILE)'.  This script should not be called twice by automation."

[[ "$USER" == "ec2-user" ]] || \
    die "Expecting to execute as 'ec2-user'."

msg "Configuring paths"
grep -q homebrew /etc/paths || \
    echo -e "/opt/homebrew/bin\n/opt/homebrew/opt/coreutils/libexec/gnubin\n$(cat /etc/paths)" \
        | sudo tee /etc/paths > /dev/null

# For whatever reason, when this script is run through ssh, the default
# environment isn't loaded automatically.
. /etc/profile

msg "\$PATH=$PATH"

msg "Installing podman-machine, testing, and CI deps. (~2m install time)"
if [[ ! -x /usr/local/bin/gvproxy ]]; then
    brew tap cfergeau/crc
    brew install go go-md2man coreutils pstree vfkit cirruslabs/cli/cirrus

    # Normally gvproxy is installed along with "podman" brew.  CI Tasks
    # on this instance will be running from source builds, so gvproxy must
    # be install from upstream release.
    curl -sSLfO "$GVPROXY_RELEASE_URL"
    sudo install -o root -g staff -m 0755 gvproxy-darwin /usr/local/bin/gvproxy
    rm gvproxy-darwin
fi

msg "Adding/Configuring PW User"
# Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
PWINST=$(curl -sSLf http://instance-data/latest/meta-data/tags/instance/Name)
PWUSER=$PWINST-worker
[[ -n "$PWINST" ]] || \
    die "Unexpectedly empty instance name, is metadata tag access enabled?"

PWCFG=$(mktemp /private/tmp/${PWINST}_cfg_XXXXXXXX)
PWLOG="/private/tmp/${PWUSER}.log"

# Make host easier to identify from CI logs (default is some
# random internal EC2 dns name).  Doesn't need to survive a
# reboot.
if [[ "$(uname -n)" != "$PWINST" ]]; then
    sudo hostname $PWINST
    sudo scutil --set HostName $PWINST
    sudo scutil --set ComputerName $PWINST
fi

# CI effectively allows unmitigated access to run, kill,
# or host any process or content on this instance as $PWUSER.
# Limit the potential blast-radius of any nefarious use by
# restricting the lifetime of the instance.  If this ends up
# disturbing a running task, Cirrus will automatically retry
# on another available pool instance. If none are available,
# the task will queue indefinitely.
#
# Note: It takes about 3-hours total until a new instance can
# be up/running in this one's place.
#
# Shutdown (and self-terminate instance after the number of hours
# set below.  This value may be extended by 2 more hours
# (see `service_pool.sh`).
#
# * Increase value to improve instance CI-utilization.
# * Reduce value to lower instability & security risk.
# * Additional hours argument is optional.
PWLIFE=$((22+${1:-0}))

if ! id "$PWUSER" &> /dev/null; then
    sudo sysadminctl -addUser $PWUSER

    # User can't remove own pre-existing homedir crap during cleanup
    sudo rm -rf /Users/$PWUSER/*
    sudo rm -rf /Users/$PWUSER/.??*
fi

# FIXME: Semi-secret POOLTOKEN value should not be in this file.
# ref: https://github.com/cirruslabs/cirrus-cli/discussions/662
cat << EOF | sudo tee $PWCFG > /dev/null
---
name: "$PWINST"
token: "$POOLTOKEN"
log:
  file: "${PWLOG}"
security:
  allowed-isolations:
    none: {}
EOF
sudo chown ${USER}:staff $PWCFG

# Log file is examined by the worker process launch script.
# Ensure it exists and $PWUSER has access to it.
touch $PWLOG
sudo chown ${USER}:staff $PWLOG
sudo chmod g+rw $PWLOG

if ! pgrep -q -f service_pool.sh; then
    msg "Starting listener supervisor process w/ ${PWLIFE}hour lifetime"
    /var/tmp/service_pool.sh "$PWCFG" "$PWLIFE" >> "${PWLOG}" &
    disown %-1
else
    msg "Warning: Listener supervisor already running"
fi

# Allow other tooling to detect this script has run successfully to completion
date -u -Iseconds >> "$COMPLETION_FILE"
