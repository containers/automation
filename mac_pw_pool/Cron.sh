#!/bin/bash

# Intended to be run from $HOME/deve/automation/mac_pw_pool/
# using a crontab like:

# # Every date/timestamp in PW Pool management is UTC-relative
# # make cron do the same for consistency.
# CRON_TZ=UTC
#
# PATH=/home/shared/.local/bin:/home/shared/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin
#
# # Keep log from filling up disk & make sure webserver is running
# # (5am UTC is during CI-activity lul)
# 59   4    * * * $HOME/devel/automation/mac_pw_pool/nightly_maintenance.sh &>> $CRONLOG
#
# # PW Pool management (usage drop-off from 03:00-15:00 UTC)
# POOLTOKEN=<from https://cirrus-ci.com/pool/1cf8c7f7d7db0b56aecd89759721d2e710778c523a8c91c7c3aaee5b15b48d05>
# CRONLOG=/home/shared/devel/automation/mac_pw_pool/Cron.log
# */5  *    * * * /home/shared/devel/automation/mac_pw_pool/Cron.sh &>> $CRONLOG

# shellcheck disable=SC2154
[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -e -w 300 "$0" "$0" "$@" || :

# shellcheck source=./pw_lib.sh
source $(dirname "${BASH_SOURCE[0]}")/pw_lib.sh

cd $SCRIPT_DIRPATH || die "Cannot enter '$SCRIPT_DIRPATH'"

# SSH agent required to provide key for accessing workers
# Started with `ssh-agent -s > /run/user/$UID/ssh-agent.env`
# followed by adding/unlocking the necessary keys.
# shellcheck disable=SC1090
source /run/user/$UID/ssh-agent.env

date -u -Iminutes
now_minutes=$(date -u +%M)

if (($now_minutes%10==0)); then
    $SCRIPT_DIRPATH/LaunchInstances.sh
    echo "Exit: $?"
fi

$SCRIPT_DIRPATH/SetupInstances.sh
echo "Exit: $?"

[[ -r "$PWSTATE" ]] || \
    die "Can't read $PWSTATE to generate utilization data."

uzn_file="$SCRIPT_DIRPATH/utilization.csv"
# Run input through `date` to validate values are usable timestamps
timestamp=$(date -u -Iseconds -d \
              $(grep -E '^# SetupInstances\.sh run ' "$PWSTATE" | \
                awk '{print $4}'))
pw_state=$(grep -E -v '^($|#+| +)' "$PWSTATE")
n_workers=$(grep 'complete alive' <<<"$pw_state" | wc -l)
n_tasks=$(awk "BEGIN{B=0} /${DH_PFX}-[0-9]+ complete alive/{B+=\$4} END{print B}" <<<"$pw_state")
n_taskf=$(awk "BEGIN{E=0} /${DH_PFX}-[0-9]+ complete alive/{E+=\$5} END{print E}" <<<"$pw_state")
printf "%s,%i,%i,%i\n" "$timestamp" "$n_workers" "$n_tasks" "$n_taskf" | tee -a "$uzn_file"

# Prevent uncontrolled growth of utilization.csv.  Assume this script
# runs every $interval minutes, keep only $history_hours worth of data.
interval_minutes=5
history_hours=36
lines_per_hour=$((60/$interval_minutes))
max_uzn_lines=$(($history_hours * $lines_per_hour))
tail -n $max_uzn_lines "$uzn_file" > "${uzn_file}.tmp"
mv "${uzn_file}.tmp" "$uzn_file"

# If possible, generate the webpage utilization graph
gnuplot -c Utilization.gnuplot || true
