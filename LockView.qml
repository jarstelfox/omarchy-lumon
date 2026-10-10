// Lumon terminal login for the Omarchy lock screen. Drop-in replacement for the stock
// LockView.qml: same properties, signals and functions, so Service.qml (PAM password and
// fingerprint) is untouched. Styled to match the MDR screensaver: blue CRT, cyan glow.
//
// Screensaver mode (from the earlier clone): while locked and idle the lock screen is the
// interactive MDR screen, hover and refine included. A key press fades it into the login; the
// first key only wakes it and doesn't go into the password. loginTimeoutSeconds with nothing typed
// fades back. Clicks on the digit grid belong to MDR (refining); a click anywhere else (header,
// bins, margins) shows the login.
import QtQuick
import QtQuick.Effects
import QtQuick.Window

Item {
  id: root

  // --- interface used by Service.qml (keep in sync with the stock LockView) ---
  property string backgroundPath: ""
  property int backgroundVersion: 0
  property bool fingerprintConfigured: false
  property bool authenticatingPassword: false
  property string failureMessage: ""
  property int failedAttempts: 0
  property bool inputEnabled: true
  property bool loadBackground: true
  property string passwordText: ""
  property bool syncingPasswordText: false
  property bool displaysAsleep: false   // set by Service.qml while it has the displays off
  // settings (Settings.js), set by Service.qml from shell.json; the defaults here keep the view
  // usable on its own, e.g. in test/shell.qml
  property int loginTimeoutSeconds: 10
  property string idleScreen: "mdr"
  property real crt: 1
  property int mdrClusters: 3
  property var mdrFiles: []

  signal submitPassword(string password)
  signal passwordTextEdited(string password)
  signal clearFailureRequested()
  signal wakeRequested()

  function forcePasswordFocus() { passwordInput.forceActiveFocus() }
  function clearPassword() { passwordTextEdited("") }
  function syncPasswordText() {
    if (passwordInput.text === passwordText) return
    syncingPasswordText = true
    passwordInput.text = passwordText
    syncingPasswordText = false
  }
  function submit() {
    var submitted = root.passwordText
    root.passwordTextEdited("")
    if (submitted.length > 0) root.submitPassword(submitted)
  }

  onPasswordTextChanged: syncPasswordText()
  onInputEnabledChanged: if (inputEnabled) Qt.callLater(forcePasswordFocus)
  Component.onCompleted: {
    syncPasswordText()
    if (inputEnabled) Qt.callLater(forcePasswordFocus)
  }

  // --- look ---
  readonly property color bg: "#04386c"
  readonly property color ink: "#6fd0fa"
  readonly property color inkHot: "#c8f1ff"
  readonly property string font: "Liberation Sans"
  readonly property real s: Math.max(0.3, Math.min(width / 2048, height / 1280))   // design px -> screen px
  readonly property bool errorState: failureMessage.length > 0
  property real time: 0
  property bool blink: true
  property string now: ""

  // MDR shows only when the setting asks for it and the screen actually loaded; otherwise the
  // login stays up, as in the stock lock
  readonly property bool screensaverMode: root.loadBackground && idleScreen === "mdr" && mdrLoader.status === Loader.Ready
  property bool revealed: false
  // typing or checking keeps the login up; a failure message alone doesn't, so idle clears it and
  // MDR comes back instead of a stale error sitting on screen until the displays blank
  readonly property bool keepRevealed: authenticatingPassword || passwordInput.text.length > 0
  readonly property bool showField: !screensaverMode || revealed || keepRevealed

  function reveal() {
    revealed = true
    idleTimer.restart()
  }
  onKeepRevealedChanged: if (!keepRevealed) idleTimer.restart()
  Timer {
    id: idleTimer
    interval: root.loginTimeoutSeconds * 1000
    onTriggered: {
      if (root.keepRevealed) return
      root.revealed = false
      if (root.errorState) root.clearFailureRequested()
    }
  }

  // While MDR fully covers the login, or the displays are off, nothing here is visible, so its
  // timers, glow layer and CRT pass stop. The login stays in the scene (not visible: false), so
  // the password field keeps focus and the first key still reaches it.
  readonly property bool mdrCovering: mdrLoader.visible && mdrLoader.opacity >= 1
  readonly property bool loginLive: root.visible && !mdrCovering && !displaysAsleep

  Timer {
    interval: 33; running: root.loginLive; repeat: true
    onTriggered: root.time += 0.033
  }
  Timer {
    interval: 530; running: root.loginLive; repeat: true; triggeredOnStart: true
    onTriggered: { root.blink = !root.blink; root.now = Qt.formatDateTime(new Date(), "MM/dd/yyyy  hh:mm:ss") }
  }

  Rectangle {
    id: content
    anchors.fill: parent
    color: root.bg
    layer.enabled: root.loginLive
    layer.effect: MultiEffect {            // phosphor glow, same as the MDR screen
      shadowEnabled: true
      shadowColor: root.ink
      shadowBlur: 0.5
      shadowOpacity: 0.7
      shadowHorizontalOffset: 0
      shadowVerticalOffset: 0
    }

    Text {
      x: 90 * root.s; y: 70 * root.s
      text: "LUMON INDUSTRIES"; color: root.ink
      font.family: root.font; font.bold: true; font.pixelSize: 34 * root.s; font.letterSpacing: 6 * root.s
    }
    Text {
      anchors.right: parent.right; anchors.rightMargin: 90 * root.s; y: 70 * root.s
      text: root.now; color: root.ink
      font.family: root.font; font.bold: true; font.pixelSize: 34 * root.s; font.letterSpacing: 2 * root.s
    }

    Column {
      anchors.centerIn: parent
      anchors.verticalCenterOffset: -40 * root.s
      spacing: 0

      Image {
        anchors.horizontalCenter: parent.horizontalCenter
        source: Qt.resolvedUrl("lumon.svg")
        sourceSize.height: 190 * root.s
      }
      Item { width: 1; height: 56 * root.s }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: "Welcome to Lumon Industries Terminal System " + (root.blink ? "_" : " ")
        color: root.inkHot
        font.family: root.font; font.bold: true; font.pixelSize: 50 * root.s
      }
      Item { width: 1; height: 90 * root.s }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 18 * root.s

        Text {
          text: "Password:"; color: root.ink
          font.family: root.font; font.bold: true; font.pixelSize: 32 * root.s
        }
        Rectangle {
          id: field
          width: 860 * root.s; height: 82 * root.s
          color: "transparent"
          border.color: root.errorState ? root.inkHot : root.ink
          border.width: Math.max(2, 3 * root.s)

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.leftMargin: 26 * root.s; anchors.rightMargin: 26 * root.s
            verticalAlignment: TextInput.AlignVCenter
            clip: true
            activeFocusOnPress: true
            enabled: root.inputEnabled && !root.authenticatingPassword
            readOnly: root.authenticatingPassword
            echoMode: TextInput.Password
            passwordCharacter: "*"
            passwordMaskDelay: 0
            color: root.inkHot
            selectionColor: root.ink
            selectedTextColor: root.bg
            font.family: root.font; font.bold: true; font.pixelSize: 44 * root.s; font.letterSpacing: 6 * root.s
            cursorVisible: false
            onTextChanged: {
              if (!root.syncingPasswordText) root.passwordTextEdited(text)
              if (text.length > 0) root.wakeRequested()
              if (text.length > 0 && root.failureMessage.length > 0) root.clearFailureRequested()
            }
            onAccepted: root.submit()
            Keys.onPressed: function(event) {
              root.wakeRequested()
              // while MDR shows, the first key only wakes it: it doesn't go into the password
              if (root.screensaverMode && !root.showField) {
                root.reveal()
                event.accepted = true
                return
              }
              root.reveal()
              if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                root.passwordTextEdited("")
                event.accepted = true
              }
            }
          }
          // block cursor after the last asterisk
          Rectangle {
            visible: passwordInput.activeFocus && root.blink && !root.authenticatingPassword
            x: passwordInput.x + Math.min(passwordInput.contentWidth, passwordInput.width) + 4 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * root.s; height: 40 * root.s; color: root.inkHot
          }
        }

        // striped LOGIN button, like the reference
        Rectangle {
          id: loginButton
          width: field.width; height: 88 * root.s
          color: login.pressed ? root.inkHot : root.ink
          clip: true
          Column {
            anchors.fill: parent
            Repeater {
              model: Math.ceil(loginButton.height / (6 * root.s))
              Rectangle { width: loginButton.width; height: 6 * root.s; color: index % 2 ? root.bg : "transparent"; opacity: 0.22 }
            }
          }
          Text {
            anchors.centerIn: parent
            text: root.authenticatingPassword ? "VERIFYING" + ".".repeat(1 + Math.floor(root.time * 2) % 3) : "LOGIN"
            color: root.bg; font.family: root.font; font.bold: true; font.pixelSize: 36 * root.s; font.letterSpacing: 4 * root.s
          }
          MouseArea {
            id: login
            anchors.fill: parent
            enabled: root.inputEnabled && !root.authenticatingPassword
            onClicked: { root.wakeRequested(); root.submit(); root.forcePasswordFocus() }
          }
        }

        Text {
          width: field.width
          horizontalAlignment: Text.AlignHCenter
          text: root.errorState ? root.failureMessage.toUpperCase()
              : (root.fingerprintConfigured ? "Or touch the fingerprint sensor" : "")
          color: root.errorState ? root.inkHot : root.ink
          opacity: root.errorState ? (root.blink ? 1 : 0.55) : 0.8
          font.family: root.font; font.bold: true; font.pixelSize: 28 * root.s; font.letterSpacing: 2 * root.s
        }
      }
    }
  }

  // CRT tube, full strength, same shader as the MDR screen
  ShaderEffect {
    anchors.fill: parent
    visible: root.loginLive && root.crt > 0
    property real time: root.time
    property real strength: root.crt
    property vector2d resolution: Qt.vector2d(width, height)
    property var source: ShaderEffectSource {
      sourceItem: content; hideSource: root.crt > 0; live: root.loginLive && root.crt > 0
      textureSize: Qt.size(Math.ceil(root.width * Screen.devicePixelRatio), Math.ceil(root.height * Screen.devicePixelRatio))
    }
    fragmentShader: Qt.resolvedUrl("crt.frag.qsb")
  }

  // clicks anywhere wake the screen and return focus to the field; the button handles its own
  MouseArea {
    anchors.fill: parent
    z: -1
    hoverEnabled: true
    onClicked: { root.wakeRequested(); root.reveal(); root.forcePasswordFocus() }
    onPositionChanged: root.wakeRequested()
  }

  // after a password check the field was disabled; give it focus back so typing works without a click
  onAuthenticatingPasswordChanged: if (!authenticatingPassword) Qt.callLater(forcePasswordFocus)

  // MDR covers the login while idle and fades out when someone presses a key. It loads through a
  // Loader so an error in MdrScreen.qml leaves the plain login instead of breaking this view.
  Loader {
    id: mdrLoader
    anchors.fill: parent
    active: root.idleScreen === "mdr"
    source: Qt.resolvedUrl("MdrScreen.qml")
    opacity: root.screensaverMode && !root.showField ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
  }
  Binding { target: mdrLoader.item; property: "running"; value: mdrLoader.visible && !root.displaysAsleep; when: mdrLoader.item !== null }
  Binding { target: mdrLoader.item; property: "crt"; value: root.crt; when: mdrLoader.item !== null }
  Binding { target: mdrLoader.item; property: "clusterCount"; value: root.mdrClusters; when: mdrLoader.item !== null }
  Binding { target: mdrLoader.item; property: "files"; value: root.mdrFiles; when: mdrLoader.item !== null && root.mdrFiles.length > 0 }
  Connections {
    target: mdrLoader.item
    ignoreUnknownSignals: true
    // any pointer activity keeps the displays awake and the password field focused
    function onActivity() { root.wakeRequested(); root.forcePasswordFocus() }
    function onOutsideClicked() { root.wakeRequested(); root.reveal(); root.forcePasswordFocus() }
  }
}
