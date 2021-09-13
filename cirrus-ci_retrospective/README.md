# Overview

This directory contains the necessary pieces to produce a container image
for execution in Github Actions workflow.  Simply stated, it cross-references
and provides all necessary contextual details to automate followup tasks and
behaviors which are guaranteed to occur after completion of a Cirrus-CI build.

For example, it can collate and process individual Cirrus-CI Task results and
attachments.  Determine if the Cirrus-CI build occurred on a PR, and if so
provide additional feedback to the author.  It could also be used to automatically
and securely produce certified/signed OS Package builds following subsequent
to tests passing on a tagged commit.

# Example Github Action Workflow

On the 'main' (default) branch of a repository (previously setup and running
tasks in Cirrus-CI), add the following file:

`.github/workflows/cirrus-ci_retrospective.yml`
```yaml

on:
    check_suite:  # ALWAYS triggered from the default branch
        types:
            - completed

jobs:
    if: github.event.check_suite.app.name == 'Cirrus CI'
    runs-on: ubuntu-latest
    steps:
        - name: Execute latest upstream cirrus-ci_retrospective
          uses: docker://quay.io/libpod/cirrus-ci_retrospective:v1.0.0
          env:
            GITHUB_TOKEN: ${{ github.token }}

        ...act on contents of ./cirrus-ci_retrospective.json...
```

## Dependencies:

In addition to the basic `common` requirements (see [top-level README.md](../README.md))
the following system packages (or their equivalents) are needed:

* curl
* jq
* sed

## Usage Notes:

* The trigger, `check_suite` type `completed` is the only event currently supported
  by the container.  This is not a technical limitation however.

* There is only ever one `check_suite` created per commit ID of a repository.  If
  a build is re-run in Cirrus-CI, it will result in re-triggering the workflow.

* It's possible for multiple runs of the workflow to be executing simultaneously
  against the same commit-id.  Depending on various timing factors and external
  forces.  For example, a branch-push and a tag-push.

* The job _must_ filter on `github.event.check_suite.app.name` to avoid
  needlessly executing against other CI-systems Check Suites.

* Implementations should utilize the version-tagged container images to provide
  behavior and output-format stability.

## Warning

Due to security concerns, Github Actions only supports execution vs check_suite events
from workflows already committed on the 'main' branch.  This makes it difficult to
test implementations, since they will not execute until merged.

However, the output JSON does provide all the necessary details to re-create, then possibly
re-execute the changes proposed in a PR.  This fact is utilized in _this_ repository to
perform test-executions for PRs.  See the workflow file for comments on related details.


# Output Decoding

The output JSON is an `array` of all Cirrus-CI tasks which completed after being triggered by
one of the supported mechanisms (i.e. PR push, branch push, or tag push).  At the time
this was written, CRON-based runs in Cirrus-CI do not trigger a `check_suite` in Github.
Otherwise, based on various values in the output JSON, it is possible to objectively
determine the execution context for the build.

*Note*: The object nesting is backwards from what you may expect.  The top-level object
represents an individual `task`, but contains it's `build` object to make parsing
with `jq` easier.  In reality, the data model actually represents a single `build`,
containing multiple `tasks`.

## After pushing to pull request number 34

```json
    {
        id: "1234567890",
        ...cut...
        "build": {
            "id": "0987654321"
            "changeIdInRepo": "679085b3f2b40797fedb60d02066b3cbc592ae4e",
            "branch": "pull/34",
            "pullRequest": 34,
            ...cut...
        }
        ...cut...
    }
```

## Pull request 34's `trigger_type: manual` task (not yet triggered)

```json
    {
        id: "something",
        ...cut...
        "status": "PAUSED",
        "automaticReRun": false,
        "build": {
            "id": "otherthing"
            "changeIdInRepo": "679085b3f2b40797fedb60d02066b3cbc592ae4e",
            "branch": "pull/34",
            "pullRequest": 34,
        }
        ...cut...
    }
```

*Important note about manual tasks:* Manually triggering an independent the task
***will not*** result in a new `check_suite`.  Therefore, the cirrus-ci_retrospective
action will not execute again, irrespective of pass, fail or any other manual task status.
Also, if any task in Cirrus-CI is dependent on a manual task, the build itself will not
conclude until the manual task is triggered and completes (pass, fail, or other).

## After merging pull request 34 into main branch (merge commit added)

```json
    {
        ...cut...
        "build": {
            "id": "foobarbaz"
            "changeIdInRepo": "232bae5d8ffb6082393e7543e4e53f978152f98a",
            "branch": "main",
            "pullRequest": null,
            ...cut...
        }
        ...cut...
    }
```

## After pushing the tag `v2.2.0` on former pull request 34's HEAD

```json
    {
        id: "1234567890",
        ...cut...
        "build": {
            ...cut...
            "changeIdInRepo": "679085b3f2b40797fedb60d02066b3cbc592ae4e",
            "branch": "v2.2.0",
            "pullRequest": null,
            ...cut...
        }
        ...cut...
    }
```

## Recommended `jq` filters for `cirrus-ci_retrospective.json`

Given a "conclusion" task name in Cirrus-CI (e.g. `cirrus-ci/test_success`):

* Obtain the pull number (set `null` if Cirrus-CI ran against a branch or tag)
  `'.[] | select(.name == "cirrus-ci/test_success") | .build.pullRequest'`

* Obtain the HEAD commit ID used by Cirrus-CI for the build (always available)
  `'.[] | select(.name == "cirrus-ci/test_success") | .build.changeIdInRepo'`

* ...todo: add more
