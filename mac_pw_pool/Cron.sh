#!/bin/bash

# Intended to be run from a crontab entry like:
#
# PW Pool management
# POOLTOKEN=<token value>
# CRONLOG=/path/to/write/Cron.log
# */5  *    * * * /path/to/run/Cron.sh &>> $CRONLOG
# 59   0    * * * tail -n 10000 $CRONLOG > ${CRONLOG}.tmp && mv ${CRONLOG}.tmp $CRONLOG

# shellcheck disable=SC2154
[ "${FLOCKER}" != "$0" ] && exec env FLOCKER="$0" flock -w 300 "$0" "$0" "$@" || :

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
n_tasks=$(awk 'BEGIN{B=0} /MacM1-[0-9]+ complete alive/{B+=$4} END{print B}' <<<"$pw_state")
n_taskf=$(awk 'BEGIN{E=0} /MacM1-[0-9]+ complete alive/{E+=$5} END{print E}' <<<"$pw_state")
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

# Try to run webserver if possible.
if ! podman container exists util_nginx; then
  podman run -it -d --rm --name util_nginx \
    -p 8080:80 --security-opt label=disable \
    -v $SCRIPT_DIRPATH/html:/usr/share/nginx/html:ro \
    nginx || true
fi
