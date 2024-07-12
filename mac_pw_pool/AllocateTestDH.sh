#!/bin/bash

# This script is intended for use by humans to allocate a dedicated-host
# and create an instance on it for testing purposes.  When executed,
# it will create a temporary clone of the repository with the necessary
# modifications to manipulate the test host.  It's the user's responsibility
# to cleanup this directory after manually removing the instance (see below).
#
# **Note**: Due to Apple/Amazon restrictions on the removal of these
# resources, cleanup must be done manually.  You will need to shutdown and
# terminate the instance, then wait 24-hours before releasing the
# dedicated-host.  The hosts cost money w/n an instance is running.
#
# The script assumes:
#
# * The current $USER value reflects your actual identity such that
#   the test instance may be labeled appropriatly for auditing.
# * The `aws` CLI tool is installed on $PATH.
# * Appropriate `~/.aws/credentials` credentials are setup.
# * The us-east-1 region is selected in `~/.aws/config`.
# * The $POOLTOKEN env. var. is set to value available from
#   https://cirrus-ci.com/pool/1cf8c7f7d7db0b56aecd89759721d2e710778c523a8c91c7c3aaee5b15b48d05
# * The local ssh-agent is able to supply the appropriate private key (stored in BW).

set -eo pipefail

# shellcheck source-path=SCRIPTDIR
source $(dirname ${BASH_SOURCE[0]})/pw_lib.sh

# Support debugging all mac_pw_pool scripts or only this one
I_DEBUG="${I_DEBUG:0}"
if ((I_DEBUG)); then
    X_DEBUG=1
    warn "Debugging enabled."
fi

dbg "\$USER=$USER"

[[ -n "$USER" ]] || \
    die "The variable \$USER must not be empty"

[[ -n "$POOLTOKEN" ]] || \
    die "The variable \$POOLTOKEN must not be empty"

INST_NAME="${USER}Testing"
LIB_DIRNAME=$(realpath --relative-to=$REPO_DIRPATH $LIB_DIRPATH)
# /tmp is usually a tmpfs, don't let an accidental reboot ruin
# access to a test DH/instance for a developer.
TMP_CLONE_DIRPATH="/var/tmp/${LIB_DIRNAME}_${INST_NAME}"

dbg "\$TMP_CLONE_DIRPATH=$TMP_CLONE_DIRPATH"

if [[ -d "$TMP_CLONE_DIRPATH" ]]; then
    die "Found existing '$TMP_CLONE_DIRPATH', assuming in-use/relevant; If not, manual cleanup is required."
fi

msg "Creating temporary clone dir and transfering any uncommited files."

git clone --no-local --no-hardlinks --depth 1 --single-branch --no-tags --quiet "file://$REPO_DIRPATH" "$TMP_CLONE_DIRPATH"
declare -a uncommited_filepaths
readarray -t uncommited_filepaths <<<$(
    pushd "$REPO_DIRPATH" &> /dev/null
    # Obtaining uncommited relative staged filepaths
    git diff --name-only HEAD
    # Obtaining uncommited relative unstaged filepaths
    git ls-files . --exclude-standard --others
    popd &> /dev/null
)

dbg "Copying \$uncommited_filepaths[*]=${uncommited_filepaths[*]}"

for uncommited_file in "${uncommited_filepaths[@]}"; do
    uncommited_file_src="$REPO_DIRPATH/$uncommited_file"
    uncommited_file_dest="$TMP_CLONE_DIRPATH/$uncommited_file"
    uncommited_file_dest_parent=$(dirname "$uncommited_file_dest")
    #dbg "Working on uncommited file '$uncommited_file_src'"
    if [[ -r "$uncommited_file_src" ]]; then
        mkdir -p "$uncommited_file_dest_parent"
        #dbg "$uncommited_file_src -> $uncommited_file_dest"
        cp -a "$uncommited_file_src" "$uncommited_file_dest"
    fi
done

declare -a modargs
# Format: <pw_lib.sh var name> <new value> <old value>
modargs=(
    # Necessary to prevent in-production macs from trying to use testing instance
    "DH_REQ_VAL          $INST_NAME     $DH_REQ_VAL"
    # Necessary to make test dedicated host stand out when auditing the set in the console
    "DH_PFX              $INST_NAME     $DH_PFX"
    # The default launch template name includes $DH_PFX, ensure the production template name is used.
    # N/B: The old/unmodified pw_lib.sh is still loaded for the running script
    "TEMPLATE_NAME       $TEMPLATE_NAME Cirrus${DH_PFX}PWinstance"
    # Permit developer to use instance for up to 3 days max (orphan vm cleaning process will nail it after that).
    "PW_MAX_HOURS        72             $PW_MAX_HOURS"
    # Permit developer to execute as many Cirrus-CI tasks as they want w/o automatic shutdown.
    "PW_MAX_TASKS        9999           $PW_MAX_TASKS"
)

for modarg in "${modargs[@]}"; do
    set -- $modarg # Convert the "tuple" into the param args $1 $2...
    dbg "Modifying pw_lib.sh \$$1 definition to '$2' (was '$3')"
    sed -i -r -e "s/^$1=.*/$1=\"$2\"/" "$TMP_CLONE_DIRPATH/$LIB_DIRNAME/pw_lib.sh"
    # Ensure future script invocations use the new values
    unset $1
done

cd "$TMP_CLONE_DIRPATH/$LIB_DIRNAME"
source ./pw_lib.sh

# Before going any further, make sure there isn't an existing
# dedicated-host named ${INST_NAME}-0.  If there is, it can
# be re-used instead of failing the script outright.
existing_dh_json=$(mktemp -p "." dh_allocate_XXXXX.json)
$AWS ec2 describe-hosts --filter "Name=tag:Name,Values=${INST_NAME}-0" --query 'Hosts[].HostId' > "$existing_dh_json"
if grep -Fqx '[]' "$existing_dh_json"; then

    msg "Creating the dedicated host '${INST_NAME}-0'"
    declare dh_allocate_json
    dh_allocate_json=$(mktemp -p "." dh_allocate_XXXXX.json)

    declare -a awsargs
    # Word-splitting of $AWS is desireable
    # shellcheck disable=SC2206
    awsargs=(
        $AWS
        ec2 allocate-hosts
        --availability-zone us-east-1a
        --instance-type mac2.metal
        --auto-placement off
        --host-recovery off
        --host-maintenance off
        --quantity 1
        --tag-specifications
        "ResourceType=dedicated-host,Tags=[{Key=Name,Value=${INST_NAME}-0},{Key=$DH_REQ_TAG,Value=$DH_REQ_VAL},{Key=PWPoolReady,Value=true},{Key=automation,Value=false}]"
    )

    # N/B: Apple/Amazon require min allocation time of 24hours!
    dbg "Executing: ${awsargs[*]}"
    "${awsargs[@]}" > "$dh_allocate_json" || \
        die "Provisioning new dedicated host $INST_NAME failed.  Manual debugging & cleanup required."

    dbg $(jq . "$dh_allocate_json")
    dhid=$(jq -r -e '.HostIds[0]' "$dh_allocate_json")
    [[ -n "$dhid" ]] || \
        die "Obtaining DH ID of new host. Manual debugging & cleanup required."

    # There's a small delay between allocating the dedicated host and LaunchInstances.sh
    # being able to interact with it.  There's no sensible way to monitor for this state :(
    sleep 3s
else  # A dedicated host already exists
    dhid=$(jq -r -e '.[0]' "$existing_dh_json")
fi

# Normally allocation is fairly instant, but not always.  Confirm we're able to actually
# launch a mac instance onto the dedicated host.
for ((attempt=1 ; attempt < 11 ; attempt++)); do
    msg "Attempt #$attempt launching a new instance on dedicated host"
    ./LaunchInstances.sh --force
    if grep -E "^${INST_NAME}-0 i-" dh_status.txt; then
        attempt=-1  # signal success
        break
    fi
    sleep 1s
done

[[ "$attempt" -eq -1 ]] || \
    die "Failed to use LaunchInstances.sh.  Manual debugging & cleanup required."

# At this point the script could call SetupInstances.sh in another loop
# but it takes about 20-minutes to complete.  Also, the developer may
# not need it, they may simply want to ssh into the instance to poke
# around.  i.e. they don't need to run any Cirrus-CI jobs on the test
# instance.
warn "---"
warn "NOT copying/running setup.sh to new instance (in case manual activities are desired)."
warn "---"

w="PLEASE REMEMBER TO terminate instance, wait two hours, then
remove the dedicated-host in the web console, or run
'aws ec2 release-hosts --host-ids=$dhid'."

msg "---"
msg "Dropping you into a shell inside a temp. repo clone:
($TMP_CLONE_DIRPATH/$LIB_DIRNAME)"
msg "---"
msg "Once it finishes booting (5m), you may use './InstanceSSH.sh ${INST_NAME}-0'
to access it.  Otherwise to fully setup the instance for Cirrus-CI, you need
to execute './SetupInstances.sh' repeatedly until the ${INST_NAME}-0 line in
'pw_status.txt' includes the text 'complete alive'.  That process can take 20+
minutes.  Once alive, you may then use Cirrus-CI to test against this specific
instance with any 'persistent_worker' task having a label of
'$DH_REQ_TAG=$DH_REQ_VAL' set."
msg "---"
warn "$w"

export POOLTOKEN  # ensure availability in sub-shell
bash -l

warn "$w"
