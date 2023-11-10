
# This library is intended to be sourced by other scripts inside this
# directory.  All other usage contexts may lead to unintended outcomes.
# only the IDs differ.  Assumes the sourcing script defines a `dbg()`
# function.

SCRIPT_FILENAME=$(basename "$0")  # N/B: Caller's arg0, not this library file path.
SCRIPT_DIRPATH=$(dirname "$0")
LIB_DIRPATH=$(dirname "${BASH_SOURCE[0]}")
TEMPDIR=$(mktemp -d -p '' "${SCRIPT_FILENAME}_XXXXX.tmp")
trap "rm -rf '$TEMPDIR'" EXIT

# Path to file recording one line per instance, with it's name, instance id, start
# date/time separated by a space.  Exceptional conditions are recorded as comments
# with the name and details.  File is refreshed/overwritten each time script runs
# without any fatal/uncaught command-errors.  Intended for reference by humans
# and/or other tooling.
PWSTATE="${PWSTATE:-$LIB_DIRPATH/pw_status.txt}"

# Name of launch template. Current/default version will be used.
# https://us-east-1.console.aws.amazon.com/ec2/home?region=us-east-1#LaunchTemplates:
TEMPLATE_NAME="${TEMPLATE_NAME:-CirrusMacM1PWinstance}"

# Path to scripts to copy/execute on Darwin instances
SETUP_SCRIPT="$LIB_DIRPATH/setup.sh"
SPOOL_SCRIPT="$LIB_DIRPATH/service_pool.sh"
CIENV_SCRIPT="$LIB_DIRPATH/ci_env.sh"

# Set to 1 to enable debugging
X_DEBUG="${X_DEBUG:-0}"

# AWS CLI command and general args
AWS="aws --no-paginate --output=json --color=off --no-cli-pager --no-cli-auto-prompt"

# Common ssh/scp arguments
SSH_ARGS="-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o CheckHostIP=no -F /dev/null -o LogLevel=ERROR -o ConnectTimeout=13"
# ssh/scp commands to run w/ arguments
SSH="${SSH:-ssh -n $SSH_ARGS}"  # N/B: default nulls stdin
SCP="${SCP:-scp -q $SSH_ARGS}"

# Indentation to prefix msg/warn/die messages with to assist humans understanding context.
_I="${_I:-}"

# Print details $1 (defaults to 1) calls above the caller in the stack.
# usage e.x. $(ctx 0) - print details about current function
#            $(ctx) - print details about current function's caller
#            $(ctx 2) - print details about current functions's caller's caller.
ctx() {
    local above level
    above=${1:-1}
    level=$((1+$above))
    script=$(basename ${BASH_SOURCE[$level]})
    echo "($script:${FUNCNAME[$level]}():${BASH_LINENO[$above]})"
}

msg() { echo "${_I}${1:-No text message provided}"; }
warn() { echo "${1:-No warning message provided}" | awk -e '{print "'"${_I}"'WARNING: "$0}' > /dev/stderr; }
die() { echo "${1:-No error message provided}" | awk -e '{print "'"${_I}"'ERROR: "$0}' > /dev/stderr; exit 1; }
dbg() {
  if ((X_DEBUG)); then
      msg "${1:-No debug message provided} $(ctx 1)" | awk -e '{print "'"${_I}"'DEBUG: "$0}' > /dev/stderr
  fi
}

# Obtain a JSON string value by running the provided query filter (arg 1) on
# JSON file (arg 2).  Return non-zero on jq error (1), or if value is empty
# or null (2).  Otherwise print value and return 0.
jq_errf="$TEMPDIR/jq_error.output"
json_query() {
    local value
    local indent="         "
    dbg "jq filter $1
$indent on $(basename $2) $(ctx)"
    if ! value=$(jq -r "$1" "$2" 2>"$jq_errf"); then
        dbg "$indent error: $(<$jq_errf)"
        return 1
    fi

    if [[ -z "$value" ]] || [[ "$value" == "null" ]]; then
        dbg "$indent result: Empty or null"
        return 2
    fi

    dbg "$indent result: '$value'"
    echo "$value"
    return 0
}
