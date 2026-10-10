#!/bin/bash
# Watch one real lock and unlock. If the lock fails to load, or the shell dies while locked,
# put the lock's QML back from a known-good commit and restart the shell: the restarted shell
# finds the session still locked and locks it again with that version. Never unlocks.
# Uncommitted edits to those files are copied to <file>.bak-<time> first (gitignored).
#
#   watch-lock.sh <log-file> [good-rev]     good-rev defaults to HEAD
set -u
P=$(cd "$(dirname "$0")/../../../.." && pwd)    # the plugin's root
LOG=${1:?usage: watch-lock.sh <log-file> [good-rev]}
GOOD=${2:-HEAD}
git -C "$P" rev-parse --verify -q "$GOOD^{commit}" >/dev/null || { echo "not a commit: $GOOD" >&2; exit 2; }
since=$(date '+%Y-%m-%d %H:%M:%S')
seen_lock=0; end=$((SECONDS + 900))
say() { echo "$(date +%T) $*" >> "$LOG"; }

restore() {
  say "RESTORING the lock's QML from $GOOD: $1"
  local f stamp; stamp=$(date +%s)
  for f in Service.qml LockView.qml MdrScreen.qml Settings.js; do
    [[ -f $P/$f ]] && ! git -C "$P" diff --quiet "$GOOD" -- "$f" 2>/dev/null && cp "$P/$f" "$P/$f.bak-$stamp" && say "kept your $f as $f.bak-$stamp"
  done
  git -C "$P" checkout "$GOOD" -- Service.qml LockView.qml MdrScreen.qml
  git -C "$P" cat-file -e "$GOOD:Settings.js" 2>/dev/null && git -C "$P" checkout "$GOOD" -- Settings.js
  omarchy restart shell >> "$LOG" 2>&1
  sleep 6
  say "status after restore: $(omarchy-shell lock status 2>&1 | head -c 200)"
  exit 1
}

say "watching $P, good view $GOOD"
while (( SECONDS < end )); do
  # tostring, not `// empty`: jq's // treats false as missing
  locked=$(timeout 3 omarchy-shell lock status 2>/dev/null | jq -r '.locked | tostring' 2>/dev/null)
  if [[ $locked == true && $seen_lock == 0 ]]; then seen_lock=1; say "locked"; fi
  if [[ $seen_lock == 1 && $locked == false ]]; then say "unlocked normally"; exit 0; fi

  bad=$(journalctl --user --since "$since" --no-pager 2>/dev/null \
    | grep -E 'LockView\.qml|MdrScreen\.qml|Service\.qml|Settings\.js|service plugin load failed|lock-view-failed' \
    | grep -iE 'is not a type|unavailable|failed to load|error loading|Cannot create|component is not ready|load failed|lock-view-failed' | tail -1)
  [[ -n $bad ]] && restore "$bad"
  # the bracket keeps this pattern from matching the command line of the check itself
  if [[ $seen_lock == 1 ]] && ! pgrep -f '[q]uickshell.*-p /usr/share/omarchy/shell' >/dev/null; then
    restore "shell process gone while locked"
  fi
  sleep 2
done
say "timed out after 15 minutes, no action taken"
