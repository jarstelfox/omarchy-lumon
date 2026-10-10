# MDR screensaver

A Quickshell (QML) recreation of the *Severance* MDR screen. `MdrScreen.qml`
is the screen; `shell.qml` wraps it as a standalone screensaver
(`qs -n -c mdr`), and a separate lock-screen plugin embeds it.

## Gotchas

- **The lock plugin copies these files and uses this interface.**
  omarchy-lumon-lock carries copies of `MdrScreen.qml`, `crt.frag.qsb` and
  `lumon.svg` (its `scripts/sync-mdr.sh` copies them from here) and uses
  MdrScreen's `crt`, `running`, `activity` and `outsideClicked`. A change here
  reaches the lock only after that sync, and renaming the files or those
  members breaks its idle view.
- **The CRT curve lives in two places.** `crt.frag` bends the picture and
  `MdrScreen.toContent` bends the pointer by the same formula (0.035, 0.05).
  Change one without the other and near the corners the swell stops sitting
  under the pointer.
- **Qt Quick only loads the compiled shader.** After editing `crt.frag`,
  rebuild `crt.frag.qsb` (`/usr/lib/qt6/bin/qsb --qt6 -o crt.frag.qsb crt.frag`)
  and commit both.
- **The header percent is the average of the bins**, by design: the show's
  Cold Harbor still pairs bins 77/75/59/52/75 with "67% Complete". Keep the two
  linked.
- **Only Cold Harbor and Siena are confirmed file names** (both appear in
  stills from the show). The rest of `files` are from memory.
- **Clusters must stay inside the visible rows.** The grid builds one more row
  than fits, so partial rows peek under the rules. A cluster placed in that
  hidden row flies digits in from off screen when refined; `newCluster` and
  `onScreen` prevent it.
- **QML traps hit here:** inside a `Rotation` or an animation object, `parent`
  is not the item (use an id), and a function named `visible` clashes with
  every Item's property of that name.

## Running it covers the screen

`qs -n -c mdr` is a fullscreen overlay with exclusive keyboard focus. While it
runs, every key press goes to it, including dictation and typing meant for
other apps. Ask the user before running it, and keep runs short (`timeout`).
For screenshots and multi-size checks, use the `testing-mdr-screen` skill.
