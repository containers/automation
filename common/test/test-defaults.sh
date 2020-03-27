#!/bin/bash

source $(dirname $0)/testlib.sh || exit 1

# CI must only/always be either 'true' or 'false'.
# Usage: test_ci <initial value> <expected value>
test_ci() {
    local prev_CI="$CI"
    CI="$1"
    source "$TEST_DIR"/"$SUBJ_FILENAME"
    test_cmd "Defaults library successfully (re-)loaded" \
        0 "" \
        test "$?" -eq 0
    test_cmd "\$CI='$1' becomes 'true' or 'false'" \
        0 "" \
        test "$CI" = "true" -o "$CI" = "false"
    test_cmd "\$CI value '$2' was expected" \
        0 "" \
        test "$CI" = "$2"
    CI="$prev_CI"
}

# DEBUG must default to 0 or non-zero
# usage: <expected non-zero> [initial_value]
test_debug() {
    local exp_non_zero=$1
    local init_value="$2"
    [[ -z "$init_value" ]] || \
        DEBUG=$init_value
    local desc_pfx="The \$DEBUG env. var initialized '$init_value', after loading library is"

    source "$TEST_DIR"/"$SUBJ_FILENAME"
    if ((exp_non_zero)); then
        test_cmd "$desc_pfx non-zero" \
            0 "" \
            test "$DEBUG" -ne 0
    else
        test_cmd "$desc_pfx zero" \
            0 "" \
            test "$DEBUG" -eq 0
    fi
}

test_ci "" "false"
test_ci "$RANDOM" "true"
test_ci "FoObAr" "true"
test_ci "false" "false"
test_ci "true" "true"

test_debug 0
test_debug 0 0
test_debug 1 1
test_debug 1 true
test_debug 1 false

# script is set +e
exit_with_status
