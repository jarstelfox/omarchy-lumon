// Test harness for LockView.qml: `qs -n -p test` from the repo root. Fake auth, never locks anything.
// Password "lumon" succeeds (quits); anything else fails. Quits by itself after 60s.
import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."   // LockView.qml and the MDR files live one folder up

ShellRoot {
  PanelWindow {
    id: w
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: "lumon-lock-test"
    color: "black"

    property string entered: ""
    property int fails: 0

    LockView {
      id: view
      anchors.fill: parent
      fingerprintConfigured: Quickshell.env("LOCKTEST_FP") === "1"
      passwordText: w.entered
      onPasswordTextEdited: p => w.entered = p
      onSubmitPassword: p => { console.log("LOCKTEST submit " + p.length + " chars"); view.authenticatingPassword = true; check.pw = p; check.start() }
      onClearFailureRequested: view.failureMessage = ""
    }
    Timer {
      id: check
      property string pw
      interval: 900
      onTriggered: {
        view.authenticatingPassword = false
        if (pw === "lumon") Qt.quit()
        else { w.fails++; view.failedAttempts = w.fails; view.failureMessage = "Authentication failed (" + w.fails + ")" }
      }
    }
    Timer { interval: 60000; running: true; onTriggered: Qt.quit() }
  }
}
