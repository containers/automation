
# Library of os/platform related definitions and functions
# Not intended to be executed directly

OS_RELEASE_VER="${OS_RELEASE_VER:-$(source /etc/os-release; echo $VERSION_ID | tr -d '.')}"
OS_RELEASE_ID="${OS_RELEASE_ID:-$(source /etc/os-release; echo $ID)}"
OS_REL_VER="${OS_REL_VER:-$OS_RELEASE_ID-$OS_RELEASE_VER}"

# Ensure no user-input prompts in an automation context
export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"
# _TEST_UID only needed for unit-testing
# shellcheck disable=SC2154
if ((UID)) || ((_TEST_UID)); then
    SUDO="${SUDO:-sudo}"
    if [[ "$OS_RELEASE_ID" =~ (ubuntu)|(debian) ]]; then
        if [[ ! "$SUDO" =~ noninteractive ]]; then
            SUDO="$SUDO env DEBIAN_FRONTEND=$DEBIAN_FRONTEND"
        fi
    fi
fi
# Regex defining all CI-related env. vars. necessary for all possible
# testing operations on all platforms and versions.  This is necessary
# to avoid needlessly passing through global/system values across
# contexts, such as host->container or root->rootless user
#
# List of envariables which must be EXACT matches
PASSTHROUGH_ENV_EXACT="${PASSTHROUGH_ENV_EXACT:-DEST_BRANCH|IMAGE_SUFFIX|DISTRO_NV|SCRIPT_BASE}"

# List of envariable patterns which must match AT THE BEGINNING of the name.
PASSTHROUGH_ENV_ATSTART="${PASSTHROUGH_ENV_ATSTART:-CI|TEST}"

# List of envariable patterns which can match ANYWHERE in the name
PASSTHROUGH_ENV_ANYWHERE="${PASSTHROUGH_ENV_ANYWHERE:-_NAME|_FQIN}"

# List of expressions to exclude env. vars for security reasons
SECRET_ENV_RE="${SECRET_ENV_RE:-(^PATH$)|(^BASH_FUNC)|(^_.*)|(.*PASSWORD.*)|(.*TOKEN.*)|(.*SECRET.*)}"

# Return a list of environment variables that should be passed through
# to lower levels (tests in containers, or via ssh to rootless).
# We return the variable names only, not their values. It is up to our
# caller to reference values.
passthrough_envars() {
    local passthrough_env_re="(^($PASSTHROUGH_ENV_EXACT)\$)|(^($PASSTHROUGH_ENV_ATSTART))|($PASSTHROUGH_ENV_ANYWHERE)"
    local envar

    for envar in SECRET_ENV_RE PASSTHROUGH_ENV_EXACT PASSTHROUGH_ENV_ATSTART PASSTHROUGH_ENV_ANYWHERE passthrough_env_re; do
      if [[ -z "${!envar}" ]]; then
        echo "Error: Required env. var. \$$envar is unset or empty in call to passthrough_envars()" > /dev/stderr
        exit 1
      fi
    done

    echo "Warning: Will pass env. vars. matching the following regex:
$passthrough_env_re" >> /dev/stderr

    compgen -A variable | grep -Ev "$SECRET_ENV_RE" | grep -E  "$passthrough_env_re"
}

# On more occasions than we'd like, it's necessary to put temporary
# platform-specific workarounds in place.  To help ensure they'll
# actually be temporary, it's useful to place a time limit on them.
# This function accepts two arguments:
# - A (required) future date of the form YYYYMMDD (UTC based).
# - An (optional) message string to display upon expiry of the timebomb.
timebomb() {
    local expire="$1"

    if ! expr "$expire" : '[0-9]\{8\}$' > /dev/null; then
      echo "timebomb: '$expire' must be UTC-based and of the form YYYYMMDD"
      exit 1
    fi

    if [[ $(date -u +%Y%m%d) -lt $(date -u -d "$expire" +%Y%m%d) ]]; then
        return
    fi

    declare -a frame
    read -a frame < <(caller)

    cat << EOF >> /dev/stderr
***********************************************************
* TIME BOMB EXPIRED!
*
*   >> ${frame[1]}:${frame[0]}: ${2:-No reason given, tsk tsk}
*
* Temporary workaround expired on ${expire:0:4}-${expire:4:2}-${expire:6:2}.
*
* Please review the above source file and either remove the
* workaround or, if absolutely necessary, extend it.
*
* Please also check for other timebombs while you're at it.
***********************************************************
EOF
    exit 1
}
