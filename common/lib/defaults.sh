
# Library of default env. vars. for inclusion under all contexts.
# Not intended to be executed directly

# Set non-'false' by nearly every CI system in existence.
CI="${CI:-false}"  # true: _unlikely_ human-presence at the controls.
[[ $CI == "false" ]] || CI='true'  # Err on the side of automation

# Default to NOT running in debug-mode unless set non-zero
A_DEBUG=${A_DEBUG:-0}
# Conditionals like ((A_DEBUG)) easier than checking "true"/"False"
( test "$A_DEBUG" -eq 0 || test "$A_DEBUG" -ne 0 ) &>/dev/null || \
    A_DEBUG=1  # assume true when non-integer

# String prefixes to use when printing messages to the console
DEBUG_MSG_PREFIX="${DEBUG_MSG_PREFIX:-DEBUG:}"
WARNING_MSG_PREFIX="${WARNING_MSG_PREFIX:-WARNING:}"
ERROR_MSG_PREFIX="${ERROR_MSG_PREFIX:-ERROR:}"

# When non-empty, should contain a regular expression that matches
# any known or potential env. vars containing secrests or other
# sensitive values.  For example `(.+PASSWORD.*)|(.+SECRET.*)|(.+TOKEN.*)`
SECRET_ENV_RE=''
