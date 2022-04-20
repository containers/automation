

# A Library of contextual console output-related operations.
# Intended for use by other scripts, not to be executed directly.

source $(dirname $(realpath "${BASH_SOURCE[0]}"))/defaults.sh

# helper, not intended for use outside this file
_rel_path() {
    if [[ -z "$1" ]]; then
        echo "<stdin>"
    else
        local abs_path=$(realpath "$1")
        local rel_path=$(realpath --relative-to=. $abs_path)
        local abs_path_len=${#abs_path}
        local rel_path_len=${#rel_path}
        if ((abs_path_len <= rel_path_len)); then
            echo "$abs_path"
        else
            echo "$rel_path"
        fi
    fi
}

# helper, not intended for use outside this file
_ctx() {
    # Caller's caller details
    local shortest_source_path=$(_rel_path "${BASH_SOURCE[3]}")
    local grandparent_func="${FUNCNAME[2]}"
    [[ -n "$grandparent_func" ]] || \
        grandparent_func="main"
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
    local exit_code=${2:-1}
    ((exit_code==0)) || \
        exit $exit_code
}

dbg() {
    if ((A_DEBUG)); then
        local shortest_source_path=$(_rel_path "${BASH_SOURCE[1]}")
        (
        echo
        echo "$DEBUG_MSG_PREFIX ${1:-No debugging message given} ($shortest_source_path:${BASH_LINENO[0]} in ${FUNCNAME[1]}())"
        ) > /dev/stderr
    fi
}

msg() {
    echo "${1:-No message specified}" &> /dev/stderr
}

# Mimic set +x for a single command, along with calling location and line.
showrun() {
    local -a context
    context=($(caller 0))
    echo "+ $@  # ${context[2]}:${context[0]} in ${context[1]}()" > /dev/stderr
    "$@"
}

# Expects stdin, indents every input line right by 4 spaces
indent(){
    cat - |& while IFS='' read -r LINE; do
         awk '{print "    "$0}' <<<"$LINE"
    done
}

req_env_vars(){
    dbg "Confirming non-empty vars for $*"
    local var_name
    local var_value
    local msgpfx
    for var_name in "$@"; do
        var_value=$(tr -d '[:space:]' <<<"${!var_name}")
        msgpfx="Environment variable '$var_name'"
        ((${#var_value}>0)) || \
            die "$msgpfx is required by $(_rel_path "${BASH_SOURCE[1]}"):${FUNCNAME[1]}() but empty or entirely white-space."
    done
}

show_env_vars() {
    local filter_rx
    local env_var_names
    filter_rx='(^PATH$)|(^BASH_FUNC)|(^_.*)'
    msg "Selection of current env. vars:"
    if [[ -n "${SECRET_ENV_RE}" ]]; then
        filter_rx="${filter_rx}|$SECRET_ENV_RE"
    else
        warn "The \$SECRET_ENV_RE var. unset/empty: Not filtering sensitive names!"
    fi

    for env_var_name in $(awk 'BEGIN{for(v in ENVIRON) print v}' | grep -Eiv "$filter_rx" | sort -u); do

        line="${env_var_name}=${!env_var_name}"
        msg "    $line"
    done
}
