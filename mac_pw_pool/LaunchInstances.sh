#!/bin/bash

set -eo pipefail

# Script intended to be executed by humans (and eventually automation) to
# ensure instances are launched from the current template version, on all
# available Cirrus-CI Persistent Worker M1 Mac dedicated hosts.  These
# dedicated host (slots) are selected at runtime based their possessing any
# value for the tag `PWPoolReady`.  The script assumes:
#
# * The `aws` CLI tool is installed on $PATH.
# * Appropriate `~/.aws/credentials` credentials are setup.
# * The us-east-1 region is selected in `~/.aws/config`.
#
# N/B: Dedicated Host names and instance names are assumed to be identical,
# only the IDs differ.

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

L_DEBUG="${L_DEBUG:0}"
if ((L_DEBUG)); then
    X_DEBUG=1
    warn "Debugging enabled - temp. dir will not be cleaned up '$TEMPDIR' $(ctx 0)."
    trap EXIT
fi

# Helper intended for use inside `name_hostid` loop.
# arg1 either "INST" or "HOST"
# arg2: Brief failure message
# arg3: Failure message details
handle_failure() {
    [[ -n "$inststate" ]] || die "Expecting \$inststate to be set $(ctx 2)"
    [[ -n "$name" ]] || die "Expecting \$name to be set $(ctx 2)"
    if [[ "$1" != "INST" ]] && [[ "$1" != "HOST" ]]; then
        die "Expecting either INST or HOST as argument $(ctx 2)"
    fi
    [[ -n "$2" ]] || die "Expecting brief failure message $(ctx 2)"
    [[ -n "$3" ]] || die "Expecting detailed failure message $(ctx 2)"

    warn "$2 $(ctx 2)"
    (
        # Script is sensitive to this first-line format
        echo "# $name $1 ERROR: $2"
        # Make it obvious which host/instance the details pertain to
        awk -e '{print "#    "$0}'<<<"$3"
    ) > "$inststate"
}

# Wrapper around handle_failure()
host_failure() {
    [[ -r "$hostoutput" ]] || die "Expecting readable $hostoutput file $(ctx)"
    handle_failure HOST "$1" "aws CLI output: $(<$hostoutput)"
}

inst_failure() {
    [[ -r "$instoutput" ]] || die "Expecting readable $instoutput file $(ctx)"
    handle_failure INST "$1" "aws CLI output: $(<$instoutput)"
}

# Find dedicated hosts to operate on.
dh_flt="Name=tag:Name,Values=MacM1-*"
dh_qry='Hosts[].{HostID:HostId, Name:[Tags[?Key==`Name`].Value][] | [0]}'
dh_searchout="$TEMPDIR/hosts.output"  # JSON or error message
if ! $AWS ec2 describe-hosts --filter "$dh_flt" --query "$dh_qry" &> "$dh_searchout"; then
    die "Searching for dedicated hosts $(ctx 0):
$(<$dh_searchout)"
fi

# Array item format: "<Name> <ID>"
dh_fmt='.[] | .Name +" "+ .HostID'
# Avoid always processing hosts in the same alpha-sorted order, as that would
# mean hosts at the end of the list consistently wait the longest for new
# instances to be created (see creation-stagger code below).
if ! readarray -t NAME2HOSTID <<<$(json_query "$dh_fmt" "$dh_searchout" | sort --random-sort); then
    die "Extracting dedicated host 'Name' and 'HostID' fields $(ctx 0):
$(<$dh_searchout)"
fi

n_dh=0
n_dh_total=${#NAME2HOSTID[@]}
if ! ((n_dh_total)); then
    msg "No dedicated hosts found"
    exit 0
fi

# At maximum possible creation-speed, there's aprox. 3-hours of time between
# an instance going down, until another can be up and running again.  Since
# instances are all on shutdown + self-termination timers, it would hurt
# pool availability if multiple instances all went down at the same time.
# Therefore, instance creations must be staggered by according to this
# window.
CREATE_STAGGER_HOURS=3
latest_launched="1970-01-01T00:00+00:00"  # in case $DHSTATE is missing
dcmpfmt="+%Y%m%d%H%M"  # date comparison format compatible with numeric 'test'
# To find the latest instance launch time, script can't rely on reading
# $DHSTATE or $PWSTATE because they may not exist or be out of date.
# Search for all running instances by name and running state, returning
# their launch timestamps.
declare -a pw_filt
pw_filts=(
  'Name=tag:Name,Values=MacM1-*'
  'Name=tag:PWPoolReady,Values=true'
  'Name=instance-state-name,Values=running'
)
pw_query='Reservations[].Instances[].LaunchTime'
inst_lt_f=$TEMPDIR/inst_launch_times
dbg "Obtaining launch times for all running MacM1-* instances"
dbg "$AWS ec2 describe-instances --filters '${pw_filts[*]}' --query '$pw_query' &> '$inst_lt_f'"
if ! $AWS ec2 describe-instances --filters "${pw_filts[@]}" --query "$pw_query" &> "$inst_lt_f"; then
    die "Can not query instances:
$(<$inst_lt_f)"
else
    declare -a launchtimes
    if ! readarray -t launchtimes<<<$(json_query '.[]?' "$inst_lt_f") ||
       [[ "${#launchtimes[@]}" -eq 0 ]] ||
       [[ "${launchtimes[0]}" == "" ]]; then
        warn "Found no running instances, this should not happen."
    else
        dbg "launchtimes=[${launchtimes[*]}]"
        for launch_time in "${launchtimes[@]}"; do
            # Assume launch_time is never malformed
            launched_hour=$(date -u -d "$launch_time" "$dcmpfmt")
            latest_launched_hour=$(date -u -d "$latest_launched" "$dcmpfmt")
            dbg "instance launched on $launched_hour; latest launch hour: $latest_launched_hour"
            if [[ $launched_hour -gt $latest_launched_hour ]]; then
                dbg "Updating latest launched timestamp"
                latest_launched="$launch_time"
            fi
        done
    fi
fi

# Increase readability for humans by always ensuring the two important
# date stamps line up regardless of the length of $n_dh_total.
_n_dh_sp=$(printf ' %.0s' seq 1 ${#n_dh_total})
msg "Operating on $n_dh_total dedicated hosts at $(date -u -Iseconds)"
msg "       ${_n_dh_sp}Last instance launch on $latest_launched"
echo -e "# $(basename ${BASH_SOURCE[0]}) run $(date -u -Iseconds)\n#" > "$TEMPDIR/$(basename $DHSTATE)"

for name_hostid in "${NAME2HOSTID[@]}"; do
    n_dh=$(($n_dh+1))
    _I="    "
    msg " "  # make output easier to read

    read -r name hostid<<<"$name_hostid"
    msg "Working on Dedicated Host #$n_dh/$n_dh_total '$name' for HostID '$hostid'."

    hostoutput="$TEMPDIR/${name}_host.output" # JSON or error message from aws describe-hosts
    instoutput="$TEMPDIR/${name}_inst.output" # JSON or error message from aws describe-instance or run-instance
    inststate="$TEMPDIR/${name}_inst.state"  # Line to append to $DHSTATE

    if ! $AWS ec2 describe-hosts --host-ids $hostid &> "$hostoutput"; then
        host_failure "Failed to look up dedicated host."
        continue
    # Allow hosts to be taken out of service easily/manually by editing its tags.
    # Also detect any JSON parsing problems in the output.
    elif ! PWPoolReady=$(json_query '.Hosts?[0]?.Tags? | map(select(.Key == "PWPoolReady")) | .[].Value' "$hostoutput"); then
        host_failure "Empty/null/failed JSON query of PWPoolReady tag."
        continue
    elif [[ "$PWPoolReady" != "true" ]]; then
        msg "Dedicated host tag 'PWPoolReady' == '$PWPoolReady' != 'true'."
        echo "# $name HOST DISABLED: PWPoolReady==$PWPoolReady" > "$inststate"
        continue
    fi

    if ! hoststate=$(json_query '.Hosts?[0]?.State?' "$hostoutput"); then
        host_failure "Empty/null/failed JSON query of dedicated host state."
        continue
    fi

    if [[ "$hoststate" == "pending" ]] || [[ "$hoststate" == "under-assessment" ]]; then
        # When an instance is terminated, its dedicated host goes into an unusable state
        # for about 1-1/2 hours.  There's absolutely nothing that can be done to avoid
        # this or work around it.  Ignore hosts in this state, assuming a later run of the
        # script will start an instance on the (hopefully) available host).
        #
        # I have no idea what 'under-assessment'  means, and it doesn't last as long as 'pending',
        # but functionally it behaves the same.
        msg "Dedicated host is untouchable due to '$hoststate' state."
        # Reference the actual output text, in case of false-match or unexpected contents.
        echo "# $name HOST BUSY: $hoststate" > "$inststate"
        continue
    elif [[ "$hoststate" != "available" ]]; then
        # The "available" state means the host is ready for zero or more instances to be created.
        # Detect all other states (they should be extremely rare).
        host_failure "Unsupported dedicated host state '$hoststate'."
        continue
    fi

    # Counter-intuitively, dedicated hosts can support more than one running instance.  Except
    # for Mac instances, but this is not reflected anywhere in the JSON.  Trying to start a new
    # Mac instance on an already occupied host is bound to fail.  Inconveniently this error
    # will look an aweful lot like many other types of errors, confusing any human examining
    # $DHSTATE.  Detect dedicated-hosts with existing instances.
    InstanceId=$(set +e; jq -r '.Hosts?[0]?.Instances?[0].InstanceId?' "$hostoutput")
    dbg "InstanceId='$InstanceId'"

    # Stagger creation of instances by $CREATE_STAGGER_HOURS
    launch_new=0
    if [[ "$InstanceId" == "null" ]] || [[ "$InstanceId" == "" ]]; then
      launch_threshold=$(date -u -Iseconds -d "$latest_launched + $CREATE_STAGGER_HOURS hours")
      launch_threshold_hour=$(date -u -d "$launch_threshold" "$dcmpfmt")
      now_hour=$(date -u "$dcmpfmt")
      dbg "launch_threshold_hour=$launch_threshold_hour"
      dbg "             now_hour=$now_hour"
      if [[ $now_hour -lt $launch_threshold_hour ]]; then
          msg "Cannot launch new instance until $launch_threshold"
          echo "# $name HOST THROTTLE: Inst. creation delayed until $launch_threshold" > "$inststate"
          continue
      else
          launch_new=1
      fi
    fi

    if ((launch_new)); then
        msg "Creating new instance on host."
        if ! $AWS ec2 run-instances \
                  --launch-template LaunchTemplateName=CirrusMacM1PWinstance \
                  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$name}]" \
                  --placement "HostId=$hostid" &> "$instoutput"; then
            inst_failure "Failed to create new instance on available host."
            continue
        else
            # Block further launches (assumes script is running in a 10m while loop).
            latest_launched=$(date -u -Iseconds)
            msg "Successfully created new instance; Waiting for 'running' state (~1m typical)..."
            # N/B: New Mac instances take ~5-10m to actually become ssh-able
            if ! InstanceId=$(json_query '.Instances?[0]?.InstanceId' "$instoutput"); then
                inst_failure "Empty/null/failed JSON query of brand-new InstanceId"
                continue
            fi
            # Instance "running" status is good enough for this script, and since network
            # accessibility can take 5-20m post creation.
            # Polls 40 times with 15-second delay (non-configurable).
            if ! $AWS ec2 wait instance-running \
                    --instance-ids $InstanceId &> "${instoutput}.wait"; then
                # inst_failure() would include unhelpful $instoutput detail
                (
                    echo "# $name INST ERROR: Running-state timeout."
                    awk -e '{print "#    "$0}' "${instoutput}.wait"
                ) > "$inststate"
                continue
            fi
        fi
    fi

    # If an instance was created, $instoutput contents are already obsolete.
    # If an existing instance, $instoutput doesn't exist.
    if ! $AWS ec2 describe-instances --instance-ids $InstanceId &> "$instoutput"; then
        inst_failure "Failed to describe host instance."
        continue
    fi

    # Describe-instance has unnecessarily complex structure, simplify it.
    if ! json_query '.Reservations?[0]?.Instances?[0]?' "$instoutput" > "${instoutput}.simple"; then
        inst_failure "Empty/null/failed JSON simplification of describe-instances."
    fi
    mv "$instoutput" "${instoutput}.describe"  # leave for debugging
    mv "${instoutput}.simple" "${instoutput}"

    msg "Parsing new or existing instance ($InstanceId) details."
    if ! InstanceId=$(json_query '.InstanceId' $instoutput); then
        inst_failure "Empty/null/failed JSON query of InstanceId"
        continue
    elif ! LaunchTime=$(json_query '.LaunchTime' $instoutput); then
        inst_failure "Empty/null/failed JSON query of LaunchTime"
        continue
    fi

    echo "$name $InstanceId $LaunchTime" > "$inststate"
done

_I=""
msg " "
msg "Processing all dedicated host and instance states."
# Consuming state file in alpha-order is easier on human eyes
readarray -t NAME2HOSTID <<<$(json_query "$dh_fmt" "$dh_searchout" | sort)
for name_hostid in "${NAME2HOSTID[@]}"; do
    read -r name hostid<<<"$name_hostid"
    inststate="$TEMPDIR/${name}_inst.state"
    [[ -r "$inststate" ]] || \
        die "Expecting to find instance-state file $inststate for host '$name' $(ctx 0)."
    cat "$inststate" >> "$TEMPDIR/$(basename $DHSTATE)"
done

dbg "Creating/updating state file"
if [[ -r "$DHSTATE" ]]; then
    cp "$DHSTATE" "${DHSTATE}~"
fi
mv "$TEMPDIR/$(basename $DHSTATE)" "$DHSTATE"
