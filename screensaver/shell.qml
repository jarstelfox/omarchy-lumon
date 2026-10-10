// Macrodata Refinement screensaver: run with `qs -n -p screensaver` from the repo root. Any key quits.
// MDR_CRT=full|subtle|off sets the CRT tube (default full). Test hook: MDR_FAKE_SIZE=1920x1080
// lays the screen out as if it were that size, shrunk to fit this display.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."   // MdrScreen.qml and its shader and logo live one folder up

ShellRoot {
  Variants {
    model: Quickshell.screens

    PanelWindow {
      required property var modelData
      screen: modelData
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      WlrLayershell.namespace: "mdr-screensaver"
      color: "black"

      MdrScreen {
        anchors.fill: parent
        fake: Quickshell.env("MDR_FAKE_SIZE") || ""
        crt: ({ off: 0, subtle: 0.5, full: 1 })[Quickshell.env("MDR_CRT") || "full"] ?? 1
      }

      Item { anchors.fill: parent; focus: true; Keys.onPressed: Qt.quit() }
    }
  }
}
