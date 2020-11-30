#!/usr/bin/env python3

"""
Download all artifacts from a Cirrus-CI Build into $PWD

Input arguments (in order):
    Repo owner/name - string, from github.
                      e.g. "containers/podman"
    Bucket - Name of the GCS bucket storing Cirrus-CI logs/artifacts.
             e.g. "cirrus-ci-6707778565701632-fcae48" for podman
    Build ID - string, the build containing tasks w/ artifacts to download
               e.g. "5790771712360448"
    Path RX - Optional, regular expression to include, matched against path
              format as: task_name/artifact_name/file_name
"""

import sys
from urllib.parse import quote, unquote
from os import makedirs
from os.path import basename, dirname, join
import re
import aiohttp

import requests
# Ref: https://gql.readthedocs.io/en/latest/index.html
# pip3 install --user --requirement ./requirements.txt
# (and/or in a python virtual environment)
from gql import gql
from gql.transport.requests import RequestsHTTPTransport
from gql import Client as GQLClient

# Ref: https://docs.aiohttp.org/en/stable/http_request_lifecycle.html
import asyncio

# Base URL for accessing google cloud storage buckets
GCS_URL_BASE = "https://storage.googleapis.com"

# GraphQL API URL for Cirrus-CI
CCI_GQL_URL = "https://api.cirrus-ci.com/graphql"


def get_raw_taskinfo(gqlclient, build_id):
    """Given a build ID, return a list of task objects"""
    query = gql('''
        query tasksByBuildID($build_id: ID!) {
          build(id: $build_id) {
            tasks {
              name,
              id,
              artifacts {
                name,
                files {
                  path
                }
              }
            }
          }
        }
    ''')
    query_vars = dict(build_id=build_id)
    result = gqlclient.execute(query, variable_values=query_vars)
    if "build" in result and result["build"]:
        result = result["build"]
        if "tasks" in result and len(result["tasks"]):
            return result["tasks"]
        else:
            raise RuntimeError(f"No tasks found for build with id {build_id}")
    else:
        raise RuntimeError(f"No Cirrus-CI build found with id {build_id}")


def art_to_url(tid, artifacts, repo, bucket):
    """Given an list of artifacts from a task object, return tuple of names and urls"""
    if "/" not in repo:
        raise RuntimeError(f"Expecting slash sep. repo. owner and name: '{repo}'")
    result = []
    # N/B: Structure comes from query in get_raw_taskinfo()
    for art in artifacts:
        try:
            key="name"  # Also used by exception
            art_name = quote(art[key])  # Safe use as URL component
            key="files"
            art_files = art[key]
        except KeyError:
            # Invalid artifact for some reason, skip it with warning.
            sys.stderr.write(f"Warning: Encountered malformed artifact for TID {tid}, missing expected key '{key}'")
            continue
        for art_file in art_files:
            art_path = quote(art_file["path"])  # NOT AN ACTUAL DIRECTORY STRUCTURE
            url = f"{GCS_URL_BASE}/{bucket}/artifacts/{repo}/{tid}/{art_name}/{art_path}"
            # Prevent clashes if/when same file/path (part of URL) is contained
            # in several named artifacts.
            result.append((art_name, url))
    return result

def get_task_art_map(gqlclient, repo, bucket, build_id):
    """Rreturn map of task name/artifact name to list of artifact URLs"""
    tid_map = {}
    for task in get_raw_taskinfo(gqlclient, build_id):
        tid = task["id"]
        artifacts = task["artifacts"]
        art_names_urls = art_to_url(tid, artifacts, repo, bucket)
        if len(art_names_urls):
            tid_map[task["name"]] = art_names_urls
    return tid_map

async def download_artifact(session, art_url):
    """Asynchronous download contents of art_url as a byte-stream"""
    async with session.get(art_url) as response:
        # ref: https://docs.aiohttp.org/en/stable/client_reference.html#aiohttp.ClientResponse.read
        return await response.read()

async def download_artifacts(task_name, art_names_urls, path_rx=None):
    """Download artifact if path_rx unset or matches dest. path into CWD subdirs"""
    async with aiohttp.ClientSession() as session:
        for art_name, art_url in art_names_urls:
            # Cirrus-CI Always/Only archives artifacts path one-level deep
            # (i.e. no subdirectories).  The artifact name and filename were
            # are part of the URL, so must decode them. See art_to_url() above
            dest_path = join(task_name, unquote(art_name), basename(unquote(art_url)))
            if path_rx is None or bool(path_rx.search(dest_path)):
                print(f"Downloading '{dest_path}'")
                sys.stderr.flush()
                makedirs(dirname(dest_path), exist_ok=True)
                with open(dest_path, "wb") as dest_file:
                    data = await download_artifact(session, art_url)
                    dest_file.write(data)


def get_arg(index, name):
    """Return the value of command-line argument, raise error ref: name if empty"""
    err_msg=f"Error: Missing/empty {name} argument\n\nUsage: {sys.argv[0]} <repo. owner/name> <bucket> <build ID> [path rx]"
    try:
        result=sys.argv[index]
        if bool(result):
            return result
        else:
            raise ValueError(err_msg)
    except IndexError:
        sys.stderr.write(f'{err_msg}\n')
        sys.exit(1)


if __name__ == "__main__":
    repo = get_arg(1, "repo. owner/name")
    bucket = get_arg(2, "bucket")
    build_id = get_arg(3, "build ID")
    path_rx = None
    if len(sys.argv) >= 5:
        path_rx = re.compile(get_arg(4, "path rx"))

    # Ref: https://cirrus-ci.org/api/
    cirrus_graphql_xport = RequestsHTTPTransport(
        url=CCI_GQL_URL,
        verify=True,
        retries=3)
    gqlclient = GQLClient(transport=cirrus_graphql_xport,
                          fetch_schema_from_transport=True)

    task_art_map = get_task_art_map(gqlclient, repo, bucket, build_id)
    loop = asyncio.get_event_loop()
    download_tasks = []
    for task_name, art_names_urls in task_art_map.items():
        download_tasks.append(loop.create_task(
            download_artifacts(task_name, art_names_urls, path_rx)))
    loop.run_until_complete(asyncio.gather(*download_tasks))
