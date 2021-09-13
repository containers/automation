#!/bin/bash

TEST_SOURCE_DIRPATH=$(realpath $(dirname "${BASH_SOURCE[0]}"))

# Load standardized test harness
source $TEST_SOURCE_DIRPATH/testlib.sh || exit 1

SUBJ_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"
TEST_CONTEXT="$TEST_SOURCE_DIRPATH/test_context"
EMPTY_CONTEXT=$(mktemp -d -p '' .tmp_$(basename ${BASH_SOURCE[0]})_XXXX)

test_cmd "Verify error when automation library not found" \
    2 'ERROR: Expecting \$AUTOMATION_LIB_PATH' \
    bash -c "AUTOMATION_LIB_PATH='' RUNTIME=/bin/true $SUBJ_FILEPATH 2>&1"

export AUTOMATION_LIB_PATH="$TEST_SOURCE_DIRPATH/../../common/lib"

test_cmd "Verify error when buildah can't be found" \
    1 "ERROR:.+find buildah.+/usr/local/bin" \
    bash -c "RUNTIME=/bin/true $SUBJ_FILEPATH 2>&1"

# Support basic testing w/o a buildah binary available
export RUNTIME="${RUNTIME:-$(type -P buildah)}"
export NATIVE_GOARCH="${NATIVE_GOARCH:-$($RUNTIME info --format='{{.host.arch}}')}"
export PARALLEL_JOBS="${PARALLEL_JOBS:-$($RUNTIME info --format='{{.host.cpus}}')}"

# These tests don't actually need to actually build/run anything
export OLD_RUNTIME="$RUNTIME"
export RUNTIME="$TEST_SOURCE_DIRPATH/fake_buildah.sh"

test_cmd "Verify error when executed w/o any arguments" \
    1 "ERROR: Must.+required arguments." \
    bash -c "$SUBJ_FILEPATH 2>&1"

test_cmd "Verify error when specify partial required arguments" \
    1 "ERROR: Must.+required arguments." \
    bash -c "$SUBJ_FILEPATH foo 2>&1"

test_cmd "Verify error when executed bad Containerfile directory" \
    1 "ERROR:.+directory: 'bar'" \
    bash -c "$SUBJ_FILEPATH foo bar 2>&1"

test_cmd "Verify error when specify invalid FQIN" \
    1 "ERROR:.+FQIN.+foo" \
    bash -c "$SUBJ_FILEPATH foo $EMPTY_CONTEXT 2>&1"

test_cmd "Verify error when specify slightly invalid FQIN" \
    1 "ERROR:.+FQIN.+foo/bar" \
    bash -c "$SUBJ_FILEPATH foo/bar $EMPTY_CONTEXT 2>&1"

test_cmd "Verify error when executed bad context subdirectory" \
    1 "ERROR:.+Containerfile or Dockerfile: '$EMPTY_CONTEXT'" \
    bash -c "$SUBJ_FILEPATH foo/bar/baz $EMPTY_CONTEXT 2>&1"

# no-longer needed
rm -rf "$EMPTY_CONTEXT"
unset EMPTY_CONTEXT

test_cmd "Verify --help output to stdout can be grepped" \
    0 "Optional Environment Variables:" \
    bash -c "$SUBJ_FILEPATH --help | grep 'Optional Environment Variables:'"

test_cmd "Confirm required username env. var. unset error" \
    1 "ERROR.+BAR_USERNAME" \
    bash -c "$SUBJ_FILEPATH foo/bar/baz $TEST_CONTEXT 2>&1"

test_cmd "Confirm required password env. var. unset error" \
    1 "ERROR.+BAR_PASSWORD" \
    bash -c "BAR_USERNAME=snafu $SUBJ_FILEPATH foo/bar/baz $TEST_CONTEXT 2>&1"

for arg in 'prepcmd' 'modcmd'; do
    test_cmd "Verify error when --$arg specified without an '='" \
        1 "ERROR:.+with '='" \
        bash -c "BAR_USERNAME=snafu BAR_PASSWORD=ufans $SUBJ_FILEPATH foo/bar/baz $TEST_CONTEXT --$arg notgoingtowork 2>&1"
done

# A specialized non-container environment required to run these
if [[ -n "$BUILD_PUSH_TEST_BUILDS" ]]; then
    unset RUNTIME NATIVE_GOARCH PARALLEL_JOBS
    RUNTIME="$OLD_RUNTIME"
    export RUNTIME

    source $(dirname "${BASH_SOURCE[0]}")/testbuilds.sh
else
    echo "WARNING: Set \$BUILD_PUSH_TEST_BUILDS non-empty to fully test build_push."
    echo ""
fi

# Must always happen last
exit_with_status
