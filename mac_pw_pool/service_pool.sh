#!/bin/bash

# Launch Cirrus-CI PW Pool listener & manager process.
# Intended to be called once from setup.sh on M1 Macs.
# Expects configuration filepath to be passed as the first argument.
# Expects the number of hours until shutdown (and self-termination)
# as the second argument.

set -o pipefail

msg() { echo "##### ${1:-No message message provided}"; }
die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }

for varname in PWCFG PWUSER PWREADYURL PWREADY; do
    varval="${!varname}"
    [[ -n "$varval" ]] || \
        die "Env. var. \$$varname is unset/empty."
done

[[ "$USER" == "ec2-user" ]] || \
    die "Expecting to execute as 'ec2-user'."

# All operations assume this CWD
cd $HOME

# For whatever reason, when this script is run through ssh, the default
# environment isn't loaded automatically.
. /etc/profile

# This can be leftover under certain conditions
# shellcheck disable=SC2154
sudo pkill -u $PWUSER -f "cirrus worker run" || true

# Configuring a launchd agent to run the worker process is a major
# PITA and seems to require rebooting the instance.  Work around
# this with a really hacky loop masquerading as a system service.
# envar exported to us
# shellcheck disable=SC2154
while [[ -r $PWCFG ]] && [[ "$PWREADY" == "true" ]]; do  # Remove file or change tag to shutdown this "service"
    # The $PWUSER has access to kill it's own listener, or it could crash.
    if ! pgrep -u $PWUSER -f -q "cirrus worker run"; then
        # FIXME: CI Tasks will execute as $PWUSER and ordinarily would have
        # read access to $PWCFG file containing $POOLTOKEN.  While not
        # disastrous, it's desirable to not leak potentially sensitive
        # values.  Work around this by keeping the file unreadable by
        # $PWUSER except for a brief period while starting up.
        sudo chmod 0644 $PWCFG
        msg "$(date -u -Iseconds) Starting PW pool listener as $PWUSER"
        # This is intended for user's setup.log
        # shellcheck disable=SC2024
        sudo su -l $PWUSER -c "/opt/homebrew/bin/cirrus worker run --file $PWCFG &" >>setup.log 2>&1 &
        sleep 10  # eek!
        sudo chmod 0600 $PWCFG
    fi

    # This can fail on occasion for some reason
    # envar exported to us
    # shellcheck disable=SC2154
    if ! PWREADY=$(curl -sSLf $PWREADYURL); then
        PWREADY="recheck"
    fi

    # Avoid re-launch busy-wait
    sleep 10

    # Second-chance
    if [[ "$PWREADY" == "recheck" ]] && ! PWREADY=$(curl -sSLf $PWREADYURL); then
        msg "Failed twice to obtain PWPoolReady instance tag.  Disabling listener."
        rm -f "$PWCFG"
        break
    fi
done

set +e

msg "Configuration file not readable; PWPoolReady tag '$PWREADY'."
msg "Terminating $PWUSER PW pool listner process"
# N/B: This will _not_ stop the cirrus agent (i.e. a running task)
sudo pkill -u $PWUSER -f "cirrus worker run"
