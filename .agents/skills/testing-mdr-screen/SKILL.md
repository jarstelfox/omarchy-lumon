---
name: testing-mdr-screen
description: >-
  Checks a change to the MDR screensaver on the real display: runs it briefly,
  moves the pointer, screenshots it, reads the log, and tries other monitor
  sizes. Use after editing MdrScreen.qml, shell.qml, crt.frag or lumon.svg,
  when asked to screenshot or preview the MDR screen, or to test hover, refine
  clicks, bins, file completion or multi-monitor layout.
---

# Testing the MDR screen

The screensaver is a fullscreen overlay that takes **exclusive keyboard
focus**. Anything the user types or dictates while it runs goes into it. So
before the first run, tell the user it will cover the screen for a few seconds
and wait for a yes. Keep every run under `timeout`.

## One run with a screenshot

```bash
timeout 6 qs -n -c mdr > /tmp/mdr.log 2>&1 &
sleep 2.5
echo "mouseto 0.5 0.5" | dotoolc     # pointer to mid-screen (fractions of the screen)
sleep 0.8
hyprctl cursorpos                    # dotool lands near, not exactly on, the target
grim -c /tmp/mdr.png                 # -c draws the pointer into the shot
wait
grep -vE 'qt.qpa.services|Launching|Shell ID|Saving logs|Configuration Loaded' /tmp/mdr.log
```

The `qt.qpa.services ... Could not register app ID` warning appears on every
Quickshell start, the desktop shell's own included; it's harmless. Anything
else in the log is worth reading.

Look at the screenshot before reporting: a run that loads without errors can
still draw wrong.

## Other monitor sizes

`MDR_FAKE_SIZE` lays the screen out as another size and shrinks it to fit this
display, so one monitor can check them all:

```bash
for sz in 1920x1080 3440x1440 1080x1920 1366x768; do
  MDR_FAKE_SIZE=$sz timeout 4 qs -n -c mdr >/dev/null 2>&1 &
  sleep 2.8; grim /tmp/mdr-$sz.png; wait
done
```

16:9, ultrawide, portrait and a small laptop cover the layout's cases. This is
not a real second monitor: separate screens run separate files, and that only
shows on real hardware.

## Clicking a cluster

Clusters are random and hidden, so a refine test needs their positions. Add a
temporary line to `grid` in `MdrScreen.qml` that logs each cluster's centre in
screen pixels, run, read the log, `mouseto` and `click left` there:

```qml
Timer { interval: 500; running: true; onTriggered: grid.clusters.forEach(q => console.log("MDRDEBUG " + (grid.x + grid.ox + (q.c + 0.5) * grid.cellW).toFixed(0) + " " + (grid.y + grid.oy + (q.r + 0.5) * grid.cellH).toFixed(0))) }  // DEBUG
```

`mouseto` takes fractions, so divide by the screen's logical size
(`hyprctl monitors -j`). Remove the line afterwards and check
`grep -c DEBUG MdrScreen.qml` is 0 before committing. The same trick with a
preset `binPct` (four bins at 100) tests file completion in one click.

## Checking whether it's still running

Don't use `pgrep -f 'c mdr'`: the shell running the check has that text in its
own command line and matches itself. Ask Hyprland for the overlay instead:

```bash
hyprctl layers -j | jq -e '[.. | objects | select(.namespace? == "mdr-screensaver")] | length > 0'
```
