# Omarchy Lumon

An Omarchy shell plugin (`lumon.lock`) that replaces Omarchy's lock screen,
plus the same MDR screen as a standalone screensaver. `Service.qml` is
Omarchy's session lock and PAM flow with a few `// Local change:` edits;
`LockView.qml` draws the lock; `MdrScreen.qml` is the screen both use;
`Settings.js` reads the plugin's settings from `shell.json`.

## Gotchas

- **A broken lock can leave the session unlocked.** An error in `Service.qml`
  means no lock at all, and nothing reports it: the clone disables
  `omarchy.lock`, and `omarchy-system-lock` discards the lock command's result.
  `LockView.qml` and `MdrScreen.qml` load through Loaders with a fallback, so
  their errors degrade to a plain password field or the login. Before any
  `omarchy restart shell`, follow `.agents/skills/testing-lock-changes/SKILL.md`.
- **`LockView.qml` must keep its interface.** `Service.wireLockView` binds the
  view by property name (only names the view declares) and connects
  `submitPassword`, `passwordTextEdited`, `clearFailureRequested` and
  `wakeRequested`. The fallback in `Service.qml` implements the same minimum.
- **Nothing is hard-coded that a user might want different.** Timings and
  looks are settings in `Settings.js` with defaults and limits, read from the
  plugin's `shell.json` entry. Add new ones there, with a check in
  `tests/settings.test.js`, not as constants in QML.
- **Saving a file doesn't update the running lock.** The plugin is
  `keepLoaded`, and Qt caches compiled QML types. Run `omarchy restart shell`.
- **`Service.qml` is security code.** Keep edits small and mark each with a
  `// Local change:` comment, so a diff against Omarchy's
  `shell/plugins/lock/Service.qml` (`/usr/share/omarchy/shell/` when installed)
  shows what's ours after an Omarchy update.
- **Keep `omarchy.clonedFrom: omarchy.lock` in the manifest.** It's the only
  way a third-party plugin gets the trusted `authentication` capability
  (`stampHostCapabilities` in Omarchy's `PluginRegistry.qml`), which keeps the
  lock outside the shell's shared service map. The marketplace guide says to
  drop `clonedFrom` before publishing; for a lock that would weaken it.
- **No symlinks anywhere in the repo.** `omarchy-plugin-validate` refuses them
  (a link could point the trusted plugins folder at any file), and
  `omarchy plugin add` and `update` run that check.
- **Runnable QML lives at the root.** Quickshell refuses imports from outside
  the folder it runs, so `screensaver.qml` and `test-lock.qml` sit next to the
  files they use (`qs -n -p screensaver.qml`). The scanner's warning about
  `Service.qml`'s `qs.Commons` import there is harmless.
- **The CRT curve lives in two places.** `crt.frag` bends the picture and
  `MdrScreen.toContent` bends the pointer by the same formula (0.035, 0.05).
  Change both, or near the corners the swell stops sitting under the pointer.
  After editing `crt.frag`, rebuild and commit `crt.frag.qsb`.
- **The header percent is the average of the bins**, by design: the show's
  Cold Harbor still pairs bins 77/75/59/52/75 with "67% Complete".
- **Only Cold Harbor and Siena are confirmed file names** (both appear in
  stills from the show). The rest of the default `files` are from memory.
- **QML traps hit here:** inside a `Rotation` or an animation object, `parent`
  is not the item (use an id), and a function named `visible` clashes with
  every Item's property of that name.

## Running anything covers the screen

The screensaver, the lock harness and the lock preview are fullscreen
overlays with exclusive keyboard focus: the user's typing and dictation go
into them. Ask before each run, keep runs under `timeout`, and never type,
ask for or handle the user's real password. For the MDR screen use
`.agents/skills/testing-mdr-screen/SKILL.md`; for the lock,
`.agents/skills/testing-lock-changes/SKILL.md`.
