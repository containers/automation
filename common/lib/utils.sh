
# Library of utility functions for manipulating/controling bash-internals
# Not intended to be executed directly

source $(dirname $(realpath "${BASH_SOURCE[0]}"))/console_output.sh

# TODO: Add unit test
copy_function() {
    local src="$1"
    local dst="$2"
    [[ -n "$src" ]] || \
        die "Expecting source function name to be passed as the first argument"
    [[ -n "$dst" ]] || \
        die "Expecting destination function name to be passed as the second argument"
    src_def=$(declare -f "$src") || [[ -n "$src_def" ]] || \
        die "Unable to find source function named ${src}()"
    dbg "Copying function ${src}() to ${dst}()"
    # First match of $src replaced by $dst
    eval "${src_def/$src/$dst}"
}

# TODO: Add unit test
rename_function() {
    local from="$1"
    local to="$2"
    [[ -n "$from" ]] || \
        die "Expecting current function name to be passed as the first argument"
    [[ -n "$to" ]] || \
        die "Expecting desired function name to be passed as the second argument"
    dbg "Copying function ${from}() to ${to}() before unlinking ${from}()"
    copy_function "$from" "$to"
    dbg "Undefining function $from"
    unset -f "$from"
}
