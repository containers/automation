#!/bin/bash

# Load standardized test harness
SCRIPT_DIRPATH=$(dirname "${BASH_SOURCE[0]}")
source ${SCRIPT_DIRPATH}/testlib.sh || exit 1

TEST_DIR=$(realpath "$SCRIPT_DIRPATH/../")
SUBJ_FILEPATH="$TEST_DIR/${SUBJ_FILENAME%.sh}.py"

test_cmd "Verify no options results in help and an error-exit" \
    2 "cirrus-ci_env.py: error: the following arguments are required:" \
    $SUBJ_FILEPATH

test_cmd "Verify missing/invalid filename results in help and an error-exit" \
    2 "No such file or directory" \
    $SUBJ_FILEPATH /path/to/not/existing/file.yml \

test_cmd "Verify missing mode-option results in help message and an error-exit" \
    2 "error: one of the arguments --list --envs --inst is required" \
    $SUBJ_FILEPATH $SCRIPT_DIRPATH/actual_cirrus.yml

test_cmd "Verify valid-YAML w/o tasks results in help message and an error-exit" \
    1 "ERROR: No Cirrus-CI tasks found in" \
    $SUBJ_FILEPATH --list $SCRIPT_DIRPATH/expected_cirrus.yml

CIRRUS=$SCRIPT_DIRPATH/actual_cirrus.yml
test_cmd "Verify invalid task name results in help message and an error-exit" \
    1 "ERROR: Unknown task name 'foobarbaz' from" \
    $SUBJ_FILEPATH --env foobarbaz $CIRRUS

TASK_NAMES=$(<"$SCRIPT_DIRPATH/actual_task_names.txt")
echo "$TASK_NAMES" | while read LINE; do
    test_cmd "Verify task '$LINE' appears in task-listing output" \
    0 "$LINE" \
    $SUBJ_FILEPATH --list $CIRRUS
done

test_cmd "Verify inherited instance image with env. var. reference is rendered" \
    0 "container quay.io/libpod/fedora_podman:c6524344056676352" \
    $SUBJ_FILEPATH --inst 'Ext. services' $CIRRUS

test_cmd "Verify DISTRO_NV env. var renders correctly from test task" \
    0 'DISTRO_NV="fedora-33"' \
    $SUBJ_FILEPATH --env 'int podman fedora-33 root container' $CIRRUS

test_cmd "Verify VM_IMAGE_NAME env. var renders correctly from test task" \
    0 'VM_IMAGE_NAME="fedora-c6524344056676352"' \
    $SUBJ_FILEPATH --env 'int podman fedora-33 root container' $CIRRUS

exit_with_status
