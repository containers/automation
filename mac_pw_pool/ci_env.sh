#!/bin/bash

# This script drops the caller into a bash shell inside an environment
# substantially similar to a Cirrus-CI task running on this host.
# The envars below may require adjustment to better fit them to
# current/ongoing development in podman's .cirrus.yml

set -eo pipefail

# Not running as the pool worker user
if [[ "$USER" == "ec2-user" ]]; then
    PWINST=$(curl -sSLf http://instance-data/latest/meta-data/tags/instance/Name)
    PWUSER=$PWINST-worker

    if [[ ! -d "/Users/$PWUSER" ]]; then
        echo "Warnin: Instance hasn't been setup.  Assuming caller will tend to this."
        sudo sysadminctl -addUser $PWUSER
    fi

    sudo install -o $PWUSER "${BASH_SOURCE[0]}" "/Users/$PWUSER/"
    exec sudo su -c "/Users/$PWUSER/$(basename ${BASH_SOURCE[0]})" - $PWUSER
fi

# Export all CI-critical envars defined below
set -a

CIRRUS_SHELL="/bin/bash"
CIRRUS_TASK_ID="0123456789"
CIRRUS_WORKING_DIR="$HOME/ci/task-${CIRRUS_TASK_ID}"

GOPATH="$CIRRUS_WORKING_DIR/.go"
GOCACHE="$CIRRUS_WORKING_DIR/.go/cache"
GOENV="$CIRRUS_WORKING_DIR/.go/support"

CONTAINERS_MACHINE_PROVIDER="applehv"

MACHINE_IMAGE="https://fedorapeople.org/groups/podman/testing/applehv/arm64/fedora-coreos-38.20230925.dev.0-applehv.aarch64.raw.gz"

GINKGO_TAGS="remote exclude_graphdriver_btrfs btrfs_noversion exclude_graphdriver_devicemapper containers_image_openpgp remote"

DEBUG_MACHINE="1"

ORIGINAL_HOME="$HOME"
HOME="$HOME/ci"
TMPDIR="/private/tmp/ci"
mkdir -p "$TMPDIR" "$CIRRUS_WORKING_DIR"

# Drop caller into the CI-like environment
cd "$CIRRUS_WORKING_DIR"
bash -il
