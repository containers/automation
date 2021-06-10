#!/bin/bash

# This script is intended to be executed by the `multi-arch-build`
# github composite action.  Use under any other environment is virtually
# guaranteed to behave unexpectedly.

set -eo pipefail

source $(dirname "${BASH_SOURCE[0]}")/lib.sh

group_run setup_automation_tooling Setting up automation tooling

group_run load_runtime_environment Loading runtime environment vars

group_run reg_login Login to $INPUT_REGISTRY_NAMESPACE

VERSION=$(get_version)
FQIN2="${FQIN%%:latest}:$VERSION"
group_run push_if_new Pushing $FQIN and conditionally $FQIN2
