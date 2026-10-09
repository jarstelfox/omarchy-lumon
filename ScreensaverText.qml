import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// The screensaver's text, drawn on the lock screen with a terminal-style effect in the spirit of the
// screensaver's own ttfx. The file is read again before every pass, so a symlink that rotates between files
// (~/.config/omarchy/branding/screensaver.txt) shows its next file on the next pass. Each pass: the text
// resolves out of random glyphs, holds, dissolves, and a short pause later the next one starts. Frames are
// only drawn while it resolves or dissolves; the hold is a still image.
Item {
  id: saver

  property string path: Quickshell.env("HOME") + "/.config/omarchy/branding/screensaver.txt"
  property bool running: true
  readonly property bool hasText: rows.length > 0

  // seconds per phase
  readonly property real inSeconds: 2.4
  readonly property real holdSeconds: 9
  readonly property real outSeconds: 1.6
  readonly property real gapSeconds: 0.6
  readonly property string glyphs: "░▒▓█▀▄▌▐#@%&*+=-:."

  property var rows: []          // the text as rows of characters
  property var thresholds: []    // per character, when in the pass it settles (0..1)
  property int columns: 0
  property string phase: "gap"   // in, hold, out, gap
  property real phaseStart: 0
  property string shown: ""

  function load() {
    file.reload()
    var text = file.text() || ""
    var lines = text.replace(/\s+$/, "").split("\n")
    var out = [], widest = 0
    for (var i = 0; i < lines.length; i++) {
      var chars = Array.from(lines[i].replace(/\r$/, ""))
      out.push(chars)
      widest = Math.max(widest, chars.length)
    }
    rows = text.trim().length ? out : []
    columns = widest
    pickEffect()
  }

  // Three ways for the characters to settle, picked at random each pass: scattered, a sweep from the left,
  // or row by row from the top.
  function pickEffect() {
    var kind = Math.floor(Math.random() * 3), t = []
    for (var r = 0; r < rows.length; r++) {
      var row = []
      for (var c = 0; c < rows[r].length; c++) {
        var jitter = Math.random() * 0.15
        if (kind === 0) row.push(Math.random() * 0.85)
        else if (kind === 1) row.push(columns > 1 ? (c / (columns - 1)) * 0.8 + jitter : jitter)
        else row.push(rows.length > 1 ? (r / (rows.length - 1)) * 0.8 + jitter : jitter)
      }
      t.push(row)
    }
    thresholds = t
  }

  function randomGlyph() {
    return glyphs.charAt(Math.floor(Math.random() * glyphs.length))
  }

  // One frame. progress runs 0..1 through the phase; settled characters show, characters just ahead of the
  // front flicker through random glyphs, the rest are blank.
  function render(progress, dissolving) {
    var lines = []
    for (var r = 0; r < rows.length; r++) {
      var line = ""
      for (var c = 0; c < rows[r].length; c++) {
        var ch = rows[r][c]
        if (ch === " ") { line += " "; continue }
        var at = thresholds[r][c]
        var p = dissolving ? 1 - progress : progress
        if (p >= at) line += ch
        else if (p >= at - 0.12) line += randomGlyph()
        else line += " "
      }
      lines.push(line)
    }
    shown = lines.join("\n")
  }

  function now() { return Date.now() / 1000 }

  function startPhase(name) {
    phase = name
    phaseStart = now()
    if (name === "in") load()
    frameTimer.running = saver.running && (name === "in" || name === "out")
    phaseTimer.interval = 1000 * (name === "in" ? inSeconds : name === "hold" ? holdSeconds : name === "out" ? outSeconds : gapSeconds)
    phaseTimer.restart()
    if (name === "hold") render(1, false)
    if (name === "gap") shown = ""
  }

  onRunningChanged: {
    if (running) startPhase("in")
    else { phaseTimer.stop(); frameTimer.stop() }
  }
  Component.onCompleted: if (running) startPhase("in")

  FileView {
    id: file
    path: saver.path
    blockLoading: true
    printErrors: false
  }

  Timer {
    id: phaseTimer
    repeat: false
    onTriggered: saver.startPhase(saver.phase === "in" ? "hold" : saver.phase === "hold" ? "out" : saver.phase === "out" ? "gap" : "in")
  }

  Timer {
    id: frameTimer
    interval: 40   // 25 frames a second while the text is moving
    repeat: true
    onTriggered: {
      var seconds = saver.phase === "in" ? saver.inSeconds : saver.outSeconds
      saver.render(Math.min(1, (saver.now() - saver.phaseStart) / seconds), saver.phase === "out")
    }
  }

  // sized so the widest row fills about 80% of the screen, and all rows fit in 60% of its height
  TextMetrics {
    id: metrics
    font.family: Style.font.family
    font.pixelSize: 100
    text: "█"
  }
  readonly property int fontPixelSize: {
    if (!columns || !rows.length || metrics.advanceWidth <= 0) return 16
    var byWidth = width * 0.8 * 100 / (columns * metrics.advanceWidth)
    var byHeight = height * 0.6 / (rows.length * 1.2)
    return Math.max(6, Math.floor(Math.min(byWidth, byHeight, 64)))
  }

  Text {
    anchors.centerIn: parent
    textFormat: Text.PlainText
    text: saver.shown
    color: Color.lock.text
    font.family: Style.font.family
    font.pixelSize: saver.fontPixelSize
    lineHeight: 1.0
    horizontalAlignment: Text.AlignLeft
  }
}
