
# A Library for anchoring scripts and other files relative to it's
# filesystem location.  Not intended be executed directly.

# Absolute realpath anchors for important directory tree roots.
COMMON_LIB_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))  # THIS file's directory path
REPO_ROOT=$(realpath "$COMMON_LIB_PATH/../../")  # Specific to THIS repository & file
SCRIPT_FILENAME=$(basename $0)  # Source script's file
SCRIPT_PATH=$(realpath "$(dirname $0)")  # Source script's directory
SCRIPT_LIB_PATH=$(realpath "$SCRIPT_PATH/../lib/")  # Assumes FHS-like structure
MKTEMP_FORMAT=".tmp_${SCRIPT_FILENAME}_XXXXXXXX"  # Helps reference source
