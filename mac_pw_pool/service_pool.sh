#!/bin/bash

# Launch Cirrus-CI PW Pool listener & manager process.
# Intended to be called once from setup.sh on M1 Macs.
# Expects configuration filepath to be passed as the first argument.
# Expects the number of hours until shutdown (and self-termination)
# as the second argument.

set -eo pipefail

msg() { echo "##### ${1:-No message message provided}"; }
die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }

msg "Listener started at $(date -u -Iseconds)"

[[ "$USER" == "ec2-user" ]] || \
    die "Expecting to execute as 'ec2-user'."

[[ -r "$1" ]] || \
    die "Can't read configuration file '$1'"

[[ -n "$2" ]] || \
    die "Expecting shutdown delay hours as second argument"

# For whatever reason, when this script is run through ssh, the default
# environment isn't loaded automatically.
. /etc/profile

PWINST=$(curl -sSLf http://instance-data/latest/meta-data/tags/instance/Name)
PWUSER=$PWINST-worker
[[ -n "$PWINST" ]] || \
    die "Unexpectedly empty instance name, is metadata tag access enabled?"

PWCFG="$1"
PWLIFE="$2"

# Configuring a launchd agent to run the worker process is a major
# PITA and seems to require rebooting the instance.  Work around
# this with a really hacky loop masquerading as a system service.
# Run it in the background to allow this setup script to exit.
# N/B: CI tasks have access to kill the pool listener process!
expires=$(date -u "+%Y%m%d%H" -d "+$PWLIFE hours")
# N/B: The text below is greped for by SetupInstances.sh
msg "$(date -u -Iseconds): Automatic instance recycle after $(date -u -Iseconds -d "+$PWLIFE hours")"
while [[ -r $PWCFG ]]; do
    # Don't start new pool listener if it or a CI agent process exist
    if ! pgrep -u $PWUSER -f -q "cirrus worker run" && ! pgrep -u $PWUSER -q "cirrus-ci-agent"; then
        # FIXME: CI Tasks will execute as $PWUSER and ordinarily would have
        # read access to config. file containing $POOLTOKEN.  While not
        # disastrous, it's desirable to not leak possibly sensitive
        # values.  Work around this by keeping the file unreadable by
        # $PWUSER except for a brief period while starting up.
        sudo chmod 0644 $PWCFG
        msg "$(date -u -Iseconds) Starting PW pool listener as $PWUSER"
        sudo su -l $PWUSER -c "/opt/homebrew/bin/cirrus worker run --file $PWCFG &"
        sleep 10  # eek!
        sudo chmod 0600 $PWCFG
    fi

    if [[ $(date -u "+%Y%m%d%H") -ge $expires ]]; then
        msg "$(date -u -Iseconds) Instance expired."
        # Block pickup of new jobs
        sudo pkill -u $PWUSER -f "cirrus worker run"
        # Try not to clobber a running Task, unless it's fake.
        if pgrep -u $PWUSER -q "cirrus-ci-agent"; then
            msg "$(date -u -Iseconds) Shutdown paused 2h for apparent in-flight CI task."
            # Cirrus-CI has hard-coded 2-hour max task lifetime
            sleep $(60 * 60 * 2)
            msg "$(date -u -Iseconds) Killing hung or nefarious CI agent older than 2h."
            sudo pkill -u $PWUSER "cirrus-ci-agent"
        fi
        msg "$(date -u -Iseconds) Executing shutdown."
        sudo shutdown -h +1m "Automatic instance recycle after >$PWLIFE hours."
        sleep 10
    fi

    # Avoid re-launch busy-wait
    sleep 60
    msg "$(date -u -Iseconds) Pool listener watcher process tick."
done >> $HOME/setup.log 2>&1
