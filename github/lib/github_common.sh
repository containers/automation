
# This file is intended for sourcing by github action workflows
# It should not be used under any other context.

# Important paths defined here
AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(realpath $(dirname ${BASH_SOURCE[0]})/../../common/lib)}"

source $AUTOMATION_LIB_PATH/common_lib.sh || exit 1

# Wrap the die() function to add github-action sugar that identifies file
# & line number within the UI, before exiting non-zero.
rename_function die _die
die() {
    # https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-error-message
    local ERROR_MSG_PREFIX
    ERROR_MSG_PREFIX="::error file=${BASH_SOURCE[1]},line=${BASH_LINENO[0]}::"
    _die "$@"
}

# Wrap the warn() function to add github-action sugar that identifies file
# & line number within the UI.
rename_function warn _warn
warn() {
    local WARNING_MSG_PREFIX
    # https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-a-warning-message
    WARNING_MSG_PREFIX="::warning file=${BASH_SOURCE[1]},line=${BASH_LINENO[0]}::"
    _warn "$@"
}

# Idomatic debug messages in github-actions are worse than useless.  They do
# not embed file/line information.  They are completely hidden unless
# the $ACTIONS_STEP_DEBUG step or job variable is set 'true'. If setting
# this variable as a secret, can have unintended conseuqences:
# https://docs.github.com/en/actions/monitoring-and-troubleshooting-workflows/using-workflow-run-logs#viewing-logs-to-diagnose-failures
# Wrap the dbg() function to add github-action sugar at the "notice" level
# so that it may be observed in output by regular users without danger.
rename_function dbg _dbg
dbg() {
    # When set true, simply enable automation library debugging.
    if [[ "${ACTIONS_STEP_DEBUG:-false}" == 'true' ]]; then export A_DEBUG=1; fi

    # notice-level messages actually show up in the UI use them for debugging
    # https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-a-notice-message
    local DEBUG_MSG_PREFIX
    DEBUG_MSG_PREFIX="::notice file=${BASH_SOURCE[1]},line=${BASH_LINENO[0]}::"
    _dbg "$@"
}

# usage: set_out_var <name> [value...]
set_out_var() {
    A_DEBUG=0 req_env_vars GITHUB_OUTPUT
    name=$1
    shift
    value="$@"
    [[ -n $name ]] || \
        die "Expecting first parameter to be non-empty value for the output variable name"
    dbg "Setting Github Action step output variable '$name' to '$value'"
    # Special string recognized by Github Actions
    # Ref: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions#setting-an-output-parameter
    echo "$name=$value" >> $GITHUB_OUTPUT
}
