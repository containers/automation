#!/bin/bash

set -eo pipefail

# This scripts is intended to wrap commands which occasionally fail due
# to external factors like networking hiccups, service failover, load-balancing,
# etc.  It is not designed to handle operational failures gracefully, such as
# bad (wrapped) command-line arguments, running out of local disk-space,
# authZ/authN, etc.

# Assume script was installed or is running in dir struct. matching repo layout.
AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(dirname ${BASH_SOURCE[0]})/../lib}"
source "$AUTOMATION_LIB_PATH/anchors.sh"
source "$AUTOMATION_LIB_PATH/console_output.sh"

usage(){
    local errmsg="$1"  # optional
    dbg "Showing usage with errmsg='$errmsg'"
    msg "
Usage: $SCRIPT_FILENAME [[attempts] [[sleep] [exit...]]] <--> <command> [arg...]
Arguments:
    attempts       Total number of times to attempt <command>. Default is 3.
    sleep          Milliseconds to sleep between retry attempts, doubling
                   duration each failure except the last. Must also specify
                   [attempts]. Default is 1 second
    exit...        One or more exit code values to consider as failure.
                   Must also specify [attempts] and [sleep].  Default is any
                   non-zero exit.  N/B: Multiple values must be quoted!
    --             Required separator between any / no options, and command
    command        Path to command to execute, cannot use a shell builtin.
    arg...         Options and/or arguments to pass to command.
"
    [[ -n "$errmsg" ]] || \
        die "$errmsg"  # exits non-zero
}

attempts=3
sleep_ms=1000
declare -a exit_codes
declare -a args=("$@")

n=1
for arg in attempts sleep_ms exit_codes; do
    if [[ "$arg" == "--" ]]; then
        shift
        break
    fi
    declare "$arg=${args[n]}"
    shift
    n=$[n+1]
done

((attempts>0)) || \
    usage "The number of retry attempts must be greater than 1, not '$attempts'"

((sleep_ms>10)) || \
    usage "The number of milliseconds must be greater than 10, not '$sleep_ms'"

for exit_code in "${exit_codes[@]}"; do
    if ((exit_code<0)) || ((exit_code>254)); then
        usage "Every exit code must be between 0-254, no '$exit_code'"
    fi
done

[[ -n "$@" ]] || \
    usage "Must specify a command to execute"

err_retry "$attempts" "$sleep_ms" "${exit_codes[@]}" "$@"
