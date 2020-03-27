
# Library of default env. vars. for inclusion under all contexts.
# Not intended to be executed directly

# Set non-'false' by nearly every CI system in existence.
CI="${CI:-false}"  # true: _unlikely_ human-presence at the controls.
[[ $CI == "false" ]] || CI='true'  # Err on the side of automation

# Default to NOT running in debug-mode unless set non-zero
DEBUG=${DEBUG:-0}
# Conditionals like ((DEBUG)) easier than checking "true"/"False"
( test "$DEBUG" -eq 0 || test "$DEBUG" -ne 0 ) &>/dev/null || DEBUG=1  # assume true when non-integer
