#!/bin/bash

set -eo pipefail

# Script intended to be executed by humans (and eventually automation)
# to provision any/all accessible Cirrus-CI Persistent Worker instances
# as they become available.  This is intended to operate independently
# from `LaunchInstances.sh` soas to "hide" the nearly 2-hours of cumulative
# startup and termination wait time.  This script depends on:
#
# * The $DHSTATE file created/updated by `LaunchInstances.sh`.
# * All requirements listed in the top `LaunchInstances.sh` comment.
# * The local ssh-agent is able to supply the appropriate private key.
# * The $POOLTOKEN env. var. is defined

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

# Update temporary-dir status file for instance $name
# status type $1 and value $2.  Where status type is
# 'setup', 'listener', 'tasks' or 'comment'.
set_pw_status() {
    [[ -n "$name" ]] || \
        die "Expecting \$name to be set"
    case $1 in
      setup) ;;
      listener) ;;
      tasks) ;;
      comment) ;;
      *) die "Status type must be 'setup', 'listener', 'tasks', or 'comment'"
    esac
    if [[ "$1" != "comment" ]] && [[ -z "$2" ]]; then
        die "Expecting status value to be non-empty."
    fi
    echo -n "$2" > $TEMPDIR/${name}.$1
}

# Wrapper around msg() and warn() which also set_pw_status() comment.
pwst_msg() { set_pw_status comment "$1"; msg "$1"; }
pwst_warn() { set_pw_status comment "$1"; warn "$1"; }

# Set non-zero to enable debugging / prevent removal of temp. dir.
S_DEBUG="${S_DEBUG:0}"
if ((S_DEBUG)); then
    X_DEBUG=1
    warn "Debugging enabled - temp. dir will not be cleaned up '$TEMPDIR' $(ctx 0)."
    trap EXIT
fi

[[ -n "$POOLTOKEN" ]] || \
    die "Expecting \$POOLTOKEN to be defined/non-empty $(ctx 0)."

[[ -r "$DHSTATE" ]] || \
    die "Can't read from state file: $DHSTATE"

declare -a _pwstate
readarray -t _pwstate <<<$(grep -E -v '^($|#+| +)' "$DHSTATE" | sort)
n_inst=0
n_inst_total="${#_dhstate[@]}"
if [[ $n_inst_total -eq 0 ]] || [[ -z "${_dhstate[0]}" ]]; then
    msg "No operable hosts found in $DHSTATE:
$(<$DHSTATE)"
    # Assume this script is running in a loop, and unf. there are
    # simply no dedicated-hosts in 'available' state.
    exit 0
fi

# N/B: Assumes $DHSTATE represents reality
msg "Operating on $n_inst_total instances from $(head -1 $DHSTATE)"
echo -e "# $(basename ${BASH_SOURCE[0]}) run $(date -u -Iseconds)\n#" > "$TEMPDIR/$(basename $PWSTATE)"
# Indent for messages inside loop
for _dhentry in "${_dhstate[@]}"; do
    read -r name instance_id launch_time<<<"$_dhentry"
    _I="    "
    msg " "
    n_inst=$(($n_inst+1))
    msg "Working on Instance #$n_inst/$n_inst_total '$name' with ID '$instance_id'."

    instoutput="$TEMPDIR/${name}_inst.output"
    ncoutput="$TEMPDIR/${name}_nc.output"
    logoutput="$TEMPDIR/${name}_ssh.output"

    # Most operations below 'continue' looping on error.  Ensure status files match.
    for status_type in setup listener tasks; do
        set_pw_status $status_type error
    done
    set_pw_status comment ""

    if ! $AWS ec2 describe-instances --instance-ids $instance_id &> "$instoutput"; then
        pwst_warn "Could not query instance $instance_id $(ctx 0)."
        continue
    fi

    # Check if instance should be managed
    if ! PWPoolReady=$(json_query '.Reservations?[0]?.Instances?[0]?.Tags? | map(select(.Key == "PWPoolReady")) | .[].Value' "$instoutput"); then
        pwst_warn "Instance does not have a PWPoolReady tag"
        PWPoolReady="tag absent"
    fi

    if [[ "$PWPoolReady" != "true" ]]; then
        pwst_msg "Instance disabled via tag 'PWPoolReady' == '$PWPoolReady' != 'true'."
        continue
    fi

    msg "Verifying lifetime <3 days (launched '$launch_time')"
    # It's really important that instances have a defined and risk-relative
    # short lifespan.  Multiple mechanisms are in place to assist, but none
    # are perfect.  Warn operators if any instance has been alive "too long".
    now=$(date -u +%Y%m%d)
    then=$(date -u -d "$launch_time" +%Y%m%d)
    # c/automation_images Cirrus-CI job terminates EC2 instances after 3 days
    [[ $((now-then)) -le 3 ]] || \
        pwst_warn "Excess instance lifetime, please investigate $(ctx 0)"

    msg "Looking up public DNS"
    if ! pub_dns=$(json_query '.Reservations?[0]?.Instances?[0]?.PublicDnsName?' "$instoutput"); then
        pwst_warn "Could not lookup of public DNS for instance $instance_id $(ctx 0)"
        continue
    fi

    msg "Attempting to contact '$name' at $pub_dns"
    if ! nc -z -w 13 $pub_dns 22 &> "$ncoutput"; then
        pwst_warn "Could not connect to port 22 on '$pub_dns' $(ctx 0)."
        continue
    fi

    if ! $SSH ec2-user@$pub_dns true; then
        pwst_warn "Could not ssh to 'ec2-user@$pub_dns' $(ctx 0)."
        continue
    fi

    msg "Checking state of instance"
    if ! $SSH ec2-user@$pub_dns test -r .setup.done; then

        if ! $SSH ec2-user@$pub_dns test -r .setup.started; then
            if $SSH ec2-user@$pub_dns test -r setup.log; then
                pwst_warn "Setup log found, prior executions may have failed $(ctx 0)."
            fi

            pwst_msg "Setting up new instance"

            # Switch to bash for consistency && some ssh commands below
            # don't play nicely with zsh.
            $SSH ec2-user@$pub_dns sudo chsh -s /bin/bash ec2-user &> /dev/null

            if ! $SCP $SETUP_SCRIPT $SPOOL_SCRIPT ec2-user@$pub_dns:/var/tmp/; then
                pwst_warn "Could not scp scripts to instance $(ctx 0)."
                continue
            fi

            if ! $SCP $CIENV_SCRIPT ec2-user@$pub_dns:./; then
                pwst_warn "Could not scp CI Env. script to instance $(ctx 0)."
                continue
            fi

            if ! $SSH ec2-user@$pub_dns chmod +x /var/tmp/*.sh; then
                pwst_warn "Could not chmod scripts $(ctx 0)."
                continue
            fi

            # Run setup script in background b/c it takes ~5-10m to complete.
            $SSH ec2-user@$pub_dns \
                env POOLTOKEN=$POOLTOKEN \
                bash -c '/var/tmp/setup.sh &> setup.log & disown %-1'

            msg "Setup script started"
            set_pw_status setup started

            # Let it run in the background
            continue
        fi

        since=$($SSH ec2-user@$pub_dns tail -1 .setup.started)
        msg "Setup not complete;  Now: $(date -u -Iseconds)"
        pwst_msg "Setup running since:      $since"
        continue
    fi

    msg "Instance setup has completed"
    set_pw_status setup complete

    if ! $SSH ec2-user@$pub_dns pgrep -u "${name}-worker" -f -q "cirrus worker run"; then
        pwst_warn "Cirrus worker listener process is not running $(ctx 0)."
        set_pw_status listener dead
        continue
    fi

    msg "Cirrus worker listener process is running"

    logpath="/private/tmp/${name}-worker.log"  # set in setup.sh
    # The log output from "cirrus worker run" only records task starts
    if ! $SSH ec2-user@$pub_dns "cat $logpath" &> "$logoutput"; then
        pwst_warn "Missing worker log $logpath"
    else
        dbg "worker log:
$(<$logoutput)"
    fi

    # First line of log should always match this
    if ! head -1 "$logoutput" | grep -q 'worker successfully registered'; then
        warn "Expecting successful registration log entry:
$(head -1 "$logoutput")"
        continue
    fi

    msg "Cirrus worker listener successfully registered at least once"
    set_pw_status listener alive

    # Most of the time these are harmless, "can't connect" flakes.
    if grep -Eq 'level=error.+msg.+failed' "$logoutput"; then
        warn "Failure messages present in worker log"
    fi

    # The CI user has write-access to this log file on the instance,
    # make this known to humans in case they care.
    n_tasks=$(grep -Ei 'started' "$logoutput" | wc -l) || true
    msg "Apparent worker task executions: $n_tasks"
    set_pw_status tasks $n_tasks
done

_I=""
msg " "
msg "Processing all persistent worker states."
for _pwentry in "${_pwstate[@]}"; do
    read -r name otherstuff<<<"$_pwentry"
    _f1=$name
    _f2=$(<$TEMPDIR/${name}.setup)
    _f3=$(<$TEMPDIR/${name}.listener)
    _f4=$(<$TEMPDIR/${name}.tasks)
    _f5=$(<$TEMPDIR/${name}.comment)
    [[ -z "$_f5" ]] || _f5=" # $_f5"

    printf '%s %s %s %s%s\n' \
      "$_f1" "$_f2" "$_f3" "$_f4" "$_f5" >> "$TEMPDIR/$(basename $PWSTATE)"
done

dbg "Creating/updating state file"
if [[ -r "$PWSTATE" ]]; then
    cp "$PWSTATE" "${PWSTATE}~"
fi
mv "$TEMPDIR/$(basename $PWSTATE)" "$PWSTATE"
