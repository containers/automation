
# A Library for anchoring scripts and other files relative to it's
# filesystem location.  Not intended be executed directly.

# Absolute realpath anchors for important directory tree roots.
AUTOMATION_LIB_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))  # THIS file's directory
AUTOMATION_ROOT=$(realpath "$AUTOMATION_LIB_PATH/../")  # THIS file's parent directory
SCRIPT_PATH=$(realpath "$(dirname $0)")  # Source script's directory
SCRIPT_FILENAME=$(basename $0)  # Source script's file
MKTEMP_FORMAT=".tmp_${SCRIPT_FILENAME}_XXXXXXXX"  # Helps reference source

automation_version() {
    local git_cmd="git describe HEAD"
    cd "$AUTOMATION_ROOT"
    if [[ -r "AUTOMATION_VERSION" ]]; then
       cat "AUTOMATION_VERSION"
    elif [[ -n "$(type -P git)" ]] && $git_cmd &> /dev/null; then
        $git_cmd
    else
        echo "Error determining version number" > /dev/stderr
        exit 1
    fi
}
