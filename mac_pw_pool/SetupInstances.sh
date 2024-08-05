#!/bin/bash

set -eo pipefail

# Script intended to be executed by humans (and eventually automation)
# to provision any/all accessible Cirrus-CI Persistent Worker instances
# as they become available.  This is intended to operate independently
# from `LaunchInstances.sh` soas to "hide" the nearly 2-hours of cumulative
# startup and termination wait times.  This script depends on:
#
# * All requirements listed in the top `LaunchInstances.sh` comment.
# * The $DHSTATE file created/updated by `LaunchInstances.sh`.
# * The $POOLTOKEN env. var. is defined
# * The local ssh-agent is able to supply the appropriate private key.

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

# Update temporary-dir status file for instance $name
# status type $1 and value $2.  Where status type is
# 'setup', 'listener', 'tasks', 'taskf' or 'comment'.
set_pw_status() {
    [[ -n "$name" ]] || \
        die "Expecting \$name to be set"
    case $1 in
      setup) ;;
      listener) ;;
      tasks) ;;  # started
      taskf) ;;  # finished
      ftasks) ;;
      comment) ;;
      *) die "Status type must be 'setup', 'listener', 'tasks', 'taskf' or 'comment'"
    esac
    if [[ "$1" != "comment" ]] && [[ -z "$2" ]]; then
        die "Expecting comment text (status argument) to be non-empty."
    fi
    echo -n "$2" > $TEMPDIR/${name}.$1
}

# Wrapper around msg() and warn() which also set_pw_status() comment.
pwst_msg() { set_pw_status comment "$1"; msg "$1"; }
pwst_warn() { set_pw_status comment "$1"; warn "$1"; }

# Attempt to signal $SPOOL_SCRIPT to stop picking up new CI tasks but
# support PWPoolReady being reset to 'true' in the future to signal
# a new $SETUP_SCRIPT run.  Cancel future $SHDWN_SCRIPT action.
# Requires both $pub_dns and $name are set
stop_listener(){
    dbg "Attempting to stop pool listener and reset setup state"
    $SSH ec2-user@$pub_dns rm -f \
        "/private/tmp/${name}_cfg_*" \
        "./.setup.done" \
        "./.setup.started" \
        "/var/tmp/shutdown.sh"
}

# Forcibly shutdown an instance immediately, printing warning and status
# comment from first argument.  Requires $name, $instance_id, and $pub_dns
# to be set.
force_term(){
    local varname
    local termoutput
    termoutput="$TEMPDIR/${name}_term.output"
    local term_msg
    term_msg="${1:-no inst_panic() message provided} Terminating immediately! $(ctx)"

    for varname in name instance_id pub_dns; do
        [[ -n "${!varname}" ]] || \
           die "Expecting \$$varname to be set/non-empty."
    done

    # $SSH has built-in -n; ignore failure, inst may be in broken state already
    echo "$term_msg" | ssh $SSH_ARGS ec2-user@$pub_dns sudo wall || true
    # Set status and print warning message
    pwst_warn "$term_msg"

    # Instance is going to be terminated, immediately stop any attempts to
    # restart listening for jobs.  Ignore failure if unreachable for any reason -
    # we/something else could have already started termination previously
    stop_listener || true

    # Termination can take a few minutes, block further use of instance immediately.
    $AWS ec2 create-tags --resources $instance_id --tags "Key=PWPoolReady,Value=false" || true

    # Prefer possibly recovering a broken pool over debug-ability.
    if ! $AWS ec2 terminate-instances --instance-ids $instance_id &> "$termoutput"; then
        # Possible if the instance recently/previously started termination process.
        warn "Could not terminate instance $instance_id $(ctx 0):
$(<$termoutput)"
    fi
}

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

if [[ -z "$SSH_AUTH_SOCK" ]] || [[ -z "$SSH_AGENT_PID" ]]; then
    die "Cannot access an ssh-agent.  Please run 'ssh-agent -s > /run/user/$UID/ssh-agent.env' and 'ssh-add /path/to/required/key'."
fi

declare -a _dhstate
readarray -t _dhstate <<<$(grep -E -v '^($|#+| +)' "$DHSTATE" | sort)
n_inst=0
n_inst_total="${#_dhstate[@]}"
if [[ -z "${_dhstate[*]}" ]] || ! ((n_inst_total)); then
    msg "No operable hosts found in $DHSTATE:
$(<$DHSTATE)"
    # Assume this script is running in a loop, and unf. there are
    # simply no dedicated-hosts in 'available' state.
    exit 0
fi

# N/B: Assumes $DHSTATE represents reality
msg "Operating on $n_inst_total instances from $(head -1 $DHSTATE)"
echo -e "# $(basename ${BASH_SOURCE[0]}) run $(date -u -Iseconds)\n#" > "$TEMPDIR/$(basename $PWSTATE)"

# Previous instance state needed for some optional checks
declare -a _pwstate
n_pw_total=0
if [[ -r "$PWSTATE" ]]; then
    readarray -t _pwstate <<<$(grep -E -v '^($|#+| +)' "$PWSTATE" | sort)
    n_pw_total="${#_pwstate[@]}"
    # Handle single empty-item array
    if [[ -z "${_pwstate[*]}" ]] || ! ((n_pw_total)); then
        _pwstate=()
        _n_pw_total=0
    fi
fi

# Assuming the `--force` option was used to initialize a new pool of
# workers, then instances need to be configured with a self-termination
# shutdown delay.  This ensures future replacement instances creation
# is staggered, soas to maximize overall worker utilization.
term_addtl=0
# shellcheck disable=SC2199
if [[ "$@" =~ --force ]]; then
    warn "Forcing instance creation: Ignoring staggered creation limits."
    term_addtl=1  # Multiples of $CREATE_STAGGER_HOURS to add to shutdown delay
fi

for _dhentry in "${_dhstate[@]}"; do
    read -r name instance_id launch_time junk<<<"$_dhentry"
    _I="    "
    msg " "
    n_inst=$(($n_inst+1))
    msg "Working on Instance #$n_inst/$n_inst_total '$name' with ID '$instance_id'."

    # Clear buffers used for updating status files
    n_started_tasks=0
    n_finished_tasks=0

    instoutput="$TEMPDIR/${name}_inst.output"
    ncoutput="$TEMPDIR/${name}_nc.output"
    logoutput="$TEMPDIR/${name}_log.output"

    # Most operations below 'continue' looping on error.  Ensure status files match.
    set_pw_status tasks 0
    set_pw_status taskf 0
    set_pw_status setup error
    set_pw_status listener error
    set_pw_status comment ""

    if ! $AWS ec2 describe-instances --instance-ids $instance_id &> "$instoutput"; then
        pwst_warn "Could not query instance $instance_id $(ctx 0)."
        continue
    fi

    dbg "Verifying required $DH_REQ_TAG=$DH_REQ_VAL"
    tagq=".Reservations?[0]?.Instances?[0]?.Tags | map(select(.Key == \"$DH_REQ_TAG\")) | .[].Value"
    if ! inst_tag=$(json_query "$tagq" "$instoutput"); then
        pwst_warn "Could not look up instance $DH_REQ_TAG tag"
        continue
    fi

    if [[ "$inst_tag" != "$DH_REQ_VAL" ]]; then
        pwst_warn "Required inst. '$DH_REQ_TAG' tag != '$DH_REQ_VAL'"
        continue
    fi

    dbg "Looking up instance name"
    nameq='.Reservations?[0]?.Instances?[0]?.Tags | map(select(.Key == "Name")) | .[].Value'
    if ! inst_name=$(json_query "$nameq" "$instoutput"); then
        pwst_warn "Could not look up instance Name tag"
        continue
    fi

    if [[ "$inst_name" != "$name" ]]; then
        pwst_warn "Inst. name '$inst_name' != DH name '$name'"
        continue
    fi

    dbg "Looking up public DNS"
    if ! pub_dns=$(json_query '.Reservations?[0]?.Instances?[0]?.PublicDnsName?' "$instoutput"); then
        pwst_warn "Could not lookup of public DNS for instance $instance_id $(ctx 0)"
        continue
    fi

    # It's really important that instances have a defined and risk-relative
    # short lifespan.  Multiple mechanisms are in place to assist, but none
    # are perfect.  Ensure instances running for an excessive time are forcefully
    # terminated as soon as possible from this script.
    launch_epoch=$(date -u -d "$launch_time" +%s)
    now_epoch=$(date -u +%s)
    age_sec=$((now_epoch-launch_epoch))
    hard_max_sec=$((PW_MAX_HOURS*60*60*2))  # double PW_MAX_HOURS
    dbg "launch_epoch=$launch_epoch"
    dbg "   now_epoch=$now_epoch"
    dbg "     age_sec=$age_sec"
    dbg "hard_max_sec=$hard_max_sec"
    msg "Instance alive for $((age_sec/60/60)) hours (max $PW_MAX_HOURS)"
    if [[ $age_sec -gt $hard_max_sec ]]; then
        force_term "Excess instance lifetime (+$((age_sec-hard_max_sec))s)"
        continue
    fi

    dbg "Attempting to contact '$name' at $pub_dns"
    if ! nc -z -w 13 $pub_dns 22 &> "$ncoutput"; then
        pwst_warn "Could not connect to port 22 on '$pub_dns' $(ctx 0)."
        continue
    fi

    if ! $SSH ec2-user@$pub_dns true; then
        pwst_warn "Could not ssh to 'ec2-user@$pub_dns' $(ctx 0)."
        continue
    fi

    dbg "Check if instance should be managed"
    if ! PWPoolReady=$(json_query '.Reservations?[0]?.Instances?[0]?.Tags? | map(select(.Key == "PWPoolReady")) | .[].Value' "$instoutput"); then
        pwst_warn "Instance does not have a PWPoolReady tag"
        PWPoolReady="absent"
    fi

    # Mechanism for a developer to manually debug operations w/o fear of new tasks or instance shutdown.
    if [[ "$PWPoolReady" != "true" ]]; then
        pwst_msg "Instance disabled via tag 'PWPoolReady' == '$PWPoolReady'."
        set_pw_status setup disabled
        set_pw_status listener disabled
        (
            set +e  # All commands below are best-effort only!
            dbg "Attempting to stop any pending shutdowns"
            $SSH ec2-user@$pub_dns sudo pkill shutdown

            stop_listener

            dbg "Attempting to stop shutdown sleep "
            $SSH ec2-user@$pub_dns pkill -u ec2-user -f "'bash -c sleep'"

            if $SSH ec2-user@$pub_dns pgrep -u ec2-user -f service_pool.sh; then
                sleep 10s  # Allow service_pool to exit gracefully
            fi

            # N/B: This will not stop any currently running CI tasks.
            dbg "Guarantee pool listener is dead"
            $SSH ec2-user@$pub_dns sudo pkill -u ${name}-worker -f "'cirrus worker run'"
        )
        continue
    fi

    if ! $SSH ec2-user@$pub_dns test -r .setup.done; then

        if ! $SSH ec2-user@$pub_dns test -r .setup.started; then
            if $SSH ec2-user@$pub_dns test -r setup.log; then
                # Can be caused by operator flipping PWPoolReady value on instance for debugging
                pwst_warn "Setup log found, prior executions may have failed $(ctx 0)."
            fi

            pwst_msg "Setting up new instance"

            # Ensure bash used for consistency && some ssh commands below
            # don't play nicely with zsh.
            $SSH ec2-user@$pub_dns sudo chsh -s /bin/bash ec2-user &> /dev/null

            if ! $SCP $SETUP_SCRIPT $SPOOL_SCRIPT $SHDWN_SCRIPT ec2-user@$pub_dns:/var/tmp/; then
                pwst_warn "Could not scp scripts to instance $(ctx 0)."
                continue  # try again next loop
            fi

            if ! $SCP $CIENV_SCRIPT ec2-user@$pub_dns:./; then
                pwst_warn "Could not scp CI Env. script to instance $(ctx 0)."
                continue  # try again next loop
            fi

            if ! $SSH ec2-user@$pub_dns chmod +x "/var/tmp/*.sh" "./ci_env.sh"; then
                pwst_warn "Could not chmod scripts $(ctx 0)."
                continue  # try again next loop
            fi

            shutdown_seconds=$((60*60*term_addtl*CREATE_STAGGER_HOURS + 60*60*PW_MAX_HOURS))
            pwst_msg "Starting automatic instance recycling in $((term_addtl*CREATE_STAGGER_HOURS + PW_MAX_HOURS)) hours"
            # Darwin is really weird WRT active terminals and the shutdown
            # command.  Instead of installing a future shutdown, stick an
            # immediate shutdown at the end of a long sleep. This is the
            # simplest workaround I could find :S
            # Darwin sleep only accepts seconds.
            if ! $SSH ec2-user@$pub_dns bash -c \
                "'sleep $shutdown_seconds && /var/tmp/shutdown.sh' </dev/null >>setup.log 2>&1 &"; then
                pwst_warn "Could not start automatic instance recycling."
                continue  # try again next loop
            fi

            pwst_msg "Executing setup script."
            # Run setup script in background b/c it takes ~10m to complete.
            # N/B: This drops .setup.started and eventually (hopefully) .setup.done
            if ! $SSH ec2-user@$pub_dns \
                    env POOLTOKEN=$POOLTOKEN \
                    bash -c "'/var/tmp/setup.sh $DH_REQ_TAG:\ $DH_REQ_VAL' </dev/null >>setup.log 2>&1 &"; then
                # This is critical, no easy way to determine what broke.
                force_term "Failed to start background setup script"
                continue
            fi

            msg "Setup script started."
            set_pw_status setup started

            # If starting multiple instance for any reason, stagger shutdowns.
            term_addtl=$((term_addtl+1))

            # Let setup run in the background
            continue
        fi

        # Setup started in previous loop.  Set to epoch on error.
        since_timestamp=$($SSH ec2-user@$pub_dns tail -1 .setup.started || echo "@0")
        since_epoch=$(date -u -d "$since_timestamp" +%s)
        running_seconds=$((now_epoch-since_epoch))
        # Be helpful to human monitors, show the last few lines from the log to help
        # track progress and/or any errors/warnings.
        pwst_msg "Setup incomplete;  Running for $((running_seconds/60)) minutes (~10 typical)"
        msg "setup.log tail: $($SSH ec2-user@$pub_dns tail -n 1 setup.log)"
        if [[ $running_seconds -gt $SETUP_MAX_SECONDS ]]; then
            force_term "Setup running for ${running_seconds}s, max ${SETUP_MAX_SECONDS}s."
        fi
        continue
    fi

    dbg "Instance setup has completed"
    set_pw_status setup complete

    # Spawned by setup.sh
    dbg "Checking service_pool.sh script"
    if ! $SSH ec2-user@$pub_dns pgrep -u ec2-user -q -f service_pool.sh; then
        # This should not happen at this stage; Nefarious or uncontrolled activity?
        force_term "Pool servicing script (service_pool.sh) is not running."
        continue
    fi

    dbg "Checking cirrus listener"
    state_fault=0
    if ! $SSH ec2-user@$pub_dns pgrep -u "${name}-worker" -q -f "'cirrus worker run'"; then
        # Don't try to examine prior state if there was none.
        if ((n_pw_total)); then
            for _pwentry in "${_pwstate[@]}"; do
                read -r _name _setup_state _listener_state _tasks _taskf _junk <<<"$_pwentry"
                dbg "Examining pw_state.txt entry '$_name' with listener state '$_listener_state'"
                if [[ "$_name" == "$name" ]] && [[ "$_listener_state" != "alive" ]]; then
                    # service_pool.sh did not restart listener since last loop
                    # and node is not in maintenance mode (PWPoolReady == 'true')
                    force_term "Pool listener '$_listener_state' state fault."
                    state_fault=1
                    break
                fi
            done
        fi

        # The instance is in the process of shutting-down/terminating, move on to next instance.
        if ((state_fault)); then
            continue
        fi

        # Previous state didn't exist, or listener status was 'alive'.
        # Process may have simply crashed, allow service_pool.sh time to restart it.
        pwst_warn "Cirrus worker listener process NOT running, will recheck again $(ctx 0)."
        # service_pool.sh should catch this and restart the listener. If not, the next time
        # through this loop will force_term() the instance.
        set_pw_status listener dead  # service_pool.sh should restart listener
        continue
    else
        set_pw_status listener alive
    fi

    dbg "Checking worker log"
    logpath="/private/tmp/${name}-worker.log"  # set in setup.sh
    if ! $SSH ec2-user@$pub_dns cat "'$logpath'" &> "$logoutput"; then
        # The "${name}-worker" user has write access to this log
        force_term "Missing worker log $logpath."
        continue
    fi

    dbg "Checking worker registration"
    # First lines of log should always match this
    if ! head -10 "$logoutput" | grep -q 'worker successfully registered'; then
        # This could signal log manipulation by worker user, or it could be harmless.
        pwst_warn "Missing registration log entry"
    fi

    # The CI user has write-access to this log file on the instance,
    # make this known to humans in case they care.
    n_started_tasks=$(grep -Ei 'started task [0-9]+' "$logoutput" | wc -l) || true
    n_finished_tasks=$(grep -Ei 'task [0-9]+ completed' "$logoutput" | wc -l) || true
    set_pw_status tasks $n_started_tasks
    set_pw_status taskf $n_finished_tasks

    msg "Apparent tasks started/finished/running: $n_started_tasks $n_finished_tasks $((n_started_tasks-n_finished_tasks)) (max $PW_MAX_TASKS)"

    dbg "Checking apparent task limit"
    if [[ "$n_finished_tasks" -gt $PW_MAX_TASKS ]]; then
        force_term "Instance exceeded $PW_MAX_TASKS apparent tasks."
    fi
done

_I=""
msg " "
msg "Processing all persistent worker states."
for _dhentry in "${_dhstate[@]}"; do
    read -r name otherstuff<<<"$_dhentry"
    _f1=$name
    _f2=$(<$TEMPDIR/${name}.setup)
    _f3=$(<$TEMPDIR/${name}.listener)
    _f4=$(<$TEMPDIR/${name}.tasks)
    _f5=$(<$TEMPDIR/${name}.taskf)
    _f6=$(<$TEMPDIR/${name}.comment)
    [[ -z "$_f6" ]] || _f6=" # $_f6"

    printf '%s %s %s %s %s%s\n' \
      "$_f1" "$_f2" "$_f3" "$_f4" "$_f5" "$_f6" >> "$TEMPDIR/$(basename $PWSTATE)"
done

dbg "Creating/updating state file"
if [[ -r "$PWSTATE" ]]; then
    cp "$PWSTATE" "${PWSTATE}~"
fi
mv "$TEMPDIR/$(basename $PWSTATE)" "$PWSTATE"
