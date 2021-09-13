#!/bin/bash

# This file is intended to be sourced as a short-cut to loading
# all common libraries one-by-one.

AUTOMATION_LIB_PATH="${AUTOMATION_LIB_PATH:-$(dirname ${BASH_SOURCE[0]})}"

# Filename list must be hard-coded
# When installed, other files may be present in lib directory
COMMON_LIBS="anchors.sh defaults.sh platform.sh utils.sh console_output.sh"
for filename in $COMMON_LIBS; do
    source $(dirname "$BASH_SOURCE[0]}")/$filename
done
