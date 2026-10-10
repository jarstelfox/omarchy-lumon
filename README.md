# MDR screensaver

The Macrodata Refinement screen from *Severance*, as an interactive
[Quickshell](https://quickshell.org) screensaver for Wayland desktops (built
on [Omarchy](https://omarchy.org) / Hyprland).

![The MDR screen, with digits swelling under the pointer](docs/preview.png)

Move the pointer and the digits under it swell, like the refiners' terminals
in the show. Somewhere in the grid hide three clusters of "scary" numbers that
jitter when you get close. Click one and its digits fly into a bin, the bin's
lid flaps open, and the file's progress goes up. Fill all five bins and the
next file loads.

## Install

```bash
git clone https://github.com/jarstelfox/mdr-screensaver ~/.config/quickshell/mdr
qs -n -c mdr
```

Any key quits. The pointer only hovers and clicks.

Needs Quickshell 0.3 or newer and the Liberation Sans font. The CRT shader
ships compiled (`crt.frag.qsb`); rebuilding it after an edit needs Qt's
shader tools (`qt6-shadertools`):

```bash
/usr/lib/qt6/bin/qsb --qt6 -o crt.frag.qsb crt.frag
```

## Options

| Variable | Values | Default |
|---|---|---|
| `MDR_CRT` | `full`, `subtle`, `off`: the curved CRT tube, bloom and scanlines | `full` |
| `MDR_FAKE_SIZE` | `WxH`, e.g. `1920x1080`: lay the screen out as if it were that size (for testing other monitors) | your screen |

```bash
MDR_CRT=subtle qs -n -c mdr
```

## How it plays

- The header's "% Complete" is the average of the five bins, rounded down.
  The show's own Cold Harbor screen has bins at 77, 75, 59, 52 and 75%, and
  its header reads 67%.
- A full bin takes no more digits. When every bin is full the header flashes
  and the next file loads, with fresh digits and empty-ish bins.
- Each monitor runs its own file.

## As a lock screen

[omarchy-lumon-lock](https://github.com/jarstelfox/omarchy-lumon-lock) shows
this screen while an Omarchy session is locked and idle, with a Lumon
terminal login behind it. It carries its own copies of `MdrScreen.qml`,
`crt.frag.qsb` and `lumon.svg`; after changing them here, run that repo's
`scripts/sync-mdr.sh` to copy them over.

## Not affiliated

A fan project. *Severance*, Lumon and the Lumon logo belong to their owners;
this repo isn't affiliated with or endorsed by them.
