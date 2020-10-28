#!/usr/bin/env python3

"""Print list of agent-stopped-responding task IDs and status-keyed task IDs"""

import sys
from collections import namedtuple
from pprint import pprint

# Ref: https://gql.readthedocs.io/en/latest/index.html
# pip3 install --user --requirement ./requirements.txt
# (and/or in a python virtual environment)
from gql import gql, Client
from gql.transport.requests import RequestsHTTPTransport

CIRRUS_CI_STATUSES = (
    "CREATED",
    "TRIGGERED",
    "SCHEDULED",
    "EXECUTING",
    "ABORTED",
    "FAILED",
    "COMPLETED",
    "SKIPPED",
    "PAUSED"
)

def get_raw_builds(client, owner, repo, sha):
    """Retrieve list of builds for the specified owner/repo @ commit SHA"""
    # Generated using https://cirrus-ci.com/explorer
    query = gql('''
        query buildBySha($owner: String!, $repo: String!, $sha: String!) {
          searchBuilds(repositoryOwner: $owner, repositoryName: $repo, SHA: $sha) {
            id
            buildCreatedTimestamp
          }
        }
    ''')
    query_vars = dict(owner=owner, repo=repo, sha=sha)
    result = client.execute(query, variable_values=query_vars)
    if "searchBuilds" in result and len(result["searchBuilds"]):
        return result["searchBuilds"]
    else:
        raise RuntimeError(f"No Cirrus-CI builds found for {owner}/{repo} commit {sha}")


def latest_build_id(raw_builds):
    """Return the build_id of the most recent build among raw_builds"""
    latest_ts = 0
    latest_bid = 0
    for build in raw_builds:
        bts = build["buildCreatedTimestamp"]
        if bts > latest_ts:
            latest_ts = bts
            latest_bid = build["id"]
    if latest_bid:
        return latest_bid
    raise RuntimeError(f"Empty raw_builds list")


def get_raw_tasks(client, build_id):
    """Retrieve raw GraphQL task list from a build"""
    query = gql('''
        query tasksByBuildID($build_id: ID!) {
          build(id: $build_id) {
            tasks {
              name
              id
              status
              notifications {
                level
                message
              }
              automaticReRun
              previousRuns {
                id
              }
            }
          }
        }
    ''')
    query_vars = dict(build_id=build_id)
    result = client.execute(query, variable_values=query_vars)
    if "build" in result and result["build"]:
        result = result["build"]
        if "tasks" in result and len(result["tasks"]):
            return result["tasks"]
        else:
            raise RuntimeError(f"No tasks found for build with id {build_id}")
    else:
        raise RuntimeError(f"No Cirrus-CI build found with id {build_id}")


def status_tid_names(raw_tasks, status):
    """Return dictionary of task IDs to task names with specified status"""
    return dict([(task["id"], task["name"])
                for task in raw_tasks
                if task["status"] == status])


def notif_tids(raw_tasks, reason):
    """Return dictionary of task IDs to task names which match notification reason"""
    result={}
    for task in raw_tasks:
        for notif in task["notifications"]:
            if reason in notif["message"]:
                result[task["id"]] = task["name"]
    return result


def output_tids(keyword, tid_names):
    """Write line of space separated list of task ID:"name" prefixed by a keyword"""
    sys.stdout.write(f'{keyword} ')
    tasks=[f'{tid}:"{name}"' for tid, name in tid_names.items()]
    sys.stdout.write(",".join(tasks))
    sys.stdout.write("\n")


if __name__ == "__main__":
    # Ref: https://cirrus-ci.org/api/
    cirrus_graphql_url = "https://api.cirrus-ci.com/graphql"
    cirrus_graphql_xport = RequestsHTTPTransport(
        url=cirrus_graphql_url,
        verify=True,
        retries=3)
    client = Client(transport=cirrus_graphql_xport, fetch_schema_from_transport=True)

    try:
        raw_builds = get_raw_builds(client, sys.argv[1], sys.argv[2], sys.argv[3])
    except IndexError as xcpt:
        print(f"Error: argument {xcpt}\n\nUsage: {sys.argv[0]} <user> <repo> <sha>")
        sys.exit(1)

    raw_tasks = get_raw_tasks(client, latest_build_id(raw_builds))
    for cci_status in CIRRUS_CI_STATUSES:
        output_tids(cci_status, status_tid_names(raw_tasks, cci_status))
    output_tids("CIASR", notif_tids(raw_tasks, "CI agent stopped responding!"))
