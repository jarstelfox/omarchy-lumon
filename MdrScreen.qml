// The Macrodata Refinement screen as a reusable piece: used by the standalone screensaver
// (shell.qml here) and by the lock screen (the omarchy-lumon-lock plugin).
// Modelled on the Cold Harbor file screen (Severance S2E1): blue CRT, sparse bold digits at
// uneven heights, a small patch that swells under the cursor, hidden "scary" clusters that
// jitter when you get close. Click a cluster to refine it into a bin.
//
// The header percent is the average of the five bins, as in the show's Cold Harbor still
// (bins 77/75/59/52/75 -> "67% Complete"). When every bin is full the file is done and the
// next one loads.
//
// Layout is in design pixels: at least 1600x1280, scaled to fit, so wider screens get more
// columns and portrait screens more rows.
import QtQuick
import QtQuick.Effects
import QtQuick.Window

Item {
  id: root
  clip: true

  // colours sampled from the Cold Harbor still, toned down a little from the camera's glow
  readonly property color bg: "#04386c"
  readonly property color ink: "#6fd0fa"
  readonly property color inkHot: "#c8f1ff"
  readonly property string font: "Liberation Sans"

  // design-pixel layout
  property string fake: ""            // test hook: lay out as if the screen were "WxH"
  readonly property real viewW: fake ? Number(fake.split("x")[0]) : width
  readonly property real viewH: fake ? Number(fake.split("x")[1]) : height
  readonly property real k: Math.max(0.01, Math.min(viewW / 1600, viewH / 1280))
  readonly property real designW: viewW / k
  readonly property real designH: viewH / k
  readonly property real fit: fake ? Math.min(width / designW, height / designH) : k

  property real crt: 1               // CRT tube strength: 0 off, 0.5 subtle, 1 full
  property bool running: true        // animation on; hosts turn it off while hidden
  signal activity()                 // pointer moved or clicked; the lock uses it to keep displays awake
  signal outsideClicked()           // click outside the digit grid; the lock uses it to show the login
  // The tube bends the picture outward, so the content under the cursor is not the content at
  // the cursor's raw position. Run the cursor through the same curve as crt.frag.
  function toContent(px, py) {
    const w = designW * fit, h = designH * fit
    let u = px / w * 2 - 1, v = py / h * 2 - 1
    const u2 = u + u * v * v * 0.035 * crt, v2 = v + v * u * u * 0.05 * crt
    return Qt.point((u2 + 1) / 2 * w / fit, (v2 + 1) / 2 * h / fit)
  }

  // Cold Harbor and Siena are on screen in the stills; the rest are other MDR file names
  readonly property var files: ["Cold Harbor", "Siena", "Cocoa", "Dranesville", "Tumwater", "Allentown"]
  property int fileIndex: 0
  property var binPct: randomBins(10, 80)
  readonly property int complete: Math.floor(binPct.reduce((a, b) => a + b, 0) / 5)
  property real flash: 0

  function randomBins(lo, hi) { return [0, 1, 2, 3, 4].map(() => lo + Math.floor(Math.random() * (hi - lo))) }

  property real time: 0
  property real mx: -1000          // cursor in design px, eased (off-screen until it moves)
  property real my: -1000
  property real tx: -1000
  property real ty: -1000

  // ponytail: fixed 30fps tick, drive from frame callbacks if motion ever looks steppy
  Timer {
    interval: 33; running: root.running && root.visible; repeat: true
    onTriggered: {
      root.time += 0.033
      root.mx += (root.tx - root.mx) * 0.3
      root.my += (root.ty - root.my) * 0.3
    }
  }

  // file complete: flash the header three times, then load the next file
  SequentialAnimation {
    id: fileDone
    NumberAnimation { target: root; property: "flash"; from: 0; to: 1; duration: 180 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 320 }
    NumberAnimation { target: root; property: "flash"; to: 1; duration: 180 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 320 }
    NumberAnimation { target: root; property: "flash"; to: 1; duration: 180 }
    NumberAnimation { target: root; property: "flash"; to: 0; duration: 900 }
    ScriptAction { script: grid.nextFile() }
  }

  Rectangle {
    id: screenContent
    width: root.designW; height: root.designH
    scale: root.fit; transformOrigin: Item.TopLeft
    color: root.bg
    layer.enabled: true
    layer.effect: MultiEffect {          // phosphor glow around every line and digit
      shadowEnabled: true
      shadowColor: root.ink
      shadowBlur: 0.5
      shadowOpacity: 0.7
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
    }

    readonly property real m: 70         // margin inside the curved tube

    // header: outlined bar with title, barcode progress, percent, logo overlapping the end
    Item {
      id: header
      x: screenContent.m; y: 56
      width: parent.width - 2 * screenContent.m; height: 66
      Rectangle {
        id: headerBox
        anchors.fill: parent; anchors.rightMargin: logo.width * 0.45
        color: Qt.rgba(root.ink.r, root.ink.g, root.ink.b, 0.85 * root.flash)
        border.color: root.ink; border.width: 3
        Text {
          id: title
          text: root.files[root.fileIndex % root.files.length]
          color: root.inkHot; font.family: root.font; font.bold: true; font.pixelSize: 34
          anchors.verticalCenter: parent.verticalCenter; x: 18
        }
        Text {
          id: pct
          text: root.complete + "% Complete"; color: root.inkHot; font.family: root.font; font.bold: true; font.pixelSize: 34
          style: Text.Outline; styleColor: root.bg
          anchors.verticalCenter: parent.verticalCenter; anchors.right: parent.right; anchors.rightMargin: logo.width * 0.55 + 14
        }
        Row {                      // barcode-style progress fill between title and percent
          x: title.x + title.width + 14
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5
          readonly property real span: pct.x - 14 - x
          Repeater {
            model: Math.max(0, Math.floor(parent.span / 11 * root.complete / 100))
            Rectangle { width: 6; height: 46; color: root.ink }
          }
        }
      }
      Image {
        id: logo
        source: Qt.resolvedUrl("lumon.svg")
        sourceSize.height: 88
        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
      }
    }
    // double rule under the header
    Rectangle { x: screenContent.m - 20; y: header.y + header.height + 22; width: parent.width - 2 * x; height: 6; color: root.ink }
    Rectangle { x: screenContent.m - 20; y: header.y + header.height + 36; width: parent.width - 2 * x; height: 2; color: root.ink }

    // digit grid, clipped between the rules so partial rows peek in at both ends
    Item {
      id: grid
      x: screenContent.m; y: header.y + header.height + 40
      width: parent.width - 2 * screenContent.m
      height: bins.y - 24 - y
      clip: true
      readonly property real cellW: 82
      readonly property real cellH: 64
      readonly property int cols: Math.floor(width / cellW)
      readonly property int rows: Math.ceil(height / cellH) + 1
      readonly property real ox: (width - cols * cellW) / 2
      readonly property real oy: -cellH * 0.35
      // rows whose digits sit fully inside the clip; clusters live only here
      readonly property int firstRow: Math.ceil((cellH * 0.35 - oy) / cellH - 0.5)
      readonly property int lastRow: Math.floor((height - cellH * 0.35 - oy) / cellH - 0.5)

      function onScreen(d) { return d.baseY > cellH * 0.35 && d.baseY < height - cellH * 0.35 }
      function newCluster() {
        const rad = 1.2 + Math.random() * 1.3
        const span = (lo, hi) => hi - lo > 2 * rad ? lo + rad + Math.random() * (hi - lo - 2 * rad) : (lo + hi) / 2
        return { c: span(0, cols - 1), r: span(firstRow, lastRow), rad: rad }
      }
      // three hidden clusters of "scary" numbers, in cell coordinates
      property var clusters: [newCluster(), newCluster(), newCluster()]
      onColsChanged: clusters = [newCluster(), newCluster(), newCluster()]
      onLastRowChanged: clusters = [newCluster(), newCluster(), newCluster()]
      property bool busy: false
      property var picked: []          // digits in flight
      property int pickedCluster: -1
      property int pickedBin: -1

      // Click: if it lands on a scary cluster, send its visible digits into a bin with room.
      function refine(px, py) {
        if (busy) return
        const c = (px - x - ox) / cellW - 0.5, r = (py - y - oy) / cellH - 0.5
        const k = clusters.findIndex(q => Math.hypot(c - q.c, r - q.r) < q.rad + 0.6)
        if (k < 0) return
        const open = [0, 1, 2, 3, 4].filter(i => root.binPct[i] < 100)
        if (!open.length) return
        const q = clusters[k], sel = []
        for (let i = 0; i < digits.count; i++) {
          const d = digits.itemAt(i)
          if (d && !d.hidden && onScreen(d) && Math.hypot(d.col - q.c, d.row - q.r) < q.rad) sel.push(d)
        }
        if (!sel.length) return
        const b = open[Math.floor(Math.random() * open.length)]
        const bin = binRepeater.itemAt(b)
        const dest = bin.mapToItem(screenContent, bin.width / 2, 8)
        bin.lid = 1
        sel.forEach((d, j) => {
          const from = d.mapToItem(screenContent, d.width / 2, d.height / 2)
          flyer.createObject(screenContent, { text: d.text, cx: from.x, cy: from.y, tx: dest.x, ty: dest.y, delay: 120 + j * 70 })
          d.hidden = true
        })
        busy = true; picked = sel; pickedCluster = k; pickedBin = b
        finishTimer.interval = 120 + sel.length * 70 + 900
        finishTimer.start()
      }
      Timer {
        id: finishTimer
        onTriggered: {
          const b = grid.pickedBin, next = root.binPct.slice()
          const bin = binRepeater.itemAt(b)
          if (bin) bin.lid = 0
          next[b] = Math.min(100, next[b] + Math.max(3, grid.picked.length))
          root.binPct = next
          // a monitor change can rebuild the grid mid-flight; skip digits that are gone
          grid.picked.forEach(d => { if (d) { d.digit = Math.floor(Math.random() * 10); d.hidden = false } })
          const cl = grid.clusters.slice(); cl[grid.pickedCluster] = grid.newCluster(); grid.clusters = cl
          if (root.complete >= 100) fileDone.start()      // keeps busy set until nextFile()
          else grid.busy = false
        }
      }
      function nextFile() {
        root.fileIndex++
        root.binPct = root.randomBins(0, 25)
        for (let i = 0; i < digits.count; i++) {
          const d = digits.itemAt(i)
          if (d) d.digit = Math.floor(Math.random() * 10)
        }
        clusters = [newCluster(), newCluster(), newCluster()]
        busy = false
      }

      Repeater {
        id: digits
        model: Math.max(0, grid.cols * grid.rows)
        Text {
          required property int index
          property int digit: Math.floor(Math.random() * 10)
          property bool hidden: false
          opacity: hidden ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 700 } }
          readonly property int col: index % grid.cols
          readonly property int row: Math.floor(index / grid.cols)
          // the show's digits sit at uneven heights and sizes
          readonly property real jx: (Math.random() - 0.5) * 10
          readonly property real jy: (Math.random() - 0.5) * 22
          readonly property real size: 0.8 + Math.random() * 0.35
          readonly property real phase: Math.random() * 6.283
          readonly property real baseX: grid.ox + (col + 0.5) * grid.cellW + jx
          readonly property real baseY: grid.oy + (row + 0.5) * grid.cellH + jy
          readonly property bool scary: grid.clusters.some(k => Math.hypot(col - k.c, row - k.r) < k.rad)
          readonly property real dx: baseX + grid.x - root.mx
          readonly property real dy: baseY + grid.y - root.my
          readonly property real near: Math.exp(-(dx * dx + dy * dy) / (2 * 85 * 85))   // tight patch under the cursor
          readonly property real agitation: scary ? Math.min(1, near * 3) : 0

          text: digit
          color: near > 0.3 ? root.inkHot : root.ink
          font.family: root.font
          font.bold: true
          font.pixelSize: 26
          scale: size * (1 + 1.6 * near)
          z: near
          x: baseX - width / 2 + 2 * Math.sin(root.time * 0.9 + phase * 2) + agitation * 7 * Math.sin(root.time * 37 + phase * 3)
          y: baseY - height / 2 + 4 * Math.sin(root.time * 1.2 + phase) + agitation * 7 * Math.cos(root.time * 41 + phase)
        }
      }
    }

    // rules above and below the bins
    Rectangle { x: screenContent.m - 20; y: bins.y - 22; width: parent.width - 2 * x; height: 5; color: root.ink }
    Rectangle { x: screenContent.m - 20; y: bins.y + bins.height + 16; width: parent.width - 2 * x; height: 5; color: root.ink }

    // bins 01-05
    Row {
      id: bins
      readonly property real binW: (screenContent.width - 2 * screenContent.m - 4 * spacing) / 5
      x: screenContent.m
      y: parent.height - 230
      spacing: 44
      Repeater {
        id: binRepeater
        model: 5
        Column {
          required property int index
          readonly property int pct: root.binPct[index]
          property real lid: 0             // 0 closed, 1 open
          Behavior on lid { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
          spacing: 12
          Item {
            width: bins.binW; height: 58
            // sides and bottom; the top is the two lid flaps
            Rectangle { width: 3; height: parent.height; color: root.ink }
            Rectangle { x: parent.width - 3; width: 3; height: parent.height; color: root.ink }
            Rectangle { y: parent.height - 3; width: parent.width; height: 3; color: root.ink }
            Rectangle {
              width: parent.width / 2; height: 3; color: root.ink
              transform: Rotation { origin.x: 0; origin.y: 1.5; angle: -125 * lid }
            }
            Rectangle {
              id: rightFlap
              x: parent.width / 2; width: parent.width / 2; height: 3; color: root.ink
              transform: Rotation { origin.x: rightFlap.width; origin.y: 1.5; angle: 125 * lid }
            }
            Text { anchors.centerIn: parent; text: "0" + (index + 1); color: root.inkHot; font.family: root.font; font.bold: true; font.pixelSize: 28 }
          }
          Rectangle {
            width: bins.binW; height: 36; color: "transparent"; border.color: root.ink; border.width: 3
            Rectangle { x: 0; y: 0; height: parent.height; width: parent.width * pct / 100; color: root.ink
                        Behavior on width { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } } }
            Text { anchors.left: parent.left; anchors.leftMargin: pct < 20 ? parent.width * pct / 100 + 10 : 12; anchors.verticalCenter: parent.verticalCenter
                   text: pct + "%"; color: pct < 20 ? root.ink : root.bg; font.family: root.font; font.bold: true; font.pixelSize: 22 }
          }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      y: bins.y + bins.height + 32
      color: root.inkHot; font.family: root.font; font.bold: true; font.pixelSize: 28; font.letterSpacing: 2
      text: "0x" + Math.floor(Math.random() * 0xffffff).toString(16).toUpperCase().padStart(6, "0")
          + " : 0x" + Math.floor(Math.random() * 0xffffff).toString(16).toUpperCase().padStart(6, "0")
    }
  }

  // a refined digit flying from the grid into a bin
  Component {
    id: flyer
    Text {
      id: f
      property real cx; property real cy; property real tx; property real ty; property int delay
      x: cx - width / 2; y: cy - height / 2
      color: root.inkHot; font.family: root.font; font.bold: true; font.pixelSize: 26; scale: 1.8
      SequentialAnimation {
        running: true
        PauseAnimation { duration: f.delay }
        ParallelAnimation {
          NumberAnimation { target: f; property: "x"; to: f.tx - f.width / 2; duration: 650; easing.type: Easing.InOutCubic }
          NumberAnimation { target: f; property: "y"; to: f.ty - f.height / 2; duration: 650; easing.type: Easing.InCubic }
          NumberAnimation { target: f; property: "scale"; to: 0.5; duration: 650 }
        }
        NumberAnimation { target: f; property: "opacity"; to: 0; duration: 120 }
        ScriptAction { script: f.destroy() }
      }
    }
  }

  // the CRT tube over the drawn area
  ShaderEffect {
    visible: root.crt > 0
    width: root.designW * root.fit; height: root.designH * root.fit
    property real time: root.time
    property real strength: root.crt
    property vector2d resolution: Qt.vector2d(width, height)
    property var source: ShaderEffectSource {
      sourceItem: screenContent; hideSource: root.crt > 0; live: root.crt > 0
      textureSize: Qt.size(Math.ceil(root.designW * root.fit * Screen.devicePixelRatio), Math.ceil(root.designH * root.fit * Screen.devicePixelRatio))
    }
    fragmentShader: Qt.resolvedUrl("crt.frag.qsb")
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onPositionChanged: mouse => { const p = root.toContent(mouse.x, mouse.y); root.tx = p.x; root.ty = p.y; root.activity() }
    onClicked: mouse => {
      const p = root.toContent(mouse.x, mouse.y)
      const inGrid = p.x >= grid.x && p.x <= grid.x + grid.width && p.y >= grid.y && p.y <= grid.y + grid.height
      if (inGrid) grid.refine(p.x, p.y)
      else root.outsideClicked()
      root.activity()
    }
  }
}
