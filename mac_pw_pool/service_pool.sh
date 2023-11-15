#!/bin/bash

# Launch Cirrus-CI PW Pool listener & manager process.
# Intended to be called once from setup.sh on M1 Macs.
# Expects configuration filepath to be passed as the first argument.

set -eo pipefail

msg() { echo "##### ${1:-No message message provided}"; }
die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }

msg "Listener started at $(date -u -Iseconds)"

[[ "$USER" == "ec2-user" ]] || \
    die "Expecting to execute as 'ec2-user'."

[[ -r "$1" ]] || \
    die "Can't read configuration file '$1'"

# For whatever reason, when this script is run through ssh, the default
# environment isn't loaded automatically.
. /etc/profile

PWINST=$(curl -sSLf http://instance-data/latest/meta-data/tags/instance/Name)
PWUSER=$PWINST-worker
[[ -n "$PWINST" ]] || \
    die "Unexpectedly empty instance name, is metadata tag access enabled?"

PWCFG="$1"

# CI effectively allows unmitigated access to run or host any
# process or content on this instance as $PWUSER.  Limit the
# potential blast-radius of any nefarious use by restricting
# the lifetime of the instance.  If this ends up disturbing
# a running task, Cirrus will automatically retry on another
# available pool instance. Shutdown instance after this many
# hours servicing the pool.  Note: It's randomized slightly
# to prevent instances going down at similar times.
_rndadj=$((RANDOM%8-4))  # +/- 4 hours
PWLIFE=$((24+$_rndadj))

# Configuring a launchd agent to run the worker process is a major
# PITA and seems to require rebooting the instance.  Work around
# this with a really hacky loop masquerading as a system service.
# Run it in the background to allow this setup script to exit.
# N/B: CI tasks have access to kill the pool listener process!
expires=$(($(date -u "+%Y%m%d%H") + $PWLIFE))
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
        sleep 30s  # eek!
        sudo chmod 0600 $PWCFG
    fi

    if [[ $(date -u "+%Y%m%d%H") -ge $expires ]]; then
        msg "$(date -u -Iseconds) Instance expired."
        # Try not to clobber a running Task, unless it's fake.
        if pgrep -u $PWUSER -q "cirrus-ci-agent"; then
            msg "$(date -u -Iseconds) Shutdown paused 2h for apparent in-flight CI task."
            # Cirrus-CI has hard-coded 2-hour max task lifetime
            sleep $(60 * 60 * 2)
            msg "$(date -u -Iseconds) Killing hung or nefarious CI agent older than 2h."
            pkill -u $PWUSER "cirrus-ci-agent"
        fi
        msg "$(date -u -Iseconds) Executing shutdown."
        sudo shutdown -h +1m "Automatic instance recycle after >$PWLIFE hours."
        sleep 120
    fi

    # Avoid re-launch busy-wait
    sleep 60
    msg "$(date -u -Iseconds) Pool listener watcher process tick."
done >> $HOME/setup.log 2>&1
