# Omarchy Lumon lock

A clone of Omarchy's `omarchy.lock` shell plugin. `Service.qml` is Omarchy's
session lock and PAM flow with a few changes; `LockView.qml` is the drawn
screen (the MDR screen while idle, a Lumon terminal login after a key press).

## Gotchas

- **A broken lock view can lock the user out.** A view that fails to load
  leaves a locked session with nothing to type into. Never reach a real lock
  untested: read and follow `.agents/skills/testing-lock-changes/SKILL.md`,
  which goes harness, preview, then a real lock with a recovery watcher
  running.
- **`LockView.qml` must keep the stock view's interface.** `Service.qml` sets
  `backgroundPath`, `backgroundVersion`, `fingerprintConfigured`,
  `authenticatingPassword`, `failureMessage`, `failedAttempts`,
  `inputEnabled`, `loadBackground` and `passwordText`, and listens for
  `submitPassword`, `passwordTextEdited`, `clearFailureRequested` and
  `wakeRequested`. Renaming any of them breaks the lock.
- **Saving a file doesn't update the running lock.** The shell logs "Local
  plugin changed, reloading" and recreates the service, but Qt's QML type
  cache keeps the old `LockView.qml`. Run `omarchy restart shell` to see a
  change.
- **`Service.qml` is security code.** It runs the session lock and PAM. Keep
  edits there small and mark each with a `// Local change:` comment, so a diff
  against Omarchy's upstream `plugins/lock/Service.qml` (in
  `/usr/share/omarchy/shell/` on an installed system) shows what's ours after
  an Omarchy update.
- **`MdrScreen.qml`, `crt.frag.qsb` and `lumon.svg` are copies** from the
  mdr-screensaver repo. Edit them there, then run `scripts/sync-mdr.sh`
  (`--check` reports drift).
- **No symlinks anywhere in this folder.** `omarchy-plugin-validate` refuses
  them, because a link could point the trusted plugins directory at any file
  on disk, and `omarchy plugin add` and `update` run that check. That's also
  why the testing skill below has no `.claude/skills` link.
- **Clicks belong to MDR on the digit grid.** Elsewhere a click shows the
  login (MdrScreen's `outsideClicked`); a key press always does, and that
  first key is swallowed, not typed.
- **Test overlays take the keyboard.** The harness and the lock preview grab
  exclusive keyboard focus, so the user's typing and dictation go into them.
  Ask before running either.
- **Never handle the user's password.** Real-lock tests are for the user to
  unlock; fake-auth tests use the harness.
