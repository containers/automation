#!/bin/bash

# Load standardized test harness
source $(dirname $(realpath "${BASH_SOURCE[0]}"))/testlib.sh || exit 1

# Would otherwise get in the way of checking output & removing $TMPDIR
DEBUG=0
source "$TEST_DIR/$SUBJ_FILENAME"

PRIVATE_TEMPDIR=$(mktemp -p '' -d "testlib-ephemeral_gpg_XXXXX")

verify_export_test() {
    test_cmd "Verify status file contains only one exported success message" \
        0 'EXPORTED \w+\s$' \
        grep ' EXPORTED ' $GPG_STATUS_FILEPATH
}

##### MAIN() #####

unset PRIVATE_KEY_FILEPATH
test_cmd "Confirm calling verify_env_vars with no environment gives 'Expecting' error message" \
    2 'ERROR.+Expecting.+empty' \
    verify_env_vars

PRIVATE_KEY_FILEPATH=$(mktemp -p "$PRIVATE_TEMPDIR" "testlib-ephemeral_gpg_XXXXX.asc")
PRIVATE_PASSPHRASE_FILEPATH=$(mktemp -p "$PRIVATE_TEMPDIR" "testlib-ephemeral_gpg_XXXXX.pass")
dd if=/dev/zero "of=$PRIVATE_KEY_FILEPATH" bs=1M count=1 &> /dev/null
dd if=/dev/zero "of=$PRIVATE_PASSPHRASE_FILEPATH" bs=1M count=1 &> /dev/null

test_cmd "Confirm calling verify_env_vars() succeeds with variables set" \
    0 '' \
    verify_env_vars

# Sensitive env. vars are not leaked after go_ephemeral is called
for sensitive_varname in DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS PINENTRY_USER_DATA; do
    expected_value="testing_${RANDOM}_testing"
    eval "$sensitive_varname=$expected_value"
    export $sensitive_varname
    # Careful: Must also regex match the newline at the end of output
    test_cmd "Confirm that a non-empty value for \$$sensitive_varname is set" \
        0 "^$sensitive_varname=$expected_value\s$" \
        bash -c "echo $sensitive_varname=\$$sensitive_varname"
    go_ephemeral; rm -rf "$GNUPGHOME"; unset GNUPGHOME  # normally cleans up on exit
    actual_value="${!sensitive_varname}"
    test_cmd "Confirm that an empty value for \$$sensitive_varname is set" \
        0 "^$sensitive_varname=\s$" \
        bash -c "echo $sensitive_varname=\$$sensitive_varname"
done

test_cmd "Verify gpg_cmd() notices when go_ephemeral() isn't called first" \
    1 "ERROR.+go_ephemeral" \
    gpg_cmd --foo --bar

TEST_PASSPHRASE="testing_${RANDOM}_testing_${RANDOM}"
echo "$TEST_PASSPHRASE" > "$PRIVATE_PASSPHRASE_FILEPATH"

go_ephemeral

test_cmd "Verify \$PRIVATE_PASSPHRASE_FILEPATH file was consumed" \
    0 ''
    test $(stat --format=%s "$PRIVATE_PASSPHRASE_FILEPATH") -eq 0

test_cmd "Verify print_cached_key warning when cache is empty" \
    0 'WARNING: Empty key cache.+testlib-ephemeral_gpg.sh:[[:digit:]]+' \
    print_cached_key

# Adds an encr and signing subkeys by default
test_cmd "Verify quick key generation command works with gpg_cmd()" \
    0 "" \
    gpg_cmd --quick-generate-key foo@bar.baz default default never

test_cmd "Verify status file contents ends with success message" \
    0 'KEY_CREATED B \w+' \
    tail -1 $GPG_STATUS_FILEPATH

# The test for this function is all the following other tests :D
GPG_KEY_ID=$(print_cached_key)

# These are not added by default
for usage in sign auth; do
    test_cmd "Verify that a $usage subkey can be added" \
        0 "" \
        gpg_cmd --quick-add-key $GPG_KEY_ID default $usage
done

test_cmd "Verify invalid default key id can not be set" \
    1 "ERROR: Non-existing key 'abcd1234'" \
    set_default_keyid "abcd1234"

test_cmd "Verify generated secret key can be exported without console input" \
    0 "" \
    gpg_cmd --export-secret-keys --armor \
        --output "$GNUPGHOME/foo-bar_baz-secret.asc" foo@bar.baz

verify_export_test

test_cmd "Verify an ascii-armor key was exported" \
    0 "" \
    egrep -qi 'BEGIN PGP PRIVATE KEY BLOCK' "$GNUPGHOME/foo-bar_baz-secret.asc"

test_cmd "Verify ID of exported key was cached" \
    0 "[[:alnum:]]{32}" \
    print_cached_key

test_cmd "Verify trust_github() can import public key" \
    0 "" \
    trust_github

# Also confirms can export correct key after importing github
test_cmd "Verify generated public key can be exported without console input" \
    0 "" \
    gpg_cmd --export --armor --output "$GNUPGHOME/foo-bar_baz-public.asc" foo@bar.baz

verify_export_test

test_cmd "Verify valid default key id can not be set" \
    0 "" \
    set_default_keyid "$GPG_KEY_ID"

# Key IDs are always 16-bytes long
for kind in sec enc sig auth; do
    test_cmd "Verify $kind key ID can be obtained" \
        0 "[[:alnum:]]{16}" \
        get_${kind}_key_id "$GPG_KEY_ID"
done

test_cmd "Verify git setup fails if uid record doesn't match required e-mail address format" \
    1 "non-empty uid string" \
    configure_git_gpg "$GPG_KEY_ID"

gpg_cmd --command-fd 0 --edit-key "$GPG_KEY_ID" <<<"
adduid
Samuel O. Mebody
somebody@example.com
this is a test comment
save
" > /dev/null  # We don't need to see this (most of the time)

test_cmd "Verify git setup uses the last UID found" \
    0 "" \
    configure_git_gpg "$GPG_KEY_ID"

# Cleanup stuff we created
rm -rf "$GNUPGHOME"  # Cannot rely on EXIT trap
rm -rf $PRIVATE_TEMPDIR
exit_with_status
