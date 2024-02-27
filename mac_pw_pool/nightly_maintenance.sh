#!/bin/bash

set -euo pipefail

cd $(dirname "${BASH_SOURCE[0]}")

SCRIPTNAME="$(basename ${BASH_SOURCE[0]})"
WEB_IMG="docker.io/library/nginx:latest"
CRONLOG="Cron.log"
CRONSCRIPT="Cron.sh"
KEEP_LINES=10000
REFRESH_REPO_EVERY=7 # days

# Do not use, these are needed to control script execution.
_CNTNAME=pw_pool_web
_FLOCKER="${_FLOCKER:-notlocked}"
_RESTARTED_SCRIPT="${_RESTARTED_SCRIPT:-0}"

if [[ ! -r "$CRONLOG" ]] || [[ ! -r "$CRONSCRIPT" ]] || [[ ! -d "../.git" ]]; then
  echo "ERROR: $SCRIPTNAME not executing from correct directory" >> /dev/stderr
  exit 1
fi

relaunch_web_container() {
  # Assume code has changed, restart container w/ latest image
  (
    set -x
    podman run --replace --name "$_CNTNAME" -d --rm --pull=newer -p 8080:80 \
      -v $HOME/devel/automation/mac_pw_pool/html:/usr/share/nginx/html:ro,Z \
      $WEB_IMG
  )
  echo "$SCRIPTNAME restarted pw_poolweb container"
}

# Don't perform maintenance while $CRONSCRIPT is running
[[ "${_FLOCKER}" != "$CRONSCRIPT" ]] && exec env _FLOCKER="$CRONSCRIPT" flock -e -w 300 "$CRONSCRIPT" "$0" "$@" || :
echo "$SCRIPTNAME running at $(date -u -Iseconds)"

if ! ((_RESTARTED_SCRIPT)); then
  today=$(date -u +%d)
  if ((today%REFRESH_REPO_EVERY)); then
    git remote update && git reset --hard origin/main
    # maintain the same flock
    echo "$SCRIPTNAME updatedd code after $REFRESH_REPO_EVERY days, restarting script..."
    env _RESTARTED_SCRIPT=1 _FLOCKER=$_FLOCKER "$0" "$@"
    exit $?  # all done
  fi
fi

tail -n $KEEP_LINES $CRONLOG > ${CRONLOG}.tmp && mv ${CRONLOG}.tmp $CRONLOG
echo "$SCRIPTNAME rotated log"

# Always restart web-container when code changes, otherwise only if required
if ((_RESTARTED_SCRIPT)); then
  relaunch_web_container
else
  podman container exists "$_CNTNAME" || relaunch_web_container
fi
