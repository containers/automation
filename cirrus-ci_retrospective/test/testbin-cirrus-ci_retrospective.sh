#!/bin/bash

# Load standardized test harness
source $(dirname "${BASH_SOURCE[0]}")/testlib.sh || exit 1

# Would otherwise get in the way of checking output & removing $TMPDIR
DEBUG=0
SUBJ_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"

##### MAIN() #####

# ref: https://help.github.com/en/actions/configuring-and-managing-workflows/using-environment-variables#default-environment-variables
req_env_vars=(GITHUB_ACTIONS GITHUB_EVENT_NAME GITHUB_EVENT_PATH GITHUB_TOKEN GITHUB_WORKSPACE)
# Script may actually be running under Github Actions
declare -A original_values
original_values[GITHUB_ACTIONS]="$GITHUB_ACTIONS"
original_values[GITHUB_EVENT_NAME]="$GITHUB_EVENT_NAME"
original_values[GITHUB_EVENT_PATH]="$GITHUB_EVENT_PATH"
original_values[GITHUB_TOKEN]="$GITHUB_TOKEN"
original_values[GITHUB_WORKSPACE]="$GITHUB_WORKSPACE"

declare -A valid_values
valid_values[GITHUB_ACTIONS]="true"
valid_values[GITHUB_EVENT_NAME]="check_suite"
valid_values[GITHUB_EVENT_PATH]="/etc/passwd-"
valid_values[GITHUB_TOKEN]="$RANDOM"
valid_values[GITHUB_WORKSPACE]="$HOME"

declare -A invalid_values
invalid_values[GITHUB_ACTIONS]="false"
invalid_values[GITHUB_EVENT_NAME]="$RANDOM"
invalid_values[GITHUB_EVENT_PATH]="$RANDOM"
invalid_values[GITHUB_TOKEN]=""
invalid_values[GITHUB_WORKSPACE]="/etc/passwd-"

# Set all to known, valid, dummy values
for required_var in $req_env_vars; do
    export $required_var="${valid_values[$required_var]}"
done

# Don't depend on the order these are checked in the subject
for required_var in ${req_env_vars[@]}; do
    valid_value="${valid_values[$required_var]}"
    invalid_value="${invalid_values[$required_var]}"
    export $required_var="$invalid_value"
    test_cmd \
        "Verify exeuction w/ \$$required_var='$invalid_value' (instead of '$valid_value') fails with helpful error message." \
        2 "::error::.+\\\$$required_var.+'$invalid_value'" \
        $SUBJ_FILEPATH
    export $required_var="$valid_value"
done

# Setup to feed test Github Action event JSON
TESTTEMPDIR=$(mktemp -p '' -d tmp_${SUBJ_FILENAME}_XXXXXXXX)
trap "rm -rf $TESTTEMPDIR" EXIT
MOCK_EVENT_JSON_FILEPATH=$(mktemp -p "$TESTTEMPDIR" mock_event_XXXXXXXX.json)
cat << EOF > "$MOCK_EVENT_JSON_FILEPATH"
{}
EOF

export GITHUB_EVENT_PATH=$MOCK_EVENT_JSON_FILEPATH

test_cmd "Verify expected error when fed empty mock event JSON file" \
    1 "::error::.+check_suite.+key" \
    $SUBJ_FILEPATH

cat << EOF > "$MOCK_EVENT_JSON_FILEPATH"
{"check_suite":{}}
EOF
test_cmd "Verify expected error when fed invalid check_suite value in mock event JSON file" \
    1 "::error::.+check_suite.+type.+null" \
    $SUBJ_FILEPATH

cat << EOF > "$MOCK_EVENT_JSON_FILEPATH"
{"check_suite": {}, "action": "foobar"}
EOF
test_cmd "Verify error and message containing incorrect value from mock event JSON file" \
    1 "::error::.+check_suite.+foobar" \
    $SUBJ_FILEPATH

cat << EOF > "$MOCK_EVENT_JSON_FILEPATH"
{"check_suite": {"app":false}, "action": "completed"}
EOF
test_cmd "Verify expected error when check_suite's 'app' map is wrong type in mock event JSON file" \
    5 "jq: error.+boolean.+id" \
    $SUBJ_FILEPATH

cat << EOF > "$MOCK_EVENT_JSON_FILEPATH"
{"check_suite": {"app":{"id":null}}, "action": "completed"}
EOF
test_cmd "Verify expected error when 'app' id is wrong type in mock event JSON file" \
    1 "::error::.+integer.+null" \
    $SUBJ_FILEPATH

# Must always happen last
for required_var in $req_env_vars; do
    export $required_var="${original_values[$required_var]}"
done
exit_with_status
