
# A Library for anchoring scripts and other files relative to it's
# filesystem location.  Not intended be executed directly.

# Absolute realpath anchors for important directory tree roots.
AUTOMATION_LIB_PATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))  # THIS file's directory
AUTOMATION_ROOT=$(realpath "$AUTOMATION_LIB_PATH/../")  # THIS file's parent directory
SCRIPT_PATH=$(realpath "$(dirname $0)")  # Source script's directory
SCRIPT_FILENAME=$(basename $0)  # Source script's file
MKTEMP_FORMAT=".tmp_${SCRIPT_FILENAME}_XXXXXXXX"  # Helps reference source

_avcache="$AUTOMATION_VERSION"  # cache, DO NOT USE (except for unit-tests)
automation_version() {
    local gitbin="$(type -P git)"
    if [[ -z "$_avcache" ]]; then
        if [[ -r "$AUTOMATION_ROOT/AUTOMATION_VERSION" ]]; then
            _avcache=$(<"$AUTOMATION_ROOT/AUTOMATION_VERSION")
        # The various installers and some unit-tests rely on git in this way
        elif [[ -x "$gitbin" ]] && [[ -d "$AUTOMATION_ROOT/../.git" ]]; then
            local gitoutput
            # Avoid dealing with $CWD during error conditions - do it in a sub-shell
            if gitoutput=$(cd "$AUTOMATION_ROOT"; $gitbin describe HEAD; exit $?); then
                _avcache=$gitoutput
            fi
        fi
    fi

    if [[ -n "$_avcache" ]]; then
        echo "$_avcache"
    else
        echo "Error determining version number" > /dev/stderr
        exit 1
    fi
}
