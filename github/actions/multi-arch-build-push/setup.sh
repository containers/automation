#!/bin/bash

# This script is intended to be executed by the `multi-arch-build`
# github composite action.  Use under any other environment is virtually
# guaranteed to behave unexpectedly.

set -eo pipefail

source $(dirname "${BASH_SOURCE[0]}")/lib.sh

# Make sure these values are masked in the output...by printing them to output,
# which isn't weird or prone to bugs/accidents.  Thanks github.
echo "::add-mask::$INPUT_REGISTRY_USERNAME"
echo "::add-mask::$INPUT_REGISTRY_PASSWORD"

group_run install_automation_tooling Install common automation tooling libraries

group_run setup_automation_tooling Setting up automation tooling

group_run show_env_vars Environment Variables

group_run tooling_versions Podman, Buildah, and Skopeo versions

group_run verify_runtime_environment Verify environment expectations

group_run load_runtime_environment Loading runtime environment vars

msg "Creating directory for arch-image exports:"
mkdir -vp "$BUILDTMP/images"

group_run setup_qemu_binfmt Configure QEMU for execution of non-native binaries
