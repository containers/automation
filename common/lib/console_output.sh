

# A Library of contextual console output-related operations.
# Intended for use by other scripts, not to be executed directly.

source $(dirname "${BASH_SOURCE[0]}")/defaults.sh

# helper, not intended for use outside this file
_rel_path() {
    local abs_path=$(realpath "$1")
    local rel_path=$(realpath --relative-to=$PWD $abs_path)
    local abs_path_len=${#abs_path}
    local rel_path_len=${#rel_path}
    if ((abs_path_len <= rel_path_len)); then
        echo "$abs_path"
    else
        echo "$rel_path"
    fi
}

# helper, not intended for use outside this file
_ctx() {
    # Caller's caller details
    local shortest_source_path=$(_rel_path "${BASH_SOURCE[3]}")
    echo "$shortest_source_path:${BASH_LINENO[2]} in ${FUNCNAME[3]}()"
}

# helper, not intended for use outside this file.
_fmt_ctx() {
    local stars="************************************************"
    local prefix="${1:-no prefix given}"
    local message="${2:-no message given}"
    echo "$stars"
    echo "$prefix  ($(_ctx))"
    echo "$stars"
}

# Print a highly-visible message to stderr.  Usage: warn <msg>
warn() {
    _fmt_ctx "$WARNING_MSG_PREFIX ${1:-no warning message given}" > /dev/stderr
}

# Same as warn() but exit non-zero or with given exit code
# usage: die <msg> [exit-code]
die() {
    _fmt_ctx "$ERROR_MSG_PREFIX ${1:-no error message given}" > /dev/stderr
    exit ${2:-1}
}

dbg() {
    if ((DEBUG)); then
        local shortest_source_path=$(_rel_path "${BASH_SOURCE[1]}")
        (
        echo
        echo "$DEBUG_MSG_PREFIX ${1:-No debugging message given} ($shortest_source_path:${BASH_LINENO[0]} in ${FUNCNAME[1]}())"
        ) > /dev/stderr
    fi
}
