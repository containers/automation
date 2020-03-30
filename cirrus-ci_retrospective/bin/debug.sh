#!/bin/bash

# This script assists with debugging cirrus-ci_retrospective.sh
# manually/locally or remotely in a github action.
#
# Usage: You need to export a valid $GITHUB_EVENT_PATH and $GITHUB_TOKEN value.
# The referenced event file, should be the JSON file from a "check_suite" event
# from a github action with a status of "completed".  There should be a "debug"
# github action active on this repo. to produce this as an artifact.  Check
# YAML files under $REPO_ROOT/.github/workflows/ for github action configs.
#
# The $GITHUB_TOKEN value may be a personal access token obtained from github
# under settings -> developer settings -> personal access token.
# When creating a new token, you need to enable the following scopes:
#
# read:discussion, read:enterprise, read:gpg_key, read:org, read:public_key,
# read:repo_hook, read:user, repo:status, repo_deployment, user:email

set -eo pipefail

# Do not use magic default values set by common.sh
DEBUG_MSG_PREFIX="DEBUG:"
WARNING_MSG_PREFIX="WARNING:"
ERROR_MSG_PREFIX="ERROR:"
source "$(dirname $0)/../lib/common.sh"
DEBUG_SUBJECT_FILEPATH="$SCRIPT_PATH/cirrus-ci_retrospective.sh"

[[ -x "$DEBUG_SUBJECT_FILEPATH" ]] || \
    die "Expecting to find $DEBUG_SUBJECT_FILEPATH executable"

# usage: <env. var> [extra read args]
set_required_envvar() {
    local envvar=$1
    local xtra=$2

    if [[ -z "${!envvar}" ]]; then
        MSG="A non-empty value for \$$envvar is required."
        warn "$MSG"
        # Use timeout in case of executing under unsupervised automation
        read -p "Please enter the value to use, within 30-seconds: " -t 30 $xtra $envvar
        [[ -n "${!envvar}" ]] || \
            die "$MSG"
    fi
}

set_required_envvar GITHUB_TOKEN -s
set_required_envvar GITHUB_EVENT_PATH

_MSGPFX="Expecting $GITHUB_EVENT_PATH to contain a 'check_suite'"
if ! jq .check_suite < "$GITHUB_EVENT_PATH" | head -1; then
    die "$_MSGPFX map."
fi

export GITHUB_TOKEN

[[ $(jq --raw-output .check_suite.app.name < "$GITHUB_EVENT_PATH" | head -1) == "Cirrus CI" ]] || \
    die "$_MSGPFX from Cirrus-CI"
unset _MSGPFX

export GITHUB_EVENT_PATH
export GITHUB_EVENT_NAME=check_suite  # Validated above
export GITHUB_ACTIONS=true            # Mock value from Github Actions
export GITHUB_WORKSPACE="${GITHUB_WORKSPACE:-$SCRIPT_PATH/../../}"
export DEBUG=1                        # The purpose of this script

$DEBUG_SUBJECT_FILEPATH
