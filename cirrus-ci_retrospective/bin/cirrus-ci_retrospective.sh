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
OUTPUT_JSON_FILE="$GITHUB_WORKSPACE/${SCRIPT_FILENAME%.sh}.json"

# Confirm expected triggering event
[[ "$(jq --slurp --compact-output --raw-output '.[0].action' < $GITHUB_EVENT_PATH)" == "completed" ]] || \
    die "Expecting github action event action to be 'completed'"

cirrus_app_id=$(jq --slurp --compact-output --raw-output '.[0].check_suite.app.id' < $GITHUB_EVENT_PATH)
dbg "# Working with Github Application ID: '$cirrus_app_id'"
[[ -n "$cirrus_app_id" ]] || \
    die "Failed to obtain Cirrus-CI's github app ID number"
[[ "$cirrus_app_id" -gt 0 ]] || \
    die "Expecting Cirrus-CI app ID to be integer greater than 0"

# Guaranteed shortcut by Github API straight to actual check_suite node
cs_node_id="$(jq --slurp --compact-output --raw-output '.[0].check_suite.node_id' < $GITHUB_EVENT_PATH)"
dbg "# Working with github global node id '$cs_node_id'"
[[ -n "$cs_node_id" ]] || \
    die "You must provide the check_suite's node_id string as the first parameter"

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
            name
            status
            automaticReRun
            build {changeIdInRepo branch pullRequest status repository {
                owner name cloneUrl masterBranch
              }
            }
            artifacts {name files{path}}
          }
        }" \
        '.' \
        '-n @@@@' >> "$output_json"
done

dbg "# Combining and pretty-formatting all task data as JSON list into $OUTPUT_JSON_FILE"
jq --indent 4 --slurp '.' $TMPDIR/.*$INTERMEDIATE_OUTPUT_EXT > "$OUTPUT_JSON_FILE"
