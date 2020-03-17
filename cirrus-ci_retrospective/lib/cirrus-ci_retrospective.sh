
# Library of constants and functions for the cirrus-ci_retrospective script
# Not intended to be executed directly.

source $(dirname "${BASH_SOURCE[0]}")/common.sh

# GH GraphQL General Reference: https://developer.github.com/v4/object/
# GH CheckSuite Object Reference: https://developer.github.com/v4/object/checksuite
GHQL_URL="https://api.github.com/graphql"
# Cirrus-CI GrqphQL Reference: https://cirrus-ci.org/api/
CCI_URL="https://api.cirrus-ci.com/graphql"
TMPDIR=$(mktemp -p '' -d "$MKTEMP_FORMAT")
# Support easier unit-testing
CURL=${CURL:-$(type -P curl)}

# Using python3 here is a compromise for readability and
# properly handling quote, control and unicode character encoding.
json_escape() {
    local json_string
    # Assume it's okay to squash repeated whitespaces inside the query
    json_string=$(printf '%s' "$1" | \
                  tr --delete '\r\n' | \
                  tr --squeeze-repeats '[[:space:]]' | \
        python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')
    # The $json_string in message is already quoted
    dbg "##### Escaped JSON string: $json_string"
    echo -n "$json_string"
}

# Given a GraphQL Query JSON, encode it as a GraphQL query string
encode_query() {
    dbg "#### Encoding GraphQL Query into JSON string"
    [[ -n "$1" ]] || \
        die "Expecting JSON string as first argument to ${FUNCNAME[0]}()"
    local json
    local quoted
    # Embed GraphQL as escaped string into JSON
    # Using printf's escaping works well
    quoted=$(json_escape "$1")
    json=$(jq --compact-output . <<<"{\"query\": $quoted}")
    dbg "#### Query JSON: $json"
    echo -n "$json"
}

# Get a temporary file named with the calling-function's name
# Optionally, if the first argument is non-empty, use it as the file extension
tmpfile() {
    [[ -n "${FUNCNAME[1]}" ]] || \
        die "tmpfile() function expects to be called by another function."
    [[ -z "$1" ]] || \
        local ext=".$1"
    mktemp -p "$TMPDIR" "$MKTEMP_FORMAT${ext}"
}

# Given a URL Data and optionally a token, validate then print formatted JSON string
curl_post() {
    local url="$1"
    local data="$2"
    local token=$GITHUB_TOKEN
    local auth=""
    [[ -n "$url" ]] || \
        die "Expecting non-empty url argument"
    [[ -n "$data" ]] || \
        die "Expecting non-empty data argument"

    [[ -n "$token" ]] || \
        dbg "### Warning: \$GITHUB_TOKEN is empty, performing unauthenticated query" > /dev/stderr
    # Don't expose secrets on any command-line
    local headers_tmpf
    local headers_tmpf=$(tmpfile headers)
    cat << EOF > "$headers_tmpf"
accept: application/vnd.github.antiope-preview+json
content-type: application/json
${token:+authorization: Bearer $token}
EOF

    # Avoid needing to pass large strings on te command-line
    local data_tmpf=$(tmpfile data)
    echo "$data" > "$data_tmpf"

    local curl_cmd="$CURL --silent --request POST --url $url --header @$headers_tmpf --data @$data_tmpf"
    dbg "### Executing '$curl_cmd'"
    local ret="0"
    $curl_cmd > /dev/stdout || ret=$?

    # Don't leave secrets lying around in files
    rm -f "$headers_tmpf" "$data_tmpf" &> /dev/null
    dbg "### curl exit code '$ret'"
    return $ret
}

# Apply filter to json file while making any errors easy to debug
filter_json() {
    local filter="$1"
    local json_file="$2"
    [[ -n "$filter" ]] || die "Expected non-empty jq filter string"
    [[ -r "$json_file" ]] || die "Expected readable JSON file"

    dbg "### Validating JSON in '$json_file'"
    # Confirm input json is valid and make filter problems easier to debug (below)
    local tmp_json_file=$(tmpfile json)
    if ! jq . < "$json_file" > "$tmp_json_file"; then
        rm -f "$tmp_json_file"
        # JQ has alrady shown an error message
        die "Error from jq relating to JSON: $(cat $json_file)"
    else
        dbg "### JSON found to be valid"
        # Allow re-using temporary file
        cp "$tmp_json_file" "$json_file"
    fi

    dbg "### Applying filter '$filter'"
    if ! jq --indent 4 "$filter" < "$json_file" > "$tmp_json_file"; then
        # JQ has alrady shown an error message
        rm -f "$tmp_json_file"
        die "Error from jq relating to JSON: $(cat $json_file)"
    fi

    dbg "### Filter applied cleanly"
    cp "$tmp_json_file" "$json_file"
}

# Name suggests parameter order and purpose
# N/B: Any @@@@ appearing in test_args will be substituted with the quoted simple/raw JSON value.
url_query_filter_test() {
    local url="$1"
    local query_json="$2"
    local filter="$3"
    shift 3
    local test_args
    test_args="$@"
    [[ -n "$url" ]] || \
        die "Expecting non-empty url argument"
    [[ -n "$filter" ]] || \
        die "Expecting non-empty filter argument"
    [[ -n "$query_json" ]] || \
        die "Expecting non-empty query_json argument"

    dbg "## Submitting GraphQL Query, filtering and verifying the result"
    local encoded_query=$(encode_query "$query_json")
    local ret
    local curl_outputf=$(tmpfile json)

    ret=0
    curl_post "$url" "$encoded_query" > "$curl_outputf" || ret=$?
    dbg "## Curl output file: $curl_outputf)"
    [[ "$ret" -eq "0" ]] || \
        die "Curl command exited with non-zero code: $ret"

    if grep -q "error" "$curl_outputf"; then
        # Barely passable attempt to catch GraphQL query errors
        die "Found the word 'error' in curl output: $(cat $curl_outputf)"
    fi

    # Validates both JSON and filter, updates $curl_outputf
    filter_json "$filter" "$curl_outputf"
    if [[ -n "$test_args" ]]; then
        # The test command can only process simple, single-line strings
        local simplified=$(jq --compact-output --raw-output . < "$curl_outputf" | tr -d '[:space:]')
        # json_escape will properly quote and escape the value for safety
        local _test_args=$(sed -r -e "s~@@@@~$(json_escape $simplified)~" <<<"test $test_args")
        # Catch error coming from sed, e.g. if '~' happens to be in $simplified
        [[ -n "$_test_args" ]] || \
            die "Substituting @@@@ in '$test_args'"
        dbg "## $_test_args"
        ( eval "$_test_args" ) || \
            die "Test '$test_args' failed on whitespace-squashed & simplified JSON '$simplified'"
    fi
    cat "$curl_outputf"
}

verify_env_vars() {
    [[ "$GITHUB_ACTIONS" == "true" ]] || \
        die "Expecting to be running inside a Github Action"

    [[ "$GITHUB_EVENT_NAME" = "check_suite" ]] || \
        die "Expecting \$GITHUB_EVENT_NAME to be 'check_suite'"

    [[ -r "$GITHUB_EVENT_PATH" ]] || \
        die "Unable to read github action event file '$GITHUB_EVENT_PATH'"

    [[ -n "$GITHUB_TOKEN" ]] || \
        die "Expecting non-empty \$GITHUB_TOKEN"

    [[ -d "$GITHUB_WORKSPACE" ]] || \
        die "Expecting to find \$GITHUB_WORKSPACE '$GITHUB_WORKSPACE' as a directory"
}
