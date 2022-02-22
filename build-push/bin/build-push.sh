#!/bin/bash

# This is a wrapper around buildah build, coupled with pre and post
# build commands and automatic registry server push.  Its goal is to
# provide an abstraction layer for additional build automation. Though
# it may be useful on its own, this is not its primary purpose.
#
# See the README.md file for more details

set -eo pipefail

# This is a convenience for callers that don't separately source this first
# in their automation setup.
if [[ -z "$AUTOMATION_LIB_PATH" ]] && [[ -r /etc/automation_environment ]]; then
    set -a
    source /etc/automation_environment
    set +a
fi

if [[ ! -r "$AUTOMATION_LIB_PATH/common_lib.sh" ]]; then
    (
        echo "ERROR: Expecting \$AUTOMATION_LIB_PATH to contain the installation"
        echo "       directory path for the common automation tooling."
        echo "       Please refer to the README.md for installation instructions."
    ) > /dev/stderr
    exit 2  # Verified by tests
fi

source $AUTOMATION_LIB_PATH/common_lib.sh

SCRIPT_FILEPATH=$(realpath "${BASH_SOURCE[0]}")

# Useful for non-standard installations & testing
RUNTIME="${RUNTIME:-$(type -P buildah||echo /bin/true)}"  # see check_dependencies()

# List of variable names to export for --prepcmd and --modcmd
# N/B: Bash cannot export arrays
_CMD_ENV="SCRIPT_FILEPATH RUNTIME PLATFORMOS FQIN CONTEXT
PUSH ARCHES REGSERVER NAMESPACE IMGNAME PREPCMD MODCMD"

# Simple error-message strings
E_FQIN="Must specify a valid 3-component FQIN w/o a tag, not:"
E_CONTEXT="Given context path is not an existing directory:"
E_ONEARCH="Must specify --arches=<value> with '=', and <value> being a comma-separated list, not:"
_E_PREPMOD_SFX="with '=', and <value> being a (quoted) string, not:"
E_USERPASS="When --nopush not specified, must export non-empty value for variable:"
E_USAGE="
Usage: $(basename ${BASH_SOURCE[0]}) [options] <FQIN> <Context> [extra...]

With the required arguments (See also, 'Required Environment Variables'):

    <FQIN> is the fully-qualified image name to build and push.  It must
    contain only three components: Registry FQDN:PORT, Namespace, and
    Image Name.   The image tag must NOT be specified, see --modcmd=<value>
    option below.

    <Context> is the full build-context DIRECTORY path containing the
    target Dockerfile or Containerfile.  This must be a local path to
    an existing directory.

Zero or more [options] and [extra...] optional arguments:

    --help if specified, will display this usage/help message.

    --arches=<value> specifies a comma-separated list of architectures
    to build.  When unspecified, the local system's architecture will
    be used. Architecture names must be the canonical values used/supported
    by golang and available/included in the base-image's manifest list.
    Note: The '=' is required.

    --prepcmd=<value> specifies a bash string to execute just prior to
    building.  Any embedded quoting will be preserved.  Any output produced
    will be displayed, but ignored. See the 'Environment for...' section
    below for details on what env. vars. are made available for use
    by/substituted in <value>.

    --modcmd=<value> specifies a bash string to execute after a successful
    build but prior to pushing any image(s).  Any embedded quoting will be
    preserved.  Output from the script will be displayed, but ignored.
    Any tags which should/shouldn't be pushed must be handled by this
    command/script (including complete removal or replacement). See the
    'Environment for...' section below for details on what env. vars.
    are made available for use by/substituted in <value>.  If no
    FQIN tags remain, an error will be printed and the script will exit
    non-zero.

    --nopush will bypass pushing the built/tagged image(s).

    [extra...] specifies optional, additional arguments to pass when building
    images.  For example, this may be used to pass in [actual] build-args, or
    volume-mounts.

Environment for --prepcmd and --modcmd

The shell environment for executing these strings will contain the
following environment variables and their values at runtime:

$_CMD_ENV

Additionally, unless --nopush was specified, the host will be logged
into the registry server.

Required Environment Variables

    Unless --nopush is used, \$<NAMESPACE>_USERNAME and
    \$<NAMESPACE>_PASSWORD must contain the necessary registry
    credentials.  The value for <NAMESPACE> is always capitalized.
    The account is assumed to have 'write' access to push the built
    image.

Optional Environment Variables:

    \$RUNTIME specifies the complete path to an alternate executable
    to use for building.  Defaults to the location of 'buildah'.

    \$PARALLEL_JOBS specifies the number of builds to execute in parallel.
    When unspecified, it defaults to the number of processor (threads) on
    the system.
"

# Show an error message, followed by usage text to stderr
die_help() {
    local err="${1:-No error message specified}"
    msg "Please use --help for usage information."
    die "$err"
}

init() {
    # /bin/true is used by unit-tests
    if [[ "$RUNTIME" =~ true ]] || [[ ! $(type -P "$RUNTIME") ]]; then
        die_help "Unable to find \$RUNTIME ($RUNTIME) on path: $PATH"
    fi
    if [[ -n "$PARALLEL_JOBS" ]] && [[ ! "$PARALLEL_JOBS" =~ ^[0-9]+$ ]]; then
        PARALLEL_JOBS=""
    fi
    # Can't use $(uname -m) because (for example) "x86_64" != "amd64" in registries
    # This will be verified, see check_dependencies().
    NATIVE_GOARCH="${NATIVE_GOARCH:-$($RUNTIME info --format='{{.host.arch}}')}"
    PARALLEL_JOBS="${PARALLEL_JOBS:-$($RUNTIME info --format='{{.host.cpus}}')}"

    dbg "Found native go-arch: $NATIVE_GOARCH"
    dbg "Found local CPU count: $PARALLEL_JOBS"

    if [[ -z "$NATIVE_GOARCH" ]]; then
        die_help "Unable to determine the local system architecture, is \$RUNTIME correct: '$RUNTIME'"
    elif ! type -P jq &>/dev/null; then
        die_help "Unable to find 'jq' executable on path: $PATH"
    fi

    # Not likely overridden, but keep the possibility open
    PLATFORMOS="${PLATFORMOS:-linux}"

    # Env. vars set by parse_args()
    FQIN=""                   # required (fully-qualified-image-name)
    CONTEXT=""                # required (directory path)
    PUSH=1                    # optional (1 means push, 0 means do not)
    ARCHES="$NATIVE_GOARCH"   # optional (Native architecture default)
    PREPCMD=""                # optional (--prepcmd)
    MODCMD=""                 # optional (--modcmd)
    declare -a BUILD_ARGS
    BUILD_ARGS=()             # optional
    REGSERVER=""              # parsed out of $FQIN
    NAMESPACE=""              # parsed out of $FQIN
    IMGNAME=""                # parsed out of $FQIN
    LOGGEDIN=0                # indicates successful $REGSERVER/$NAMESPACE login
    unset NAMESPACE_USERNAME  # lookup based on $NAMESPACE when $PUSH=1
    unset NAMESPACE_PASSWORD  # lookup based on $NAMESPACE when $PUSH=1
}

cleanup() {
    set +e
    if ((LOGGEDIN)) && ! $RUNTIME logout "$REGSERVER/$NAMESPACE"; then
        warn "Logout of registry '$REGSERVER/$NAMESPACE' failed."
    fi
}

parse_args() {
    local -a args
    local arg
    local archarg
    local nsu_var
    local nsp_var

    dbg "in parse_args()"

    if [[ $# -lt 2 ]]; then
        die_help "Must specify non-empty values for required arguments."
    fi

    args=("$@")  # Special-case quoting: Will NOT separate quoted arguments
    for arg in "${args[@]}"; do
        dbg "Processing parameter '$arg'"
        case "$arg" in
            --arches=*)
                archarg=$(tr ',' ' '<<<"${arg:9}")
                if [[ -z "$archarg" ]]; then die_help "$E_ONEARCH '$arg'"; fi
                ARCHES="$archarg"
                ;;
            --arches)
                # Argument format not supported (to simplify parsing logic)
                die_help "$E_ONEARCH '$arg'"
                ;;
            --prepcmd=*)
                # Bash argument processing automatically strips any outside quotes
                PREPCMD="${arg:10}"
                ;;
            --prepcmd)
                die_help "Must specify --prepcmd=<value> $_E_PREPMOD_SFX '$arg'"
                ;;
            --modcmd=*)
                MODCMD="${arg:9}"
                ;;
            --modcmd)
                die_help "Must specify --modcmd=<value> $_E_PREPMOD_SFX '$arg'"
                ;;
            --nopush)
                dbg "Nopush flag detected, will NOT push built images."
                PUSH=0
                ;;
            *)
                if [[ -z "$FQIN" ]]; then
                    dbg "Grabbing FQIN parameter: '$arg'."
                    FQIN="$arg"
                    REGSERVER=$(awk -F '/' '{print $1}' <<<"$FQIN")
                    NAMESPACE=$(awk -F '/' '{print $2}' <<<"$FQIN")
                    IMGNAME=$(awk -F '/' '{print $3}' <<<"$FQIN")
                elif [[ -z "$CONTEXT" ]]; then
                    dbg "Grabbing Context parameter: '$arg'."
                    CONTEXT=$(realpath -e -P $arg || die_help "$E_CONTEXT '$arg'")
                else
                    # Properly handle any embedded special characters
                    BUILD_ARGS+=($(printf "%q" "$arg"))
                fi
                ;;
        esac
    done
    if ((PUSH)) && [[ -n "$NAMESPACE" ]]; then
        set +x # Don't expose any secrets if somehow we got into -x mode
        nsu_var="$(tr '[:lower:]' '[:upper:]'<<<${NAMESPACE})_USERNAME"
        nsp_var="$(tr '[:lower:]' '[:upper:]'<<<${NAMESPACE})_PASSWORD"
        dbg "Confirming non-empty \$$nsu_var and \$$nsp_var"
        # These will be unset after logging into the registry
        NAMESPACE_USERNAME="${!nsu_var}"
        NAMESPACE_PASSWORD="${!nsp_var}"
        # Leak as little as possible into any child processes
        unset "$nsu_var" "$nsp_var"
    fi

    # validate parsed argument contents
    if [[ -z "$FQIN" ]]; then
        die_help "$E_FQIN '<empty>'"
    elif [[ -z "$REGSERVER" ]] || [[ -z "$NAMESPACE" ]] || [[ -z "$IMGNAME" ]]; then
        die_help "$E_FQIN '$FQIN'"
    elif [[ -z "$CONTEXT" ]]; then
        die_help "$E_CONTEXT ''"
    fi
    test $(tr -d -c '/' <<<"$FQIN" | wc -c) = '2' || \
        die_help "$E_FQIN '$FQIN'"
    test -r "$CONTEXT/Containerfile" || \
        test -r "$CONTEXT/Dockerfile" || \
        die_help "Given context path does not contain a Containerfile or Dockerfile: '$CONTEXT'"

    if ((PUSH)); then
        test -n "$NAMESPACE_USERNAME" || \
            die_help "$E_USERPASS '\$$nsu_var'"
        test -n "$NAMESPACE_PASSWORD" || \
            die_help "$E_USERPASS '\$$nsp_var'"
    fi

    dbg "Processed:
    RUNTIME='$RUNTIME'
    FQIN='$FQIN'
    CONTEXT='$CONTEXT'
    PUSH='$PUSH'
    ARCHES='$ARCHES'
    MODCMD='$MODCMD'
    BUILD_ARGS=$(echo -n "${BUILD_ARGS[@]}")
    REGSERVER='$REGSERVER'
    NAMESPACE='$NAMESPACE'
    IMGNAME='$IMGNAME'
    namespace username chars: '${#NAMESPACE_USERNAME}'
    namespace password chars: '${#NAMESPACE_PASSWORD}'
"
}

# Build may have a LOT of output, use a standard  stage-marker
# to ease reading and debugging from the wall-o-text
stage_notice() {
    local msg
    # N/B: It would be nice/helpful to resolve any env. vars. in '$@'
    #      for display.  Unfortunately this is hard to do safely
    #      with (e.g.) eval echo "$@" :(
    msg="$@"
    (
        echo "############################################################"
        echo "$msg"
        echo "############################################################"
    ) > /dev/stderr
}

BUILTIID=""    # populated with the image-id on successful build
parallel_build() {
    local arch
    local platforms=""
    local output
    local _fqin
    local -a _args

    _fqin="$1"
    dbg "in parallel_build($_fqin)"
    req_env_vars FQIN ARCHES CONTEXT REGSERVER NAMESPACE IMGNAME
    req_env_vars PARALLEL_JOBS PLATFORMOS RUNTIME _fqin

    for arch in $ARCHES; do
        platforms="${platforms:+$platforms,}$PLATFORMOS/$arch"
    done

    # Need to build up the command from parts b/c array conversion is handled
    # in strange and non-obvious ways when it comes to embedded whitespace.
    _args=(--layers --force-rm --jobs="$PARALLEL_JOBS" --platform="$platforms"
           --manifest="$_fqin" "$CONTEXT")

    # Keep user-specified BUILD_ARGS near the beginning so errors are easy to spot
    # Provide a copy of the output in case something goes wrong in a complex build
    stage_notice "Executing build command: '$RUNTIME build ${BUILD_ARGS[@]} ${_args[@]}'"
    "$RUNTIME" build "${BUILD_ARGS[@]}" "${_args[@]}"
}

confirm_arches() {
    local filter=".manifests[].platform.architecture"
    local arch
    local maniarches

    dbg "in confirm_arches()"
    req_env_vars FQIN ARCHES RUNTIME
    maniarches=$($RUNTIME manifest inspect "containers-storage:$FQIN:latest" | \
                 jq -r "$filter" | \
                 grep -v 'null' | \
                 tr -s '[:space:]' ' ' | \
                 sed -z '$ s/[\n ]$//')
    dbg "Found manifest arches: $maniarches"

    for arch in $ARCHES; do
        grep -q "$arch" <<<"$maniarches" || \
            die "Failed to locate the $arch arch. in the $FQIN:latest manifest-list: $maniarches"
    done
}

registry_login() {
    dbg "in registry_login()"
    req_env_vars PUSH LOGGEDIN

    if ((PUSH)) && ! ((LOGGEDIN)); then
        req_env_vars NAMESPACE_USERNAME NAMESPACE_PASSWORD REGSERVER NAMESPACE
        dbg "    Logging in"
        echo "$NAMESPACE_PASSWORD" | \
            $RUNTIME login --username "$NAMESPACE_USERNAME" --password-stdin \
            "$REGSERVER/$NAMESPACE"
        LOGGEDIN=1
    else
        dbg "    Already logged in"
    fi

    # No reason to keep these around any longer
    unset NAMESPACE_USERNAME NAMESPACE_PASSWORD
}

run_prepmod_cmd() {
    local kind="$1"
    shift
    dbg "Exporting variables '$_CMD_ENV'"
    export $_CMD_ENV
    stage_notice "Executing $kind-command: " "$@"
    bash -c "$@"
    dbg "$kind command successful"
}

# Outputs sorted list of FQIN w/ tags to stdout, silent otherwise
get_manifest_tags() {
    local _json
    dbg "in get_manifest_fqins()"

    # At the time of this comment, there is no reliable way to
    # lookup all tags based solely on inspecting a manifest.
    # However, since we know $FQIN (remember, value has no tag) we can
    # use it to search all related names container storage. Unfortunately
    # because images can have multiple tags, the `reference` filter
    # can return names we don't care about.  Work around this by
    # sending the final result back through a grep of $FQIN
    _json=$($RUNTIME images --json --filter=reference=$FQIN)
    dbg "Image listing json: $_json"
    if [[ -n "$_json" ]] && jq --exit-status '.[].names' <<<"$_json" &>/dev/null
    then
        jq --raw-output '.[].names[]'<<<"$_json" | grep "$FQIN" | sort
    fi
}

push_images() {
    local _fqins
    local _fqin
    dbg "in push_images()"

    # It's possible that --modcmd=* removed all images, make sure
    # this is known to the caller.
    _fqins=$(get_manifest_tags)
    if [[ -z "$_fqins" ]]; then
        die "No FQIN(s) to be pushed."
    fi

    dbg "Will try to push FQINs: $_fqins"

    registry_login
    for _fqin in $_fqins; do
        # Note: --all means push manifest AND images it references
        msg "Pushing $_fqin"
        $RUNTIME manifest push --all $_fqin docker://$_fqin
    done
}

##### MAIN() #####

# Handle requested help first before anything else
if grep -q -- '--help' <<<"$@"; then
    echo "$E_USAGE" > /dev/stdout  # allow grep'ing
    exit 0
fi

init
parse_args "$@"
if [[ -n "$PREPCMD" ]]; then
    registry_login
    run_prepmod_cmd prep "$PREPCMD"
fi

parallel_build "$FQIN:latest"
confirm_arches
if [[ -n "$MODCMD" ]]; then
    registry_login
    run_prepmod_cmd mod "$MODCMD"
fi
if ((PUSH)); then push_images; fi
