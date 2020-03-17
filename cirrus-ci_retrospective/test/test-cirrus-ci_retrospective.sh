#!/bin/bash

# Load standardized test harness
source $(dirname "${BASH_SOURCE[0]}")/testlib.sh || exit 1

# Would otherwise get in the way of checking output & removing $TMPDIR
DEBUG=0
source "$TEST_DIR/$SUBJ_FILENAME"

_TMPDIR="$TMPDIR"  # some testing requires examining all $TMPDIR contents
if [[ -d "$_TMPDIR" ]]; then
    trap "rm -rf $_TMPDIR" EXIT  # The REAL directory to remove
fi

copy_function() {
  test -n "$(declare -f "$1")" || return
  eval "${_/$1/$2}"
}

rename_function() {
  copy_function "$@" || return
  unset -f "$1"
}

# There are many paths to die(), some specific paths need to be tested
SPECIAL_DEATH_CODE=101
rename_function die _die
die() {
    echo "Caught call to die() from ${FUNCNAME[1]} with message: ${1:-NOMSG}" > /dev/stderr
    exit $SPECIAL_DEATH_CODE
}

mock_env_vars() {
    export GITHUB_ACTIONS=true
    export GITHUB_EVENT_NAME=check_suite
    export GITHUB_EVENT_PATH=$(tmpfile)
    export GITHUB_TOKEN=$RANDOM$RANDOM$RANDOM
    export GITHUB_WORKSPACE=$_TMPDIR
}

mock_curl_zero_exit() {
    local real_curl=$(type -P curl)
    if [[ "$CURL" != "$real_curl" ]]; then
        sed -r -i -e "s/exit .+/exit 0/g" "$CURL"
    else
        echo "Cowardly refusing to modify" > /dev/stderr
        exit 103
    fi
}

##### MAIN() #####

test_cmd \
    "Call verify_env_vars() w/o required values should exit with an error code and message." \
    $SPECIAL_DEATH_CODE \
    'Caught call to die.+verify_env_vars' \
    verify_env_vars

mock_env_vars

test_cmd \
    "Call encode_query with an empty argument should exit with an error code and message." \
    $SPECIAL_DEATH_CODE \
    'Caught call to die.+encode_query.+JSON' \
    encode_query

COMPLEX="{\"foo
            \t\"\t\t           bar{\r '"
for test_f in json_escape encode_query; do
    test_cmd \
        "Call to $test_f properly handles complex string containing control-characters and embedded quotes" \
        0 \
        ".*foo.*bar.*" \
        $test_f "$COMPLEX"
done

# e.g. output
# {
#    "query": "[] "
# }
test_cmd \
    "Call to encode_query '[]' is formatted in the expected way" \
    0 \
    '\{"query":"\[\]"\}' \
    encode_query '[]'

TEST_EXTENSION=foobarbaz
test_cmd \
    "Verify no tmpfile with testing extension '$TEST_EXTENSION' is present before the next test" \
    0 \
    ""  \
    find "$TMPDIR" -name "*.$TEST_EXTENSION"

test_cmd \
    "Calling tmpfile with an argument, uses it as the file extension" \
    0 \
    "$TMPDIR.+\.$TEST_EXTENSION" \
    tmpfile "$TEST_EXTENSION"

TEST_JSON='[{"1":2},{"3":4}]'
TEST_JSON_FILE=$(mktemp -p "$_TMPDIR" TEST_JSON_XXXXXXXX)
echo "$TEST_JSON" > "$TEST_JSON_FILE"
test_cmd \
    "Verify filter_json with invalid filter mentions jq in error" \
    $SPECIAL_DEATH_CODE \
    'Caught.+filter_json.+jq' \
    filter_json "!" "$TEST_JSON_FILE"

TEST_FILT='.[1]["3"]'
test_cmd \
    "Verify filter_json '$TEST_FILT' '$TEST_JSON_FILE' has no output" \
    0 \
    "" \
    filter_json "$TEST_FILT" "$TEST_JSON_FILE"

test_cmd \
    "Verify final copy of '$TEST_JSON_FILE' has expected contents" \
    0 \
    '^4 $' \
    cat "$TEST_JSON_FILE"

# Makes checking temp-files writen by curl_post() easier
TMPDIR=$(mktemp -d -p "$_TMPDIR" "tmpdir_curl_XXXXX")
# Set up a mock for argument checking
_CURL="$CURL"
_CURL_EXIT=42
CURL="$_TMPDIR/mock_curl.sh"  # used by curl_post
cat << EOF > $CURL
#!/bin/bash
echo "curl \$*"
exit $_CURL_EXIT
EOF
chmod +x "$CURL"

test_cmd \
    "Verify curl_post() does not pass secrets on the command-line" \
    $_CURL_EXIT \
    "^curl.+((?!${GITHUB_TOKEN}).)*$" \
    curl_post foo bar

mock_curl_zero_exit

test_cmd \
    "Verify curl_post without an mock error, does not pass data on command-line" \
    0 \
    '^curl.+((?!snafu).)*$' \
    curl_post foobar snafu

QUERY="foobar"
OUTPUT_JSON='[null,0,1,2,3,4]'
cat << EOF > $CURL
#!/bin/bash
set -e
cat << NESTEDEOF
$OUTPUT_JSON
NESTEDEOF
exit $_CURL_EXIT
EOF

TEST_URL="the://url"
test_cmd \
    "Verify url_query_filter_test reports errors coming from curl command" \
    $SPECIAL_DEATH_CODE \
    "Caught.+url_query_filter_test.+$_CURL_EXIT" \
    url_query_filter_test "$TEST_URL" "$QUERY" "."

mock_curl_zero_exit

test_cmd \
    "Verify url_query_filter_test works normally with simple JSON and test" \
    0 \
    "^4 $" \
    url_query_filter_test "$TEST_URL" "$QUERY" ".[-1]" "@@@@ -eq 4"

test_cmd \
    "Verify url_query_filter_test works with single-operand test" \
    0 \
    "^null $" \
    url_query_filter_test "$TEST_URL" "$QUERY" ".[0]" "-n @@@@"

test_cmd \
    "Verify url_query_filter_test works without any test" \
    0 \
    "^0 $" \
    url_query_filter_test "$TEST_URL" "$QUERY" ".[1]"

test_cmd \
    "Verify no calls left secrets in \$TMPDIR" \
    1 \
    '' \
    grep -qr "$GITHUB_TOKEN" "$TMPDIR"

# Put everything back the way it was for posterity
TMPDIR="$_TMPDIR"
CURL="$_CURL"

exit_with_status
