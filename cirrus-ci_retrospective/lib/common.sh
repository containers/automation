
# This library simply sources the necessary common libraries.
# Not intended for direct execution
AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(dirname ${BASH_SOURCE[0]})/../../common/lib}"
# Magic prefixes that receive special treatment by Github Actions
# Ref: https://help.github.com/en/actions/reference/workflow-commands-for-github-actions
DEBUG_MSG_PREFIX="${DEBUG_MSG_PREFIX:-::debug::}"
WARNING_MSG_PREFIX="${WARNING_MSG_PREFIX:-::warning::}"
ERROR_MSG_PREFIX="${ERROR_MSG_PREFIX:-::error::}"
source "$AUTOMATION_LIB_PATH/defaults.sh"
source "$AUTOMATION_LIB_PATH/anchors.sh"
source "$AUTOMATION_LIB_PATH/console_output.sh"
