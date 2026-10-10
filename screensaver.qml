// Macrodata Refinement screensaver: run with `qs -n -p screensaver.qml` from the repo root. Any key quits.
// Reads the same settings as the lock (the lumon.lock entry in ~/.config/omarchy/shell.json, see
// Settings.js). MDR_CRT=full|subtle|off overrides the CRT setting for one run. Test hook:
// MDR_FAKE_SIZE=1920x1080 lays the screen out as if it were that size, shrunk to fit this display.
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Settings.js" as Settings

ShellRoot {
  id: shellRoot
  property var settings: Settings.resolve(null)

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: shellRoot.settings = Settings.fromShellJson(text(), "lumon.lock")
  }

  readonly property string crtOverride: Quickshell.env("MDR_CRT") || ""

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
        crt: Settings.resolve({ crt: shellRoot.crtOverride || shellRoot.settings.crt }).crtStrength
        clusterCount: shellRoot.settings.clusters
        files: shellRoot.settings.files
      }

      Item { anchors.fill: parent; focus: true; Keys.onPressed: Qt.quit() }
    }
  }
}
