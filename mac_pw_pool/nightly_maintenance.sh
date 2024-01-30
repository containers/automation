#!/bin/bash

set -euo pipefail

CRONLOG=$HOME/devel/automation/mac_pw_pool/Cron.log
KEEP_LINES=10000
set -x
tail -n $KEEP_LINES $CRONLOG > ${CRONLOG}.tmp && mv ${CRONLOG}.tmp $CRONLOG

# Ensure the utilization graph always runs the latest image
podman run --replace -d --rm --name pw_pool_web \
  -p 8080:80 --security-opt label=disable \
  -v $HOME/devel/automation/mac_pw_pool/html:/usr/share/nginx/html:ro \
  --pull=newer \
  docker.io/library/nginx:latest
