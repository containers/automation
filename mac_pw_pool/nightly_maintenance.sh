#!/bin/bash

set -euo pipefail

cd $(dirname "${BASH_SOURCE[0]}")

SCRIPTNAME="$(basename ${BASH_SOURCE[0]})"
WEB_IMG="docker.io/library/nginx:latest"
CRONLOG="Cron.log"
CRONSCRIPT="Cron.sh"
KEEP_LINES=10000
MAX_REPO_AGE_DAYS=21

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
    podman run --replace --name "$_CNTNAME" -it --rm --pull=newer -p 8080:80 \
      -v $HOME/devel/automation/mac_pw_pool/html:/usr/share/nginx/html:ro,Z \
      $WEB_IMG
  )
  echo "$SCRIPTNAME restarted pw_poolweb container"
}

# Don't perform maintenance while $CRONSCRIPT is running
[[ "${_FLOCKER}" != "$CRONSCRIPT" ]] && exec env _FLOCKER="$CRONSCRIPT" flock -e -w 300 "$CRONSCRIPT" "$0" "$@" || :
echo "$SCRIPTNAME running at $(date -u -Iseconds)"

if ! ((_RESTARTED_SCRIPT)); then
  # Make sure the recent code is being used.
  last_commit_date=$(git log -1 --format="%cI" --no-show-signature  HEAD)
  last_s=$(date -d "$last_commit_date" +%s)
  now_s=$(date -u +%s)
  diff_s=$((now_s-last_s))

  if [[ "$diff_s" -gt $(($MAX_REPO_AGE_DAYS*24*60*60)) ]]; then
    git remote update && git reset --hard origin/main
    # maintain the same flock
    echo "$SCRIPTNAME updatedd code older than $MAX_REPO_AGE_DAYS days, restarting script..."
    env _RESTARTED_SCRIPT=1 _FLOCKER=$_FLOCKER "$0" "$@"
    exit $?  # all done
  else
    echo "$SCRIPTNAME code appears recent ($last_commit_date), yay!"
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
