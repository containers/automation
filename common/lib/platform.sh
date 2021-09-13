
# Library of os/platform related definitions and functions
# Not intended to be executed directly

OS_RELEASE_VER="$(source /etc/os-release; echo $VERSION_ID | tr -d '.')"
OS_RELEASE_ID="$(source /etc/os-release; echo $ID)"
OS_REL_VER="$OS_RELEASE_ID-$OS_RELEASE_VER"

SUDO=""
if [[ "$UID" -ne 0 ]]; then
    SUDO="sudo"
fi

if [[ "$OS_RELEASE_ID" == "ubuntu" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    SUDO="$SUDO env DEBIAN_FRONTEND=$DEBIAN_FRONTEND"
fi
