#!/bin/bash

# Unit-tests for library script in the current directory
# Also verifies test script is derived from library filename

# shellcheck source-path=./
source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
# Must be staticly defined, 'source-path' directive can't work here.
# shellcheck source=../lib/platform.sh disable=SC2154
source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

# For whatever reason, SCRIPT_PATH cannot be resolved.
# shellcheck disable=SC2154
test_cmd "Library $SUBJ_FILENAME is not executable" \
    0 "" \
    test ! -x "$SCRIPT_PATH/$SUBJ_FILENAME"

for var in OS_RELEASE_VER OS_RELEASE_ID OS_REL_VER; do
    test_cmd "The variable \$$var is defined and non-empty" \
        0 "" \
        test -n "${!var}"
done

for var in OS_RELEASE_VER OS_REL_VER; do
    NODOT=$(tr -d '.' <<<"${!var}")
    test_cmd "The '.' character does not appear in \$$var" \
        0 "" \
        test "$NODOT" == "${!var}"
done

for OS_RELEASE_ID in 'debian' 'ubuntu'; do
  (
    export _TEST_UID=$RANDOM  # Normally $UID is read-only
    # Must be staticly defined, 'source-path' directive can't work here.
    # shellcheck source=../lib/platform.sh disable=SC2154
    source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

    # The point of this test is to confirm it's defined
    # shellcheck disable=SC2154
    test_cmd "The '\$SUDO' env. var. is non-empty when \$_TEST_UID is non-zero" \
        0 "" \
        test -n "$SUDO"

    test_cmd "The '\$SUDO' env. var. contains 'noninteractive' when '\$_TEST_UID' is non-zero" \
        0 "noninteractive" \
        echo "$SUDO"
  )
done

test_cmd "The passthrough_envars() func. has output by default." \
  0 ".+" \
  passthrough_envars

(
    # Confirm defaults may be overriden
    PASSTHROUGH_ENV_EXACT="FOOBARBAZ"
    PASSTHROUGH_ENV_ATSTART="FOO"
    PASSTHROUGH_ENV_ANYWHERE="BAR"
    export FOOBARBAZ="testing"

    test_cmd "The passthrough_envars() func. w/ overriden expr. only prints name of test variable." \
      0 "FOOBARBAZ" \
      passthrough_envars
)

# Test from a mostly empty environment to limit possibility of expr mismatch flakes
declare -a printed_envs
readarray -t printed_envs <<<$(env --ignore-environment PATH="$PATH" FOOBARBAZ="testing" \
                               SECRET_ENV_RE="(^PATH$)|(^BASH_FUNC)|(^_.*)|(FOOBARBAZ)|(SECRET_ENV_RE)" \
                               CI="true" AUTOMATION_LIB_PATH="/path/to/some/place" \
                               bash -c "source $TEST_DIR/$SUBJ_FILENAME && passthrough_envars")

test_cmd "The passthrough_envars() func. w/ overriden \$SECRET_ENV_RE hides test variable." \
    1 "0" \
    expr match "${printed_envs[*]}" '.*FOOBARBAZ.*'

test_cmd "The passthrough_envars() func. w/ overriden \$SECRET_ENV_RE returns CI variable." \
    0 "[1-9]+[0-9]*" \
    expr match "${printed_envs[*]}" '.*CI.*'

# Must be last call
exit_with_status
