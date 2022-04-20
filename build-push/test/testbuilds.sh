

# This script is intended to be sourced from testbin-build-push.sh.
# Any/all other usage is virtually guaranteed to fail and/or cause
# harm to the system.

for varname in RUNTIME TEST_FQIN BUILDAH_USERNAME BUILDAH_PASSWORD; do
    value=${!varname}
    if [[ -z "$value" ]]; then
        echo "ERROR: Required \$$varname variable is unset/empty."
        exit 1
    fi
done
unset value

$RUNTIME --version
test_cmd "Confirm $(basename $RUNTIME) is available" \
    0 "buildah version .+" \
    $RUNTIME --version

skopeo --version
test_cmd "Confirm skopeo is available" \
    0 "skopeo version .+" \
    skopeo --version

PREPCMD='echo "SpecialErrorMessage:$REGSERVER" > /dev/stderr && exit 42'
test_cmd "Confirm error output and exit(42) from --prepcmd" \
    42 "SpecialErrorMessage:localhost" \
    bash -c "$SUBJ_FILEPATH --nopush localhost/foo/bar $TEST_CONTEXT --prepcmd='$PREPCMD' 2>&1"

# N/B: The following are stateful - each depends on precedding test success
#      and assume empty container-storage (podman system reset).

test_cmd "Confirm building native-arch test image w/ --nopush" \
    0 "STEP 3/3: ENTRYPOINT /bin/false.+COMMIT" \
    bash -c "A_DEBUG=1 $SUBJ_FILEPATH localhost/foo/bar $TEST_CONTEXT --nopush 2>&1"

native_arch=$($RUNTIME info --format='{{.host.arch}}')
test_cmd "Confirm native_arch was set to non-empty string" \
    0 "" \
    test -n "$native_arch"

test_cmd "Confirm built image manifest contains the native arch '$native_arch'" \
    0 "$native_arch" \
    bash -c "$RUNTIME manifest inspect localhost/foo/bar:latest | jq -r '.manifests[0].platform.architecture'"

test_cmd "Confirm rebuilding with same command uses cache" \
    0 "STEP 3/3.+Using cache" \
    bash -c "A_DEBUG=1 $SUBJ_FILEPATH localhost/foo/bar $TEST_CONTEXT --nopush 2>&1"

test_cmd "Confirm manifest-list can be removed by name" \
    0 "untagged: localhost/foo/bar:latest" \
    $RUNTIME manifest rm containers-storage:localhost/foo/bar:latest

test_cmd "Verify expected partial failure when passing bogus architectures" \
     125 "error creating build.+architecture staple" \
    bash -c "A_DEBUG=1 $SUBJ_FILEPATH --arches=correct,horse,battery,staple localhost/foo/bar --nopush $TEST_CONTEXT 2>&1"

MODCMD='$RUNTIME tag $FQIN:latest $FQIN:9.8.7-testing'
test_cmd "Verify --modcmd is able to tag the manifest" \
    0 "Executing mod-command" \
    bash -c "A_DEBUG=1 $SUBJ_FILEPATH localhost/foo/bar $TEST_CONTEXT --nopush --modcmd='$MODCMD' 2>&1"

test_cmd "Verify the tagged manifest is also present" \
    0 "[a-zA-Z0-9]+" \
    bash -c "$RUNTIME images --quiet localhost/foo/bar:9.8.7-testing"

test_cmd "Confirm tagged image manifest contains native arch '$native_arch'" \
    0 "$native_arch" \
    bash -c "$RUNTIME manifest inspect localhost/foo/bar:9.8.7-testing | jq -r '.manifests[0].platform.architecture'"

TEST_TEMP=$(mktemp -d -p '' .tmp_$(basename ${BASH_SOURCE[0]})_XXXX)

test_cmd "Confirm digest can be obtained from 'latest' manifest list" \
    0 ".+" \
    bash -c "$RUNTIME manifest inspect localhost/foo/bar:latest | jq -r '.manifest[0].digest' | tee $TEST_TEMP/latest_digest"

test_cmd "Confirm digest can be obtained from '9.8.7-testing' manifest list" \
    0 ".+" \
    bash -c "$RUNTIME manifest inspect localhost/foo/bar:9.8.7-testing | jq -r '.manifest[0].digest' | tee $TEST_TEMP/tagged_digest"

test_cmd "Verify tagged manifest image digest matches the same in latest" \
    0 "" \
    test "$(<$TEST_TEMP/tagged_digest)" == "$(<$TEST_TEMP/latest_digest)"

MODCMD='
set -x;
$RUNTIME images && \
    $RUNTIME manifest rm containers-storage:$FQIN:latest && \
    $RUNTIME manifest rm containers-storage:$FQIN:9.8.7-testing && \
    echo "AllGone";
'
# TODO: Test fails due to: https://github.com/containers/buildah/issues/3490
# for now pretend it should exit(125) which will be caught when bug is fixed
# - causing it to exit(0) as it should
test_cmd "Verify --modcmd can execute a long string with substitutions" \
    125 "AllGone" \
    bash -c "A_DEBUG=1 $SUBJ_FILEPATH --modcmd='$MODCMD' localhost/foo/bar --nopush $TEST_CONTEXT 2>&1"

test_cmd "Verify previous --modcmd removed the 'latest' tagged image" \
    125 "image not known" \
    $RUNTIME images --quiet containers-storage:localhost/foo/bar:latest

test_cmd "Verify previous --modcmd removed the '9.8.7-testing' tagged image" \
    125 "image not known" \
    $RUNTIME images --quiet containers-storage:localhost/foo/bar:9.8.7-testing

FAKE_VERSION=$RANDOM
MODCMD="set -ex;
\$RUNTIME tag \$FQIN:latest \$FQIN:$FAKE_VERSION;
\$RUNTIME manifest rm \$FQIN:latest;"
test_cmd "Verify e2e workflow w/ additional build-args" \
    0 "Pushing $TEST_FQIN:$FAKE_VERSION" \
    bash -c "env A_DEBUG=1 $SUBJ_FILEPATH \
        --prepcmd='touch $TEST_SOURCE_DIRPATH/test_context/Containerfile' \
        --modcmd='$MODCMD' \
        --arches=amd64,s390x,arm64,ppc64le \
        $TEST_FQIN \
        $TEST_CONTEXT \
        --device=/dev/fuse --label testing=true \
        2>&1"

test_cmd "Verify latest tagged image was not pushed" \
    1 "(Tag latest was deleted or has expired.)|(manifest unknown: manifest unknown)" \
    skopeo inspect docker://$TEST_FQIN:latest

test_cmd "Verify architectures can be obtained from manifest list" \
    0 "" \
    bash -c "$RUNTIME manifest inspect $TEST_FQIN:$FAKE_VERSION | \
        jq -r '.manifests[].platform.architecture' > $TEST_TEMP/maniarches"

for arch in amd64 s390x arm64 ppc64le; do
    test_cmd "Verify $arch architecture present in $TEST_FQIN:$FAKE_VERSION" \
    0 "" \
    fgrep -qx "$arch" $TEST_TEMP/maniarches
done

test_cmd "Verify pushed image can be removed" \
    0 "" \
    skopeo delete docker://$TEST_FQIN:$FAKE_VERSION

# Cleanup
rm -rf "$TEST_TEMP"
