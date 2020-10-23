
# This library simply sources the necessary common libraries.
# Not intended for direct execution
AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(dirname $(realpath ${BASH_SOURCE[0]}))/../../common/lib}"
GITHUB_ACTION_LIB="${GITHUB_ACTION_LIB:-$AUTOMATION_LIB_PATH/github_common.sh}"
# Allow in-place use w/o installing, e.g. for testing
[[ -r "$GITHUB_ACTION_LIB" ]] || \
    GITHUB_ACTION_LIB="$AUTOMATION_LIB_PATH/../../github/lib/github_common.sh"
# Also loads common lib
source "$GITHUB_ACTION_LIB"
