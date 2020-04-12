
# This file is intended for sourcing by github action workflows
# It should not be used under any other context.

# Important paths defined here
source $(dirname $BASH_SOURCE[0])/../../common/lib/anchors.sh || exit 1

# Override default library message prefixes to those consumed by Github Actions
# https://help.github.com/en/actions/reference/workflow-commands-for-github-actions
# Doesn't work properly w/o $ACTIONS_STEP_DEBUG=true
# DEBUG_MSG_PREFIX="::debug::"
WARNING_MSG_PREFIX="::warning::"
ERROR_MSG_PREFIX="::error::"
source $AUTOMATION_LIB_PATH/defaults.sh || exit 1
source $AUTOMATION_LIB_PATH/console_output.sh || exit 1

# usage: set_out_var <name> [value...]
set_out_var() {
    name=$1
    shift
    value="$@"
    [[ -n $name ]] || \
        die "Expecting first parameter to be non-empty value for the output variable name"
    dbg "Setting Github Action step output variable '$name' to '$value'"
    # Special string recognized by Github Actions
    printf "\n::set-output name=$name::%s\n" "$value"
}
