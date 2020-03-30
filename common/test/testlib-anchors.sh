#!/bin/bash

# Unit-tests for library script in the current directory
# Also verifies test script is derived from library filename

source $(dirname ${BASH_SOURCE[0]})/testlib.sh || exit 1
source "$TEST_DIR/$SUBJ_FILENAME" || exit 2

test_cmd "Library $SUBJ_FILENAME is not executable" \
    0 "" \
    test ! -x "$SCRIPT_PATH/$SUBJ_FILENAME"

test_cmd "The unit-test and library files not in same directory" \
    0 "" \
    test "$AUTOMATION_LIB_PATH" != "$SCRIPT_PATH"

test_cmd "This common unit-test is in test subdir relative ti AUTOMATION_ROOT" \
    0 "$AUTOMATION_ROOT/test" \
    echo "$SCRIPT_PATH"

test_cmd "The repository root is above \$AUTOMATION_ROOT and contains a .git directory" \
    0 "" \
    test -d "$AUTOMATION_ROOT/../.git"

for path_var in AUTOMATION_LIB_PATH AUTOMATION_ROOT SCRIPT_PATH; do
    test_cmd "\$$path_var is defined and non-empty: ${!path_var}" \
        0 "" \
        test -n "${!path_var}"
    test_cmd "\$$path_var referrs to existing directory" \
        0 "" \
        test -d "${!path_var}"
done

test_cmd "Able to create a temporary directory using \$MKTEMP_FORMAT that references script name" \
    0 "removed.+$SCRIPT_FILENAME" \
    rm -rvf $(mktemp -p '' -d "$MKTEMP_FORMAT")

test_cmd "There is no AUTOMATION_VERSION file in \$AUTOMATION_ROOT before testing automation_version()" \
    1 "" \
    test -r "$AUTOMATION_ROOT/AUTOMATION_VERSION"

TEMPDIR=$(mktemp -p '' -d tmp_${SCRIPT_FILENAME}_XXXXXXXX)
trap "rm -rf $TEMPDIR" EXIT
cat << EOF > "$TEMPDIR/git"
#!/bin/bash
echo "Standard Error is ignored" > /dev/stderr
echo "99.99.99" > /dev/stdout
EOF
chmod +x "$TEMPDIR/git"

actual_path=$PATH
export PATH=$TEMPDIR:$PATH
test_cmd "Without AUTOMATION_VERSION file, automation_version() uses git" \
    0 "99.99.99" \
    automation_version

echo "exit 123" >> "$TEMPDIR/git"

test_cmd "Without AUTOMATION_VERSION file, a git error causes automation_version() to error" \
    1 "Error determining version number" \
    automation_version

ln -sf /usr/bin/* $TEMPDIR/
ln -sf /bin/* $TEMPDIR/
rm -f "$TEMPDIR/git"
export PATH=$TEMPDIR
test_cmd "Without git or AUTOMATION_VERSION file automation_version() errorsr"\
    1 "Error determining version number" \
    automation_version
unset PATH
export PATH=$actual_path

# Must be last call
exit_with_status
