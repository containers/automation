#!/bin/bash

# Load standardized test harness
source $(dirname $(realpath "${BASH_SOURCE[0]}"))/testlib.sh || exit 1

# Would otherwise get in the way of checking output & removing $TMPDIR
DEBUG=${DEBUG:-0}
SUBJ_FILEPATH="$TEST_DIR/$SUBJ_FILENAME"
export GITREPODIR=$(mktemp -p '' -d 'testbin-ephemeral_gpg_XXXXX.repo')
export PRIVATE_KEY_FILEPATH=$(mktemp -p '' "testbin-ephemeral_gpg_XXXXX.key")
export PRIVATE_PASSPHRASE_FILEPATH=$(mktemp -p '' "testbin-ephemeral_gpg_XXXXX.pass")
trap "rm -rf $GITREPODIR $PRIVATE_KEY_FILEPATH $RIVATE_PASSPHRASE_FILEPATH" EXIT

TEST_KEY_UID='Fine Oolong <foo@bar.baz>'
TEST_KEY_ID="C71D7CA13828797F29528BA25B786A278A6D48C5"
SIG_KEY_FPR="CBD7A22AD00CB77FD9B8F314A7D41FE6F7FE0989"
TEST_KEY_PASSPHRASE='bin_GdJN-bin_MwPa'
TEST_PRIV_PUB_KEY='
-----BEGIN PGP PRIVATE KEY BLOCK-----

lIYEXu0eiBYJKwYBBAHaRw8BAQdAmmXn0oLorwHlhHiVjs6TXBo8Lo1dsrG0NU1j
WGf01eb+BwMCvev3eznkTMLsp39YX5f1UX12uY7LuDg32Ka6N/maauL5ftlUtuxi
UIW0lP+9l34aqaBN4aTSLppVpSFEbo5EFv3H7NtoxyxholIM6ccdoLQZRmluZSBP
b2xvbmcgPGZvb0BiYXIuYmF6PoiQBBMWCAA4FiEExx18oTgoeX8pUouiW3hqJ4pt
SMUFAl7tHogCGwMFCwkIBwIGFQoJCAsCBBYCAwECHgECF4AACgkQW3hqJ4ptSMV7
lgD+MFzKRP/i4tmuLbnE6Xiwb4jxrrtz5pF7blSFPHJhEkEA/juxypMqFVJEgCf1
t3IFJTxh6Lkj9yZZiFjdRHLxD8kInIsEXu0eiBIKKwYBBAGXVQEFAQEHQEEkryan
kgJNY4w5o8dZd7N0g38j8U9qScFbo421hvoZAwEIB/4HAwJ9hWYQX1qmu+wrT6EO
rg5o9H9Mxo3L2LTKfw24eq+t9udUDOKaYXHXzFEmrOAQiPheZq0R4nGVN4Avf31l
A5bxCZZV/vQ0MIrt1W1f8r6NiHgEGBYIACAWIQTHHXyhOCh5fylSi6JbeGonim1I
xQUCXu0eiAIbDAAKCRBbeGonim1IxWCbAQCwTzKCAqza4VWqxX31D6ygIb0+9Otj
zQUZxE5jggDU2QEA/OlbISfm5+2NJGizJW/n+VozyfrAHr/JsmW8qbixAwachgRe
7R6JFgkrBgEEAdpHDwEBB0DvuGjjL4RKGK7DirQwLhpScrFnG6kHPWbVIpj+A4zQ
d/4HAwKly2aim7e1zOy26pXOgBV17gg4FAJ68Ug0uDD5TnkjynmqkWfTuIFvddyz
ByYmtxL4vbd+vgKb2vLxtmXDI5GvXaeBzfzDM8n8j7smYz/diO8EGBYIACAWIQTH
HXyhOCh5fylSi6JbeGonim1IxQUCXu0eiQIbAgCBCRBbeGonim1IxXYgBBkWCAAd
FiEEy9eiKtAMt3/ZuPMUp9Qf5vf+CYkFAl7tHokACgkQp9Qf5vf+CYmOwAD/Uy2j
HLsnhQ/IQYRxdbhW1N93q58gHcn6qlx77k/GojIA/0tFeY3N3NGJQF0V/JlCVSfZ
BJtu+41FD2jdRaWdm+gLuukBAPEzEncXlr02mdzkm6yiJmLm8nTmr0iLAhkNqn2C
Cp1XAP43Bl3JwwigFvgP19ydLCQ9Mqc5DfOVFS9UnFlnGSSeDZyGBF7tHooWCSsG
AQQB2kcPAQEHQIGZympIyDs48GfUyuDjkNcJRoFCLwJoyt6OjpvbzTi1/gcDArMo
IDOeZcFc7OcMNKPNICosTF8jRblG0/UYx/JmH999AGOeU5hPB4FnYLcsv+xLcw6s
SFQC10yCbs6edx8oA7UUkYKbSvbsK+MUBaF5GECIeAQYFggAIBYhBMcdfKE4KHl/
KVKLolt4aieKbUjFBQJe7R6KAhsgAAoJEFt4aieKbUjFrYQA/RNSOCZLckAgUV1G
DcuR1Epmfyymckq4ysCRp3KVnE8tAP9zT6TR/7uhd61X/xaa5ANsWUKDFuPFEp7n
/0ocs8zkApyLBF7tHooSCisGAQQBl1UBBQEBB0COYmfEzCxyCDUR6seA0HaUF9Bc
tBIloo+RTjvt54s+SAMBCAf+BwMCtn0weBQeArTsKOJ9t6yCgJExkrlpvgL1Nfkq
z0vy5StDbu/HuVKOTT2ecCoyclqKuA+S5E78pcJWPMoFBS3Vee6BVaDiRTjVN6kZ
rFXhWIh4BBgWCAAgFiEExx18oTgoeX8pUouiW3hqJ4ptSMUFAl7tHooCGwwACgkQ
W3hqJ4ptSMUccQD7Bd/g1ph10NFnvg6+2OSQgHuA7/HTSHEmH65Qm6WroXoBALq5
QKdFj22bniOLyMcRQi/fsYHiIRxEMec7v3RkR+YF
=BUzJ
-----END PGP PRIVATE KEY BLOCK-----
-----BEGIN PGP PUBLIC KEY BLOCK-----

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
=TnEk
-----END PGP PUBLIC KEY BLOCK-----
'

# These files are intentionally modified during script use.
restore_inputs(){
    # Files may not have write-bit set
    chmod 0600 "$PRIVATE_PASSPHRASE_FILEPATH" || true
    chmod 0600 "$PRIVATE_KEY_FILEPATH" || true
    echo "$TEST_KEY_PASSPHRASE" > "$PRIVATE_PASSPHRASE_FILEPATH"
    echo "$TEST_PRIV_PUB_KEY" > "$PRIVATE_KEY_FILEPATH"
    chmod 0600 "$PRIVATE_PASSPHRASE_FILEPATH"
    chmod 0600 "$PRIVATE_KEY_FILEPATH"
}

rein_test_cmd() {
    restore_inputs
    test_cmd "${@}"
}

##### MAIN() #####

for var_name in PRIVATE_PASSPHRASE_FILEPATH PRIVATE_KEY_FILEPATH; do
    # Assume 3-characters is "too small" and will fail
    echo "foo" > "$PRIVATE_KEY_FILEPATH"
    echo "bar" > "$PRIVATE_PASSPHRASE_FILEPATH"
    test_cmd "Verify expected error when ${!var_name} file is too small" \
        1 "must be larger than" \
        $SUBJ_FILEPATH true
    restore_inputs
    chmod 0000 "${!var_name}"
    test_cmd "Verify \$${var_name} must be writable check" \
        1 "ERROR:.+file.+writable" \
        $SUBJ_FILEPATH true
    restore_inputs
done

for must_have in 'uid:u:.+:Fine' 'sub:.+:A7D41FE6F7FE0989' 'uid:.+:GitHub'; do
    rein_test_cmd "Verify key listing of imported keys contains '$must_have'" \
        0 "$must_have" \
        $SUBJ_FILEPATH gpg --list-keys --quiet --batch --with-colons --keyid-format LONG
done

rein_test_cmd "Confirm can create repository" \
    0 "Initialized empty Git repository" \
    $SUBJ_FILEPATH git init "$GITREPODIR"

BASH_GIT_REPO="set -e; cd $GITREPODIR;"
echo "$RANDOM$RANDOM$RANDOM" > "$GITREPODIR/testfile"

rein_test_cmd "Confirm use bash command string for git committing" \
    0 "commit_message.+file changed.+testfile" \
    $SUBJ_FILEPATH bash -c "$BASH_GIT_REPO git add testfile; git commit -sm commit_message 2>&1"

rein_test_cmd "Verify last commit passes signature verification" \
    0 "gpg.+Signature.+$SIG_KEY_FPR.+Good signature.+ultimate.+Author.+Fine" \
    $SUBJ_FILEPATH bash -c "$BASH_GIT_REPO git log -1 HEAD 2>&1"

rein_test_cmd "Confirm a signed tag can be added for HEAD" \
    0 ""
    $SUBJ_FILEPATH bash -c "$BASH_GIT_REPO git tag -as v0.0.0 -m tag_annotation HEAD 2>&1"

rein_test_cmd "Verify tag can be verified" \
    0 "$SIG_KEY_FPR.+Good signature.+tagger Fine Oolong" \
    $SUBJ_FILEPATH bash -c "$BASH_GIT_REPO git tag --verify v0.0.0 2>&1"

# Files may not have write-bit set
chmod 0600 "$PRIVATE_PASSPHRASE_FILEPATH" || true
chmod 0600 "$PRIVATE_KEY_FILEPATH" || true
exit_with_status
