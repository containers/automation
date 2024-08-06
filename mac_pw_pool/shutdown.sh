#!/bin/bash

# Script intended to be called by automation only.
# Should never be called from any other context.

# Log on the off-chance it somehow helps somebody debug something one day
(

echo "Starting ${BASH_SOURCE[0]} at $(date -u -Iseconds)"

PWNAME=$(uname -n)
PWUSER=$PWNAME-worker

if id -u "$PWUSER" &> /dev/null; then
    # Try to not reboot while a CI task is running.
    # Cirrus-CI imposes a hard-timeout of 2-hours.
    now=$(date -u +%s)
    timeout_at=$((now+60*60*2))
    echo "Waiting up to 2 hours for any pre-existing cirrus agent (i.e. running task)"
    while pgrep -u $PWUSER -q -f "cirrus-ci-agent"; do
        if [[ $(date -u +%s) -gt $timeout_at ]]; then
            echo "Timeout waiting for cirrus-ci-agent to terminate"
            break
        fi
        echo "Found cirrus-ci-agent still running, waiting..."
        sleep 60
    done
fi

echo "Initiating shutdown at $(date -u -Iseconds)"

# This script is run with a sleep in front of it
# as a workaround for darwin's shutdown-command
# terminal weirdness.

sudo shutdown -h now "Automatic instance recycling"

) < /dev/null >> setup.log 2>&1
