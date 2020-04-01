#!/bin/bash

set -eo pipefail

# Execute inside a github action, using a completed check_suite event's JSON file
# as input.  Queries details about the concluded Cirrus-CI build, tasks, artifacts,
# execution environment, and associated repository state.

source $(dirname "${BASH_SOURCE[0]}")/../lib/$(basename "${BASH_SOURCE[0]}")

if ((DEBUG)); then
    dbg "# Warning: Debug mode enabled:  NOT cleaning up '$TMPDIR' upon exit."
else
    trap "rm -rf $TMPDIR" EXIT
fi

verify_env_vars

INTERMEDIATE_OUTPUT_EXT=".json_item"
OUTPUT_JSON_FILE="${OUTPUT_JSON_FILE:-$GITHUB_WORKSPACE/${SCRIPT_FILENAME%.sh}.json}"

# Confirm expected triggering event and type
jq --exit-status 'has("check_suite")' < "$GITHUB_EVENT_PATH" || \
    die "Expecting to find a top-level 'check_suite' key in event JSON $GITHUB_EVENT_PATH"

_act_typ=$(jq --compact-output --raw-output '.action' < "$GITHUB_EVENT_PATH")
[[ "$_act_typ" == "completed" ]] || \
    die "Expecting github action 'check_suite' event to be type 'completed', got '$_act_typ'"

_filt='.check_suite.app.id'
cirrus_app_id=$(jq --compact-output --raw-output "$_filt" < "$GITHUB_EVENT_PATH")
dbg "# Working with Github Application ID: '$cirrus_app_id'"
[[ -n "$cirrus_app_id" ]] || \
    die "Expecting non-empty value from jq filter $_filt in $GITHUB_EVENT_PATH"
[[ "$cirrus_app_id" -gt 0 ]] || \
    die "Expecting jq filter $_filt value to be integer greater than 0, got '$cirrus_app_id'"

# Guaranteed shortcut by Github API straight to actual check_suite node
_filt='.check_suite.node_id'
cs_node_id=$(jq --compact-output --raw-output "$_filt" < "$GITHUB_EVENT_PATH")
dbg "# Working with github global node id '$cs_node_id'"
[[ -n "$cs_node_id" ]] || \
    die "Expecting the jq filter $_filt to be non-empty value in $GITHUB_EVENT_PATH"

# Validate node is really the type expected - global node ID's can point anywhere
dbg "# Checking type of object at '$cs_node_id'"
# Only verification test important, discard actual output
_=$(url_query_filter_test \
    "$GHQL_URL" \
    "{
        node(id: \"$cs_node_id\") {
            __typename
        }
    }" \
    '.data.node.__typename' \
    '@@@@ = "CheckSuite"'
)

# This count is needed to satisfy 'first' being a required parameter in subsequent query
dbg "# Obtaining total number of check_runs present on confirmed CheckSuite object"
cr_count=$(url_query_filter_test \
    "$GHQL_URL" \
    "{
        node(id: \"$cs_node_id\") {
            ... on CheckSuite {
                checkRuns {
                    totalCount
                }
            }
        }
    }" \
    '.data.node.checkRuns.totalCount' \
    '@@@@ -gt 0' \
)

# 'externalId' is the database key needed to query Cirrus-CI GraphQL API
dbg "# Obtaining task names and id's for up to '$cr_count' check_runs max."
task_ids=$(url_query_filter_test \
    "$GHQL_URL" \
    "{
        node(id: \"$cs_node_id\") {
          ... on CheckSuite {
            checkRuns(first: $cr_count, filterBy: {appId: $cirrus_app_id}) {
              nodes {
                externalId
                name
              }
            }
          }
        }
    }" \
    '.data.node.checkRuns.nodes[] | .name + ";" + .externalId + ","' \
    '-n @@@@')

dbg "# Clearing any unintended intermediate json files"
# Warning: Using a side-effect here out of pure laziness
dbg "## $(rm -fv $TMPDIR/*.$INTERMEDIATE_OUTPUT_EXT)"

dbg "# Processing task names and ids"
unset GITHUB_TOKEN  # not needed/used for cirrus-ci query
echo "$task_ids" | tr -d '",' | while IFS=';' read task_name task_id
do
    dbg "# Cross-referencing task '$task_name' ID '$task_id' in Cirrus-CI's API:"
    [[ -n "$task_id" ]] || \
        die "Expecting non-empty id for task '$task_name'"
    [[ -n "$task_name" ]] || \
        die "Expecting non-empty name for task id '$task_id'"

    # To be slurped up into an array of json maps as a final step
    output_json=$(tmpfile .$INTERMEDIATE_OUTPUT_EXT)
    dbg "# Writing task details into '$output_json' temporarily"
    url_query_filter_test \
        "$CCI_URL" \
        "{
          task(id: $task_id) {
            id
            name
            status
            automaticReRun
            build {id changeIdInRepo branch pullRequest status repository {
                owner name cloneUrl masterBranch
              }
            }
            artifacts {name files{path}}
          }
        }" \
        '.' \
        '-n @@@@' | jq --indent 4 '.data.task' > "$output_json"
done

dbg "# Combining all task data into JSON list as action output and into $OUTPUT_JSON_FILE"
# Github Actions handles this prefix specially:  Ensure stdout JSON is all on one line.
# N/B: It is not presently possible to actually _use_ this output value as JSON in
#      a github actions workflow.
printf "::set-output name=json::'%s'" \
    $(jq --indent 4 --slurp '.' $TMPDIR/.*$INTERMEDIATE_OUTPUT_EXT | \
      tee "$OUTPUT_JSON_FILE" | \
      jq --compact-output '.')
