#!/usr/bin/env python3

"""
Download all artifacts from a Cirrus-CI Build into a subdirectory tree.

Subdirectory naming format: <build ID>/<task-name>/<artifact-name>/<file-path>

Input arguments (in order):
    Build ID - string, the build containing tasks w/ artifacts to download
               e.g. "5790771712360448"
    Path RX - Optional, regular expression to match against subdirectory
              tree naming format.
"""

import asyncio
import re
import sys
from argparse import ArgumentParser
from os import makedirs
from os.path import split
from urllib.parse import quote, unquote

# Ref: https://docs.aiohttp.org/en/stable/http_request_lifecycle.html
from aiohttp import ClientSession
# Ref: https://gql.readthedocs.io/en/latest/index.html
# pip3 install --user --requirement ./requirements.txt
# (and/or in a python virtual environment)

from gql import Client as GQLClient
from gql import gql
from gql.transport.requests import RequestsHTTPTransport


# GraphQL API URL for Cirrus-CI
CCI_GQL_URL = "https://api.cirrus-ci.com/graphql"

# Artifact download base-URL for Cirrus-CI.
# Download URL will be formed by appending:
# "/<CIRRUS_BUILD_ID>/<TASK NAME OR ALIAS>/<ARTIFACTS_NAME>/<PATH>"
CCI_ART_URL = "https://api.cirrus-ci.com/v1/artifact/build"

# Set True when --verbose is first argument
VERBOSE = False

def get_tasks(gqlclient, buildId):  # noqa N803
    """Given a build ID, return a list of task objects."""
    # Ref: https://cirrus-ci.org/api/
    query = gql('''
        query tasksByBuildId($buildId: ID!) {
          build(id: $buildId) {
            tasks {
              name,
              id,
              buildId,
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
    query_vars = {"buildId": buildId}
    tasks = gqlclient.execute(query, variable_values=query_vars)
    if "build" in tasks and tasks["build"]:
        b = tasks["build"]
        if "tasks" in b and len(b["tasks"]):
            return b["tasks"]
        raise RuntimeError(f"No tasks found for build with ID {buildId}")
    raise RuntimeError(f"No Cirrus-CI build found with ID {buildId}")


def task_art_url_sfxs(task):
    """Given a task dict return list CCI_ART_URL suffixes for all artifacts."""
    result = []
    bid = task["buildId"]
    tname = quote(task["name"])  # Make safe for URLs
    for art in task["artifacts"]:
        aname = quote(art["name"])
        for _file in art["files"]:
            fpath = quote(_file["path"])
            result.append(f"{bid}/{tname}/{aname}/{fpath}")
    return result


async def download_artifact(session, dest_path, dl_url):
    """Asynchronous download contents of art_url as a byte-stream."""
    # Last path component assumed to be the filename
    makedirs(split(dest_path)[0], exist_ok=True)  # os.path.split
    async with session.get(dl_url) as response:
        with open(dest_path, "wb") as dest_file:
            dest_file.write(await response.read())


async def download_artifacts(task, path_rx=None):
    """Given a task dict, download all artifacts or matches to path_rx."""
    downloaded = []
    skipped = []
    async with ClientSession() as session:
        for art_url_sfx in task_art_url_sfxs(task):
            dest_path = unquote(art_url_sfx)  # Strip off URL encoding
            dl_url = f"{CCI_ART_URL}/{dest_path}"
            if path_rx is None or bool(path_rx.search(dest_path)):
                if VERBOSE:
                    print(f"    Downloading '{dest_path}'")
                    sys.stdout.flush()
                await download_artifact(session, dest_path, dl_url)
                downloaded.append(dest_path)
            else:
                if VERBOSE:
                    print(f"       Skipping '{dest_path}'")
                skipped.append(dest_path)
    return {"downloaded": downloaded, "skipped": skipped}


def get_args(argv):
    """Return parsed argument namespace object."""
    parser = ArgumentParser(prog="cirrus-ci_artifacts",
                            description=('Download Cirrus-CI artifacts by Build ID'
                                         ' number, into a subdirectory of the form'
                                         ' <Build ID>/<Task Name>/<Artifact Name>'
                                         '/<File Path>'))
    parser.add_argument('-v', '--verbose',
                        dest='verbose', action='store_true', default=False,
                        help='Show "Downloaded" | "Skipped" + relative artifact file-path.')
    parser.add_argument('buildId', nargs=1, metavar='<Build ID>', type=int,
                        help="A Cirrus-CI Build ID number.")
    parser.add_argument('path_rx', nargs='?', default=None, metavar='[Reg. Exp.]',
                        help="Reg. exp. include only <task>/<artifact>/<file-path> matches.")
    return parser.parse_args(args=argv[1:])


async def download(tasks, path_rx=None):
    """Return results from all async operations."""
    # Python docs say to retain a reference to all tasks so they aren't
    # "garbage-collected" while still active.
    results = []
    for task in tasks:
        if len(task["artifacts"]):
            results.append(asyncio.create_task(download_artifacts(task, path_rx)))
    await asyncio.gather(*results)
    return results


def main(buildId, path_rx=None):  # noqa: N803,D103
    if path_rx is not None:
        path_rx = re.compile(path_rx)
    transport = RequestsHTTPTransport(url=CCI_GQL_URL, verify=True, retries=3)
    with GQLClient(transport=transport, fetch_schema_from_transport=True) as gqlclient:
        tasks = get_tasks(gqlclient, buildId)
    transport.close()
    async_results = asyncio.run(download(tasks, path_rx))
    return [r.result() for r in async_results]


if __name__ == "__main__":
    args = get_args(sys.argv)
    VERBOSE = args.verbose
    main(args.buildId[0], args.path_rx)
