#!/bin/bash

# Setup and launch Cirrus-CI PW Pool node.  It must be called
# with the env. var. `$POOLTOKEN` set.  It is assumed to be
# running on a fresh AWS EC2 mac2.metal instance as `ec2-user`
# The instance must have both "metadata" and "Allow tags in
# metadata" options enabled.  The instance must set the
# "terminate" option for "shutdown behavior".

set -eo pipefail

GVPROXY_RELEASE_URL="https://github.com/containers/gvisor-tap-vsock/releases/latest/download/gvproxy-darwin"
STARTED_FILE="$HOME/.setup.started"
COMPLETION_FILE="$HOME/.setup.done"

# Ref: https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/instancedata-data-retrieval.html
PWNAME=$(curl -sSLf http://instance-data/latest/meta-data/tags/instance/Name)
PWREADYURL="http://instance-data/latest/meta-data/tags/instance/PWPoolReady"
PWREADY=$(curl -sSLf $PWREADYURL)

PWUSER=$PWNAME-worker
rm -f /private/tmp/*_cfg_*
PWCFG=$(mktemp /private/tmp/${PWNAME}_cfg_XXXXXXXX)
PWLOG="/private/tmp/${PWUSER}.log"

msg() { echo "##### ${1:-No message message provided}"; }
die() { echo "ERROR: ${1:-No error message provided}"; exit 1; }

die_if_empty() {
    local tagname
    tagname="$1"
    [[ -n "$tagname" ]] || \
        die "Unexpectedly empty instance '$tagname' tag, is metadata tag access enabled?"
}

[[ -n "$POOLTOKEN" ]] || \
    die "Must be called with non-empty \$POOLTOKEN set."

[[ ! -r "$COMPLETION_FILE" ]] || \
    die "Appears setup script already ran at '$(cat $COMPLETION_FILE)'"

[[ "$USER" == "ec2-user" ]] || \
    die "Expecting to execute as 'ec2-user'."

die_if_empty PWNAME
die_if_empty PWREADY

[[ "$PWREADY" == "true" ]] || \
    die "Found PWPoolReady tag not set 'true', aborting setup."

# All operations assume this CWD
cd $HOME

# Checked by instance launch script to monitor setup status & progress
msg $(date -u -Iseconds | tee "$STARTED_FILE")

msg "Configuring paths"
grep -q homebrew /etc/paths || \
    echo -e "/opt/homebrew/bin\n/opt/homebrew/opt/coreutils/libexec/gnubin\n$(cat /etc/paths)" \
        | sudo tee /etc/paths > /dev/null

# For whatever reason, when this script is run through ssh, the default
# environment isn't loaded automatically.
. /etc/profile

msg "Installing podman-machine, testing, and CI deps. (~2m install time)"
if [[ ! -x /usr/local/bin/gvproxy ]]; then
    brew tap cfergeau/crc
    brew install go go-md2man coreutils pstree vfkit cirruslabs/cli/cirrus

    # Normally gvproxy is installed along with "podman" brew.  CI Tasks
    # on this instance will be running from source builds, so gvproxy must
    # be install from upstream release.
    curl -sSLfO "$GVPROXY_RELEASE_URL"
    sudo install -o root -g staff -m 0755 gvproxy-darwin /usr/local/bin/gvproxy
    rm gvproxy-darwin
fi

msg "Setting up hostname"
# Make host easier to identify from CI logs (default is some
# random internal EC2 dns name).
if [[ "$(uname -n)" != "$PWNAME" ]]; then
    sudo hostname $PWNAME
    sudo scutil --set HostName $PWNAME
    sudo scutil --set ComputerName $PWNAME
fi

msg "Adding/Configuring PW User"
if ! id "$PWUSER" &> /dev/null; then
    sudo sysadminctl -addUser $PWUSER
    # User can't remove own pre-existing homedir crap during cleanup
    sudo rm -rf /Users/$PWUSER/*
    sudo rm -rf /Users/$PWUSER/.??*
    sudo pkill -u $PWUSER || true
fi

# FIXME: Semi-secret POOLTOKEN value should not be in this file.
# TODO: It would be nice to label these based on instance's $DH_REQ_TAG: $DH_REQ_VAL
#       as that would allow targeting PRs against (for example) a temp. testing pool.
# ref: https://github.com/cirruslabs/cirrus-cli/discussions/662
cat << EOF | sudo tee $PWCFG > /dev/null
---
name: "$PWNAME"
token: "$POOLTOKEN"
log:
  file: "${PWLOG}"
security:
  allowed-isolations:
    none: {}
EOF
sudo chown ${USER}:staff $PWCFG

# Monitored by instance launch script
echo "# Log created $(date -u -Iseconds) - do not manually remove or modify!" > $PWLOG
sudo chown ${USER}:staff $PWLOG
sudo chmod g+rw $PWLOG

if ! pgrep -q -f service_pool.sh; then
    # Allow service_pool.sh access to these values
    export PWCFG
    export PWUSER
    export PWREADYURL
    export PWREADY
    msg "Spawning listener supervisor process."
    /var/tmp/service_pool.sh </dev/null >>setup.log 2>&1 &
    disown %-1
else
    msg "Warning: Listener supervisor already running"
fi

# Monitored by instance launch script
date -u -Iseconds >> "$COMPLETION_FILE"
