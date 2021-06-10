#!/bin/bash

# This script is intended to be executed by the `multi-arch-build`
# github composite action.  Use under any other environment is virtually
# guaranteed to behave unexpectedly.

set -eo pipefail

source $(dirname "${BASH_SOURCE[0]}")/lib.sh

group_run setup_automation_tooling Setting up automation tooling

group_run load_runtime_environment Loading runtime environment vars

group_run "podman manifest create $FQIN" Create manifest image for $FQIN

# Every arch needs to download/install potentially many packages.
# Improve overall runtime by allowing this to execute in parallel.
declare -a jobs
for arch in $INPUT_BUILD_ARCHES; do
    build_image_arch > "/tmp/build_${arch}_${_FQIN}.log" 2>&1 &
    jid="$!"
    msg "Building $FQIN for $arch as job $jid"
    # Track job IDs + arch to provide status info.
    jobs+=("$jid,$arch")
done

msg "Waiting for builds to complete..."
something_broke=0
for jid_arch in ${jobs[*]}; do
    jid=$(cut -d "," -f 1 <<<"$jid_arch")
    arch=$(cut -d "," -f 2 <<<"$jid_arch")
    word=""
    if wait $jid; then
        word="successful"
    else
        word="failed (exit $?)"
        something_broke=1
    fi
    group_run "cat /tmp/build_${arch}_${_FQIN}.log" "Job $jid for $arch build of $FQIN $word."
done

if ((something_broke)); then
    die "At least one build failed, not continuing"
fi

group_run combine_images "Combining all images into $FQIN manifest"
