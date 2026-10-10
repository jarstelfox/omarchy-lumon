#!/bin/bash
# Copy the MDR screen files from the mdr-screensaver checkout into this plugin.
# Omarchy refuses symlinks inside a plugin folder (omarchy-plugin-validate: a link
# could point the trusted plugins directory at any file on disk), so the plugin
# carries real copies instead.
#
#   scripts/sync-mdr.sh           copy them in
#   scripts/sync-mdr.sh --check   only report files that differ (exit 1 if any)
#
# MDR_DIR overrides the source (default ~/.config/quickshell/mdr).
set -euo pipefail
cd "$(dirname "$0")/.."
src=${MDR_DIR:-$HOME/.config/quickshell/mdr}
files=(MdrScreen.qml crt.frag.qsb lumon.svg)
[[ -d $src ]] || { echo "no mdr-screensaver checkout at $src" >&2; exit 2; }
stale=0
for f in "${files[@]}"; do
  if ! cmp -s "$src/$f" "$f"; then
    stale=1
    if [[ ${1:-} == --check ]]; then echo "differs: $f"; else cp "$src/$f" "$f"; echo "copied: $f"; fi
  fi
done
[[ ${1:-} == --check ]] && exit $stale
(( stale )) || echo "already in sync"
