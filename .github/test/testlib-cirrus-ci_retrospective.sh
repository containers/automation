#!/bin/bash

source $(dirname $BASH_SOURCE[0])/testlib.sh

test_cmd "The library $TEST_DIR/$SUBJ_FILENAME loads" \
    0 '' \
    source $TEST_DIR/$SUBJ_FILENAME

source $TEST_DIR/$SUBJ_FILENAME

test_cmd 'These tests are running in a github actions workflow environment' \
    0 '' \
    test "$GITHUB_ACTIONS" == "true"

test_cmd 'Default shell variables are initialized empty/false' \
    0 '^falsefalse$' \
    echo -n "${prn}${tid}${sha}${tst}${was_pr}${do_intg}"

# Remaining tests all require debuging output to be enabled
DEBUG=1

test_cmd 'The debugging function does not throw any errors and uses special debug output' \
    0 'DEBUG:' \
    dbg_ccir

test_cmd "The \$MONITOR_TASK variable is defined an non-empty" \
    0 '^.+' \
    echo -n "$MONITOR_TASK"

test_cmd "The \$ACTION_TASK variable is defined an non-empty" \
    0 '^.+' \
    echo -n "$ACTION_TASK"

MONITOR_TASK=TEST_MONITOR_TASK_NAME
ACTION_TASK=TEST_ACTION_TASK_NAME
TESTTEMPDIR=$(mktemp -p '' -d "tmp_${SUBJ_FILENAME}_XXXXXXXX")
trap "rm -rf $TESTTEMPDIR" EXIT

# usage: write_ccir <id> <build_pullRequest> <build_changeIdInRepo> <action_status> <monitor_status>
write_ccir() {
    local id=$1
    local pullRequest=$2
    local changeIdInRepo=$3
    local action_status=$4
    local monitor_status=$5

    build_section="\"build\": {
                \"id\": \"1234567890\",
                \"changeIdInRepo\": \"$changeIdInRepo\",
                \"branch\": \"pull/$pullRequest\",
                \"pullRequest\": $pullRequest,
                \"status\": \"COMPLETED\"
            }"

    cat << EOF > $TESTTEMPDIR/cirrus-ci_retrospective.json
    [
        {
            "id": "$id",
            "name": "$MONITOR_TASK",
            "status": "$monitor_status",
            "automaticReRun": false,
            $build_section
        },
        {
            "id": "$id",
            "name": "$ACTION_TASK",
            "status": "$action_status",
            "automaticReRun": false,
            $build_section
        }
    ]
EOF
    if ((TEST_DEBUG)); then
        echo "Wrote JSON:"
        cat $TESTTEMPDIR/cirrus-ci_retrospective.json
    fi
}

write_ccir 10 12 13 14 15
# usage: write_ccir <id> <build_pullRequest> <build_changeIdInRepo> <action_status> <monitor_status>
for regex in '"id": "10"' $MONITOR_TASK $ACTION_TASK '"branch": "pull/12"' \
             '"changeIdInRepo": "13"' '"pullRequest": 12' '"status": "14"' \
             '"status": "15"'; do
    test_cmd "Verify test JSON can load with test values from $TESTTEMPDIR, and match '$regex'" \
        0 "$regex" \
        load_ccir "$TESTTEMPDIR"
done

# Remaining tests all require debuging output disabled
DEBUG=0

write_ccir 1 2 3 PAUSED COMPLETED
load_ccir "$TESTTEMPDIR"
for var in was_pr do_intg; do
    test_cmd "Verify JSON for a pull request sets \$$var=true" \
        0 '^true' \
        echo ${!var}
done

for stat in COMPLETED ABORTED FAILED YOMAMA SUCCESS SUCCESSFUL FAILURE; do
    write_ccir 1 2 3 $stat COMPLETED
    load_ccir "$TESTTEMPDIR"
    test_cmd "Verify JSON for a pull request sets \$do_intg=false when action status is $stat" \
        0 '^false' \
        echo $do_intg

    write_ccir 1 2 3 PAUSED $stat
    load_ccir "$TESTTEMPDIR"
    test_cmd "Verify JSON for a pull request sets \$do_intg=true when monitor status is $stat" \
        0 '^true' \
        echo $do_intg
done

for pr in "true" "false" "null" "0"; do
    write_ccir 1 "$pr" 3 PAUSED COMPLETED
    load_ccir "$TESTTEMPDIR"
    test_cmd "Verify \$do_intg=false and \$was_pr=false when JSON sets pullRequest=$pr" \
        0 '^falsefalse' \
        echo ${do_intg}${was_pr}
done

# Must be the last command in this file
exit_with_status
