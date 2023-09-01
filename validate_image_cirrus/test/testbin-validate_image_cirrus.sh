#!/bin/bash

set -o pipefail

# Integration tests for validate_image_cirrus.py

BIN_DIR=$(realpath "$(dirname ${BASH_SOURCE[0]})/..")
BIN="$BIN_DIR/validate_image_cirrus.py"
REQS=$(realpath "$BIN_DIR/requirements.txt")
source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1

# A valid manifest-list FQIN to test against
VALID_ML_FQIN="quay.io/podman/stable:v3.4.4"
# A valid regular/single-arch image to test against
# must not clash with VALID_ML_FQIN
VALID_FQIN="quay.io/podman/stable:v2.1.1"

set -e

# Avoid needing to re-install all deps every test-run, re-use
# python venv if requirements file is unchanged.  Note: This
# will leak tempdirs when file does change between multiple runs.
REQ_SHA=$(cat $REQS | sha256sum | awk '{print $1}')
VENV_DIR="/var/tmp/validate_image_cirrus_venv_$REQ_SHA"
if [[ ! -d "$VENV_DIR" ]] || [[ ! -r "$VENV_DIR/good_to_go" ]]; then
  echo -e "\nCaching python deps, this may take a few minutes...\n"
  rm -f "$VENV_DIR/good_to_go"
  virtualenv "$VENV_DIR"
  source $VENV_DIR/bin/activate
  pip3 install --upgrade pip
  pip3 install --upgrade -r "$REQS"
  echo -e "\n\nDownloading test images, this may take several minutes...\n"
  SKOPEO="skopeo sync -a --scoped --preserve-digests -s docker -d dir"
  $SKOPEO "$VALID_ML_FQIN" "$VENV_DIR"
  $SKOPEO "$VALID_FQIN" "$VENV_DIR"
  touch "$VENV_DIR/good_to_go"
  echo ""
else
  echo -e "\n\nReusing cached python deps and test images...\n"
  source $VENV_DIR/bin/activate
fi

skopeo --version

# /tmp may be a ramdisk w/ limited space available
TMP=$(mktemp -p '/var/tmp' -d "validate_image_cirrus_tmp_XXXXX")
trap "rm -rf $TMP" EXIT

set +e

test_cmd "The script is runable and --help works" \
  0 "Show internal debugging/processing details" \
  $BIN --help

test_cmd "The script returns error when no argument given" \
  2 "usage:.+error:.+the following arguments are required" \
  $BIN

# The simple test image is missing otherwise required labels
# workaround this for general testing purposes.
RLARG="-l name,license,vendor,version"

# Confirm all test images validate
test_cmd "Script exits cleanly on all pulled known-clean test sources." \
  0 "Sanity: PASS" \
  $BIN -v $RLARG "$VENV_DIR/$VALID_FQIN" "$VENV_DIR/$VALID_ML_FQIN"

# Confirm both regular image and manifest-list
for fqin in $VALID_FQIN $VALID_ML_FQIN; do
  echo -e "\n##### Testing '$fqin' #####\n"

  # Confirm image validates before messing with contents
  test_cmd "Script exits cleanly on pulled known-clean test source for '$fqin'" \
    0 "Sanity: PASS" \
    $BIN -v $RLARG "$VENV_DIR/$fqin"

  # Confirm image matches with itself under another FQIN
  DIFFERENT_NAME="$TMP/${fqin%:*}:v$RANDOM"
  test_cmd "Verify image-match copy destination is absent" \
    0 "" \
    test ! -d "$DIFFERENT_NAME"

  mkdir -p "$DIFFERENT_NAME"
  cp -a "$VENV_DIR/$fqin"/* "$DIFFERENT_NAME"
  test_cmd "Script passes image-match test against a copy" \
    0 "All digests match.+N/A" \
    $BIN $RLARG -v -m "$VENV_DIR/$fqin" "$DIFFERENT_NAME"

  test_cmd "Script flags single-item matching check on '$fqin'" \
    1 "option specified with only one" \
    $BIN -v --matching "$VENV_DIR/$fqin"

  test_cmd "Script flags unexpected platforms" \
    10 "Expected platforms: FAIL" \
    $BIN -v $RLARG -p foo/bar,bar/foo "$VENV_DIR/$fqin"

  NO_TAG_FQIN_DIR="$TMP/${fqin%:*}"
  NO_TAG_PARENT_DIR="$TMP/$(dirname $fqin)/"
  mkdir -p "$NO_TAG_PARENT_DIR"
  cp -a "$VENV_DIR/$fqin" "$NO_TAG_PARENT_DIR"
  mv "$TMP/$fqin" "$NO_TAG_FQIN_DIR"
  test_cmd "A fqin dir w/ missing tag is rejected" \
    9 "Validation results.+FAIL.+ ':'" \
    $BIN -v $NO_TAG_FQIN_DIR

  NO_REG_PFX="$TMP/foo/bar:latest"
  mkdir -p "$NO_REG_PFX"
  mv "$NO_TAG_FQIN_DIR"/* "$NO_REG_PFX/"
  test_cmd "A fqin dir missing the reg-server is rejected" \
    9 "Validation results.+Missing.+quay\.io" \
    $BIN -v "$NO_REG_PFX"

  BAD_MANIFEST_FQIN_DIR="$TMP/${fqin}"
  cp -a "$VENV_DIR/$fqin" "$(dirname $BAD_MANIFEST_FQIN_DIR)"
  echo "$RANDOM$RANDOM}}[" >> "$BAD_MANIFEST_FQIN_DIR/manifest.json"
  test_cmd "A fqin dir w/ corrupt manifest.json is rejected" \
    9 "Validation results.+Failed to parse" \
    $BIN -v "$BAD_MANIFEST_FQIN_DIR"

  NO_MANIFEST_FQIN_DIR="$TMP/${fqin}"
  cp -a "$VENV_DIR/$fqin" "$(dirname $NO_MANIFEST_FQIN_DIR)"
  rm "$NO_MANIFEST_FQIN_DIR/manifest.json"
  test_cmd "A fqin dir missing a manifest.json is rejected" \
    9 "Validation results.+No manifest\\.json" \
    $BIN -v "$NO_MANIFEST_FQIN_DIR"
done

##### Warning: Fragile image-match failure test, sensitive
##### to loop order above.

test_cmd "Script passes image-match test against a copy" \
  10 "Matching Digests: FAIL.+Matching Digests: PASS.+N/A.+Matching Digests: FAIL" \
  $BIN $RLARG -v -m "$VENV_DIR/$VALID_ML_FQIN" "$DIFFERENT_NAME" "$VENV_DIR/$VALID_FQIN"

test_cmd "Script fails comparison between manifest-list and image" \
  10 "Matching Digests.+FAIL.+v2.1.1 \!\= quay.io/podman/stable:v[0-9]+" \
  $BIN $RLARG -m "$DIFFERENT_NAME" "$VENV_DIR/$VALID_FQIN"

##### Tests which only pertain to manifest-list

test_cmd "Default arguments work with manifest-list test image" \
  0 "Sanity: PASS.+Expected labels: PASS.+Expected platforms: PASS" \
  $BIN "$VENV_DIR/$VALID_ML_FQIN"

test_cmd "Skipping list-based checks works manifest-list test image" \
  0 "check skipped" \
  $BIN -r "" -p "" -l "" "$VENV_DIR/$VALID_ML_FQIN"


test_cmd "Script flags missing manifest-list labels" \
  10 "Missing labels: \['barfoo', 'foobar', 'snafu'\].+Expected labels: FAIL" \
  $BIN -v -l name,foobar,license,barfoo,vendor,version,snafu "$VENV_DIR/$VALID_ML_FQIN"

test_cmd "Script flags unexpected manifest-list platforms" \
  10 "DEBUG: Missing platforms: \['bar/foo', 'foo/bar', 'sna/fu'\].+Expected platforms: FAIL" \
  $BIN -v -p foo/bar,bar/foo,linux/s390x,sna/fu "$VENV_DIR/$VALID_ML_FQIN"

# This might fail after some time since it depends on metadata pulled from
# the Cirrus-CI API that may reach EOL (I have no idea what the retention
# policy is).
EXPECTED_PUSH_TIMESTAMP=$(date --utc --iso-8601=minutes --date '4/28/2022 14:54:00 EDT')
test_cmd "Script successfully validates $VALID_ML_FQIN timestamps" \
  0 "Cirrus timestamp.+PASS.+Delta 77\.949" \
  $BIN -v -c $EXPECTED_PUSH_TIMESTAMP "$VENV_DIR/$VALID_ML_FQIN"

ACTUAL_COMMIT=b2725024f859193eef10d33837258b206aab8245
test_cmd "Script successfully validates $VALID_ML_FQIN timestamps w/ overriden commit" \
  0 "Cirrus timestamp.+PASS.+Delta 77\.949" \
  $BIN -v -c $EXPECTED_PUSH_TIMESTAMP --commit $ACTUAL_COMMIT "$VENV_DIR/$VALID_ML_FQIN"

test_cmd "Script successfully flags invalid commit ID" \
  10 "Bad CommitID '1234567890'" \
  $BIN --commit 1234567890 -c $EXPECTED_PUSH_TIMESTAMP "$VENV_DIR/$VALID_ML_FQIN"

test_cmd "Script successfully reports failure-margin when checking timestamps" \
  10 "Cirrus timestamp.+FAIL.+30\.0s.+77\.949" \
  $BIN -v -d 1 -c $EXPECTED_PUSH_TIMESTAMP "$VENV_DIR/$VALID_ML_FQIN"

# Must be last call
exit_with_status
