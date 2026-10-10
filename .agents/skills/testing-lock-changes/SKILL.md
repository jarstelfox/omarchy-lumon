---
name: testing-lock-changes
description: >-
  Tests a change to this Omarchy lock plugin without risking a locked-out
  user: a fake-auth harness first, then the shell's lock preview, then a real
  lock with a recovery watcher running. Use after editing LockView.qml,
  Service.qml or the copied MDR files, before telling the user a lock change
  works, or when the user wants to try a real lock.
---

# Testing lock changes

The order matters because each step is riskier than the last: a view that
fails to load inside a real lock leaves the user with nothing to type into.
Stop at the first step that shows a problem.

The harness and the preview both take **exclusive keyboard focus**, so the
user's typing and dictation go into them. Tell the user before each run and
wait for a yes. Never type, ask for or handle the user's real password.

## 1. Harness: the view with fake authentication

`test-lock.qml` runs `LockView.qml` in a plain overlay with fake auth: `lumon` unlocks and quits, anything else fails, and it quits
itself after 60 seconds. It never touches the real lock.

```bash
timeout 30 qs -n -p test-lock.qml > /tmp/lock-test.log 2>&1 &
sleep 2.5
echo "key x" | dotoolc          # reveals the login; this first key is swallowed
echo "type wrong" | dotoolc; echo "key enter" | dotoolc; sleep 1.4
grim /tmp/lock-fail.png          # expect AUTHENTICATION FAILED (1)
echo "type lumon" | dotoolc; echo "key enter" | dotoolc; sleep 1.5
hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == "lumon-lock-test")] | length > 0' \
  && echo "still up: the right password did not unlock" || echo "unlocked"
```

The harness logs `LOCKTEST submit <n> chars` for each submit, so a stray
submit (from the user typing into it) shows up in the log. Once the login is
showing, every key types: don't send a waking key then.

Check presence with the layer query above, not `pgrep -f`, which matches the
shell running the check.

## 2. Preview inside the real shell

The shell runs the plugin folder (`~/.config/omarchy/plugins/lumon.lock`), so
the change has to be there. To check the safety net as well, add a stray `}`
to `LockView.qml` there, restart and preview: the plain fallback password field
should show. Put the file back with `git checkout -- LockView.qml` and restart
again before going on.

```bash
omarchy restart shell            # the only way past Qt's QML type cache
omarchy-shell lock preview; sleep 3; grim /tmp/lock-preview.png; omarchy-shell lock hidePreview
journalctl --user --since "-1 min" --no-pager | grep -E 'LockView|MdrScreen'
```

The preview draws the view in a window without locking anything. Its input
is off, so it shows the idle MDR screen and not the login. Any load error in
the journal stops here.

## 3. A real lock, with the user present

Start the watcher first, giving it the last commit whose view is known to
work. If the lock fails to load or the shell dies while locked, it puts that
commit's `Service.qml`, `LockView.qml`, `MdrScreen.qml` and `Settings.js` back
(keeping any uncommitted edits as `<file>.bak-<time>`) and restarts the shell,
which locks again with them. It never unlocks.

```bash
.agents/skills/testing-lock-changes/scripts/watch-lock.sh /tmp/lock-watch.log <good-rev> &
```

Then the user runs `omarchy system lock`, unlocks with their password, and
the log ends with `unlocked normally`. Before they lock, give them the manual
recovery from the README ("If a lock ever gets stuck"): it's the fallback if
the watcher can't help.
