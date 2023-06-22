
# Library of os/platform related definitions and functions
# Not intended to be executed directly

OS_RELEASE_VER="${OS_RELEASE_VER:-$(source /etc/os-release; echo $VERSION_ID | tr -d '.')}"
OS_RELEASE_ID="${OS_RELEASE_ID:-$(source /etc/os-release; echo $ID)}"
OS_REL_VER="${OS_REL_VER:-$OS_RELEASE_ID-$OS_RELEASE_VER}"

# Ensure no user-input prompts in an automation context
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
if ((UID)) || ((_TEST_UID)); then
    SUDO="${SUDO:-sudo}"
    if [[ "$OS_RELEASE_ID" =~ (ubuntu)|(debian) ]]; then
        if [[ ! "$SUDO" =~ noninteractive ]]; then
            SUDO="$SUDO env DEBIAN_FRONTEND=$DEBIAN_FRONTEND"
        fi
    fi
fi
