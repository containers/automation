#!/bin/bash

# This helper script is intended for testing several functions
# which output calling context.  It is intended to only be used
# by the console-output unit-tests.  They are senitive to
# the both line-positions and line-content of all the following.

SCRIPT_DIRPATH=$(dirname "${BASH_SOURCE[0]}")
AUTOMATION_LIB_PATH=$(realpath "$SCRIPT_DIRPATH/../lib")
source "$AUTOMATION_LIB_PATH/common_lib.sh"

set +e

test_function() {
    A_DEBUG=1 dbg "Test dbg message"
    warn "Test warning message"
    msg "Test msg message"
    die "Test die message" 0
}

A_DEBUG=1 dbg "Test dbg message"
warn "Test warning message"
msg "Test msg message"
die "Test die message" 0

test_function
