
# This library simply sources the necessary common libraries.
# Not intended for direct execution
AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(dirname $(realpath ${BASH_SOURCE[0]}))/../../common/lib}"
source "$AUTOMATION_LIB_PATH/defaults.sh"
source "$AUTOMATION_LIB_PATH/anchors.sh"
source "$AUTOMATION_LIB_PATH/console_output.sh"
source "$AUTOMATION_LIB_PATH/utils.sh"
