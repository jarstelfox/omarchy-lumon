import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "FingerprintModel.js" as FingerprintModel
import "Settings.js" as Settings

Item {
  id: root

  property var shell: null
  property var manifest: null      // injected by the shell; gives this plugin's id

  // Local change: settings from this plugin's entry in shell.json (see Settings.js). Re-read when the
  // file changes; until it loads, and whenever it can't be read or parsed, the defaults apply.
  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "lumon.lock"
  property var settings: Settings.resolve(null)

  FileView {
    id: shellConfigFile
    path: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.settings = Settings.fromShellJson(text(), root.pluginId)
    onLoadFailed: root.settings = Settings.resolve(null)
  }
  property string omarchyPath: ""

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string currentBackgroundLink: stateHome + "/omarchy/current/background"

  property bool lockRequested: false
  property bool pendingSessionLock: false
  property bool authenticatingPassword: false
  property bool fingerprintAuthenticating: false
  property bool passwordPamConfigured: false
  property bool fingerprintConfigured: false
  property int fingerprintUnreachedStreak: 0
  property bool fingerprintAttemptReachedDevice: false
  property bool fingerprintAttemptFastError: false
  property double fingerprintAttemptPromptedAtMs: 0
  property double fingerprintLastNudgeMs: 0
  property double fingerprintLastSettleMs: 0
  property double fingerprintResumedAtMs: 0
  property int fingerprintProbeStreak: 0
  // While the lock has the displays off no new attempt starts, so the reader
  // isn't held awake all night; any wake starts it again.
  property bool fingerprintPaused: false
  // The sleep watch is stopped while paused, so a sleep seen after the
  // pre-suspend lock request is marked here instead.
  property bool fingerprintSleptWhilePaused: false
  // When the armed retry is due, so time spent blank counts toward it.
  property double fingerprintRetryDueMs: 0
  // The backoff the armed retry was set to; a wake shortens the timer to the
  // remaining wait, so the input guard reads the tier from here instead.
  property int fingerprintRetryBackoffMs: 0
  // Outputs the lock last saw, so only a display arriving counts as a wake.
  property int knownScreenCount: 0
  property bool previewVisible: false
  property string enteredPassword: ""
  property string pendingPassword: ""
  property string failureMessage: ""
  property int failedAttempts: 0
  property string backgroundPath: ""
  property string videoPosterPath: ""
  property int backgroundVersion: 0
  // The wallpaper file's mtime and size. The lock caches its wallpaper by
  // version, so a file overwritten in place must bump the version too.
  property string backgroundSignature: ""
  property string lastEvent: "init"
  property string lastEventAt: ""
  readonly property bool videoBackground: Util.isVideoPath(backgroundPath)
  property bool strandedLock: false
  property bool strandedLockResolved: false

  readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure

  // Decisions read the lock state afresh. A property binding that missed a change
  // notification once reported locked after an unlock, and a lock request before
  // suspend then took that for done and never locked the session.
  function currentlyLocked() {
    return lockRequested || sessionLock.locked || sessionLock.secure
  }
  readonly property bool authenticating: authenticatingPassword || fingerprintAuthenticating
  // A prompt clears the unavailable notice before the attempt finishes.
  readonly property bool fingerprintUnavailable: FingerprintModel.isUnavailable(fingerprintProbeStreak) || (fingerprintConfigured && (!fingerprintAttemptReachedDevice || fingerprintAttemptFastError) && FingerprintModel.isUnavailable(fingerprintUnreachedStreak))

  function realScreenCount() {
    var screens = Quickshell.screens || []
    var count = 0

    for (var i = 0; i < screens.length; i++) {
      var screen = screens[i]
      if (screen && screen.name && screen.width > 0 && screen.height > 0) count += 1
    }

    return count
  }

  function hasRealScreen() {
    return realScreenCount() > 0
  }

  function queueSessionLock() {
    pendingSessionLock = true
    if (!sessionLockStabilizeTimer.running) logEvent("lock-pending: screen-stabilizing")
    sessionLockStabilizeTimer.restart()
    if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
  }

  function requestSessionLock() {
    if (!lockRequested || sessionLock.locked || sessionLock.secure) return
    if (sessionLockStabilizeTimer.running) return

    if (!hasRealScreen()) {
      if (!pendingSessionLock || lastEvent !== "lock-pending: no-real-screen") logEvent("lock-pending: no-real-screen")
      pendingSessionLock = true
      if (!pendingSessionLockTimer.running) pendingSessionLockTimer.start()
      return
    }

    pendingSessionLock = false
    pendingSessionLockTimer.stop()
    sessionLock.locked = true
  }

  // ext-session-lock outlives its client, and a restart carries no lock over, so
  // a session locked this early may be an orphan behind Hyprland's failsafe. It
  // may also be another shell's live lock, which Hyprland would let this one
  // take over and then strand on exit, so the helper answers undetermined while
  // another locker runs. Outputs are often still absent here, so ask until the
  // answer means something.
  function checkStrandedLock() {
    if (strandedLockResolved || strandedLockCheckProc.running) return

    // A lock this shell took is nobody's orphan.
    if (currentlyLocked()) {
      strandedLockResolved = true
      return
    }

    strandedLockCheckProc.running = true
  }

  function recoverStrandedLock() {
    if (!strandedLock || currentlyLocked() || !passwordPamConfigured) return

    strandedLock = false
    logEvent("lock-stranded: recovering")
    beginLock()
  }

  function refreshBackground() {
    if (!readlinkProc.running) readlinkProc.running = true
  }

  function refreshPoster() {
    if (!root.videoBackground) {
      root.videoPosterPath = ""
      return
    }
    if (posterProc.running) return
    posterProc.sourcePath = root.backgroundPath
    posterProc.running = true
  }

  function refreshFingerprintStatus() {
    if (!fingerprintCheckProc.running) fingerprintCheckProc.running = true
  }

  // Only definitive enrollment results may disable authentication.
  function applyFingerprintProbe(text) {
    var status = FingerprintModel.classifyProbe(text)
    if (status === "unknown") {
      if (fingerprintConfigured) return
      fingerprintProbeStreak += 1
      if (lockRequested) {
        fingerprintRecheckTimer.interval = FingerprintModel.retryDelayMs(fingerprintProbeStreak)
        fingerprintRecheckTimer.restart()
      }
      return
    }
    fingerprintProbeStreak = 0
    fingerprintRecheckTimer.stop()
    fingerprintConfigured = status === "yes"
    if (lockRequested && fingerprintConfigured) {
      // A pending retry already owns the next attempt.
      if (!fingerprintRetryTimer.running) startFingerprint()
    } else if (!fingerprintConfigured) {
      // abort() delivers no completion signal, so close the attempt here
      // too; settle returns before arming a retry while unconfigured.
      if (fingerprintPam.active) fingerprintPam.abort()
      settleFingerprintAttempt()
      fingerprintRetryTimer.stop()
    }
  }

  function logEvent(event) {
    lastEvent = event
    lastEventAt = new Date().toISOString()
    console.log("omarchy lock " + lastEventAt + " " + event)
  }

  function resetAuthenticationState() {
    enteredPassword = ""
    pendingPassword = ""
    failureMessage = ""
    failedAttempts = 0
    authenticatingPassword = false
    fingerprintAuthenticating = false
    fingerprintUnreachedStreak = 0
    fingerprintAttemptFastError = false
    fingerprintAttemptPromptedAtMs = 0
    fingerprintLastNudgeMs = 0
    fingerprintLastSettleMs = 0
    fingerprintResumedAtMs = 0
    fingerprintProbeStreak = 0
    fingerprintPaused = false
    fingerprintSleptWhilePaused = false
    fingerprintRecheckTimer.stop()
    fingerprintRetryTimer.stop()
    fingerprintReachTimer.stop()
    fingerprintResumeTimer.stop()
    if (passwordPam.active) passwordPam.abort()
    if (fingerprintPam.active) fingerprintPam.abort()
  }

  function beginLock() {
    if (!passwordPamConfigured) {
      logEvent("lock-denied: missing-pam")
      return false
    }

    resetAuthenticationState()
    lockRequested = true
    hidePointerWhileLocked()
    armBlankTimer()
    logEvent("lock-requested")
    queueSessionLock()

    Qt.callLater(function() {
      root.refreshBackground()
      root.refreshFingerprintStatus()
    })

    return true
  }

  function finishUnlock() {
    if (!root.currentlyLocked()) return

    lockRequested = false
    pendingSessionLock = false
    sessionLockStabilizeTimer.stop()
    pendingSessionLockTimer.stop()
    resetAuthenticationState()
    idleBlankTimer.stop()
    sessionLock.locked = false
    restorePointer()
    logEvent("unlocked")
    runWake()
  }

  // Local change: true while runBlank has the displays off, so the lock view can pause its animation
  // instead of rendering to dark screens until the next wake.
  property bool displaysAsleep: false

  function armBlankTimer(delayMs) {
    idleBlankTimer.interval = delayMs || idleBlankTimer.idleMs
    idleBlankTimer.armedAt = Date.now()
    idleBlankTimer.restart()
  }

  // Local change: the lock screen can't hide the pointer itself (no blank shape to ask Hyprland for), so while
  // locked Hyprland hides it after hidePointerSeconds still seconds (cursor:inactive_timeout); unlocking puts
  // the user's value back. hidePointerSeconds 0 leaves the pointer alone. A Hyprland reload while locked would
  // also put the user's value back, which only means the pointer shows.
  property string savedPointerTimeout: ""
  property bool pointerRestorePending: false

  function hidePointerWhileLocked() {
    if (settings.hidePointerSeconds <= 0 || pointerSaveProc.running) return
    pointerSaveProc.running = true
  }

  function restorePointer() {
    var value = Number(savedPointerTimeout)
    if (savedPointerTimeout === "" || !isFinite(value)) return
    // a "hide" command may still be running; restore once it exits, or the restore could be dropped
    if (pointerSetProc.running) { pointerRestorePending = true; return }
    savedPointerTimeout = ""
    pointerRestorePending = false
    pointerSetProc.command = ["hyprctl", "eval", "hl.config({ cursor = { inactive_timeout = " + value + " } })"]
    pointerSetProc.running = true
  }

  Process {
    id: pointerSaveProc
    command: ["hyprctl", "getoption", "cursor:inactive_timeout", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        var saved = ""
        try { saved = String(JSON.parse(text).float) } catch (e) { saved = "" }
        var savedValue = Number(saved)
        // can't read the user's value: don't hide, or unlocking would have nothing to put back
        if (saved === "" || !isFinite(savedValue)) return
        // only the first lock saves; a second lock request keeps the value from before the first
        if (root.savedPointerTimeout === "") root.savedPointerTimeout = saved
        if (!root.lockRequested) return root.restorePointer()   // unlocked before this finished
        pointerSetProc.command = ["hyprctl", "eval", "hl.config({ cursor = { inactive_timeout = " + root.settings.hidePointerSeconds + " } })"]
        pointerSetProc.running = true
      }
    }
  }

  Process {
    id: pointerSetProc
    onExited: if (root.pointerRestorePending) root.restorePointer()
  }

  function runWake() {
    displaysAsleep = false
    if (!wakeProcess.running) wakeProcess.running = true
    if (lockRequested) armBlankTimer()
    resumeFingerprint()
    nudgeFingerprint()
  }

  // An attempt already running is left to finish under its own timeouts, so
  // a slow claim still completes; only the next one waits for a wake.
  function pauseFingerprint() {
    if (fingerprintPaused) return
    fingerprintPaused = true
    fingerprintRetryTimer.stop()
  }

  // The retry keeps whatever backoff was armed, counting the time spent blank,
  // so a failing reader still gets its idle window; after a sleep it recovers
  // at once, as the sleep watch does.
  function resumeFingerprint() {
    if (!fingerprintPaused) return
    fingerprintPaused = false
    if (fingerprintSleptWhilePaused) {
      fingerprintSleptWhilePaused = false
      noteFingerprintResumed()
      fingerprintRetryBackoffMs = FingerprintModel.MATCH_RETRY_MS
      fingerprintRetryTimer.interval = FingerprintModel.MATCH_RETRY_MS
    } else {
      fingerprintRetryTimer.interval = Math.max(FingerprintModel.MATCH_RETRY_MS, fingerprintRetryDueMs - Date.now())
    }
    if (lockRequested && fingerprintConfigured && !fingerprintAuthenticating) fingerprintRetryTimer.restart()
  }

  // A resume brings no input to wake the lock, so after a lock request the
  // panel and the reader come back once a sleep is seen; the blank countdown
  // then takes both away again if nothing else happens. The idle service
  // repeats the same request without sleeping, so the sleep has to be seen.
  function noteSleepRequested() {
    if (!lockRequested || !fingerprintPaused) return
    // logind holds a suspend for its inhibitor delay, at most 15 seconds here.
    fingerprintResumeTimer.ticksLeft = 20
    fingerprintResumeTimer.lastTickMs = Date.now()
    fingerprintResumeTimer.restart()
  }

  // User activity advances retries without recreating a busy retry loop.
  function nudgeFingerprint() {
    if (!lockRequested) return
    if (!fingerprintConfigured && fingerprintRecheckTimer.running) {
      var now = Date.now()
      if (FingerprintModel.shouldNudge(now, fingerprintLastNudgeMs, now - FingerprintModel.IDLE_CLEAR_MS, fingerprintRecheckTimer.interval)) {
        fingerprintLastNudgeMs = now
        fingerprintRecheckTimer.interval = FingerprintModel.MATCH_RETRY_MS
        fingerprintRecheckTimer.restart()
      }
      return
    }
    if (!fingerprintConfigured) return
    if (fingerprintPam.active || fingerprintAuthenticating) return
    if (!fingerprintRetryTimer.running) return
    var now = Date.now()
    if (!FingerprintModel.shouldNudge(now, fingerprintLastNudgeMs, fingerprintLastSettleMs, fingerprintRetryBackoffMs)) return
    fingerprintLastNudgeMs = now
    armFingerprintRetry(FingerprintModel.MATCH_RETRY_MS)
  }


  function armFingerprintRetry(delayMs) {
    fingerprintRetryTimer.interval = delayMs
    fingerprintRetryBackoffMs = delayMs
    fingerprintRetryDueMs = Date.now() + delayMs
    if (!fingerprintPaused) fingerprintRetryTimer.restart()
  }

  // Reset pre-sleep failures while the resume hook restarts fprintd.
  function noteFingerprintResumed() {
    var now = Date.now()
    if (FingerprintModel.inResumeGrace(now, fingerprintResumedAtMs)) return
    logEvent("fingerprint-resume: streak=" + fingerprintUnreachedStreak)
    fingerprintResumedAtMs = now
    fingerprintUnreachedStreak = 0
  }

  // A suspended PAM conversation may be orphaned by the daemon restart.
  function restartFingerprintAfterSleep() {
    noteFingerprintResumed()
    if (fingerprintAuthenticating || fingerprintPam.active) {
      if (fingerprintPam.active) fingerprintPam.abort()
      settleFingerprintAttempt()
      return
    }
    if (!fingerprintRetryTimer.running) return
    armFingerprintRetry(FingerprintModel.MATCH_RETRY_MS)
  }

  function runBlank() {
    displaysAsleep = true
    pauseFingerprint()
    if (!blankProcess.running) blankProcess.running = true
  }

  function submitPassword(value) {
    var password = String(value || "")
    if (!lockRequested || authenticatingPassword || password.length === 0) return

    runWake()
    pendingPassword = password
    failureMessage = ""
    authenticatingPassword = true

    if (!passwordPam.start()) {
      handlePasswordFailure()
      return
    }

    Qt.callLater(respondToPasswordPrompt)
  }

  function respondToPasswordPrompt() {
    if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
    passwordPam.respond(pendingPassword)
  }

  // onError and onCompleted can both fire; settle each password attempt once
  // and always clear pendingPassword even if the lock was already dismissed.
  function handlePasswordFailure() {
    if (!authenticatingPassword) return

    authenticatingPassword = false
    pendingPassword = ""
    if (!lockRequested) return

    enteredPassword = ""
    failedAttempts += 1
    failureMessage = I18n.t("lock.authenticationFailed").arg(I18n.formatNumber(failedAttempts))
    runWake()
  }

  function startFingerprint() {
    if (!lockRequested || !sessionLock.secure || !fingerprintConfigured || fingerprintPaused) return
    if (fingerprintPam.active || fingerprintAuthenticating) return

    fingerprintAuthenticating = true
    fingerprintAttemptReachedDevice = false
    fingerprintAttemptFastError = false
    fingerprintAttemptPromptedAtMs = 0
    if (!fingerprintPam.start()) {
      // Pace a failed start while checking whether its PAM configuration was
      // removed; a definitive "no" stops retries and hides the indicator.
      settleFingerprintAttempt()
      refreshFingerprintStatus()
      return
    }
    // Bound claims that never prompt; a normal verify waits for a finger
    // under pam_fprintd's own timeout after reaching the reader.
    fingerprintReachTimer.restart()
  }

  // A prompt proves the claim landed, so stop waiting for reachability.
  function noteFingerprintReachedDevice() {
    if (fingerprintAttemptReachedDevice) return
    fingerprintAttemptReachedDevice = true
    fingerprintAttemptPromptedAtMs = Date.now()
    fingerprintReachTimer.stop()
  }

  // abort() gives no completion signal; settle the attempt here.
  function timeoutFingerprintReach() {
    logEvent("fingerprint-reach-timeout")
    if (fingerprintPam.active) fingerprintPam.abort()
    settleFingerprintAttempt()
  }

  // onError and onCompleted can both fire; settle each attempt once.
  function settleFingerprintAttempt(deviceError) {
    if (!fingerprintAuthenticating) return
    fingerprintAuthenticating = false
    fingerprintReachTimer.stop()
    if (!lockRequested || !fingerprintConfigured) return

    // An error can arrive before the sleep watcher notices the wall-clock gap.
    var now = Date.now()
    fingerprintAttemptFastError = !!deviceError && fingerprintAttemptReachedDevice && now - fingerprintAttemptPromptedAtMs < FingerprintModel.FAST_ERROR_MS
    var usableAttempt = fingerprintAttemptReachedDevice && !fingerprintAttemptFastError
    if (!usableAttempt && fingerprintSleepWatch.running
        && FingerprintModel.spannedSleep(now - fingerprintSleepWatch.lastTickMs, fingerprintSleepWatch.interval)) {
      noteFingerprintResumed()
    }

    // Reached attempts are the steady state (one per swipe window), so only
    // the misses and the recovery from them leave a trace.
    var previousStreak = fingerprintUnreachedStreak
    var inGrace = FingerprintModel.inResumeGrace(now, fingerprintResumedAtMs)
    fingerprintUnreachedStreak = FingerprintModel.nextStreak(previousStreak, usableAttempt, inGrace)
    if (!usableAttempt) {
      var crossed = !FingerprintModel.isUnavailable(previousStreak) && FingerprintModel.isUnavailable(fingerprintUnreachedStreak)
      logEvent((crossed ? "fingerprint-unavailable" : "fingerprint-unreached") + ": streak=" + fingerprintUnreachedStreak)
    } else if (previousStreak > 0) {
      logEvent("fingerprint-recovered: streak=" + previousStreak)
    }
    fingerprintLastSettleMs = now
    armFingerprintRetry(FingerprintModel.retryDelayMs(fingerprintUnreachedStreak))
  }

  function handleFingerprintFinished(result) {
    if (result === PamResult.Success && lockRequested) {
      // A match after a run of misses is the recovery too; the unlock resets
      // the streak without settling, so log it here or it leaves no trace.
      if (fingerprintUnreachedStreak > 0) logEvent("fingerprint-recovered: streak=" + fingerprintUnreachedStreak)
      finishUnlock()
    } else {
      settleFingerprintAttempt(result === PamResult.Error)
    }
  }

  // Local change: bind a loaded lock view (LockView.qml, or the fallback below) to this service. Only
  // properties the view declares are set, so the fallback can stay minimal. The preview gets no input
  // and no signals.
  function wireLockView(view, preview) {
    function bind(name, getter) { if (name in view) view[name] = Qt.binding(getter) }
    bind("backgroundPath", function() { return root.backgroundPath })
    bind("backgroundVersion", function() { return root.backgroundVersion })
    bind("videoPosterPath", function() { return root.videoPosterPath })
    bind("fingerprintConfigured", function() { return root.fingerprintConfigured || root.fingerprintUnavailable })
    bind("fingerprintUnavailable", function() { return root.fingerprintUnavailable })
    bind("loginTimeoutSeconds", function() { return root.settings.loginTimeoutSeconds })
    bind("idleScreen", function() { return root.settings.idleScreen })
    bind("crt", function() { return root.settings.crtStrength })
    bind("mdrClusters", function() { return root.settings.clusters })
    bind("mdrFiles", function() { return root.settings.files })
    if (preview) {
      bind("inputEnabled", function() { return false })
      bind("loadBackground", function() { return root.previewVisible })
      return
    }
    bind("authenticatingPassword", function() { return root.authenticatingPassword })
    bind("failureMessage", function() { return root.failureMessage })
    bind("failedAttempts", function() { return root.failedAttempts })
    bind("inputEnabled", function() { return root.lockRequested })
    bind("loadBackground", function() { return root.locked })
    bind("displaysAsleep", function() { return root.displaysAsleep })
    bind("passwordText", function() { return root.enteredPassword })
    view.passwordTextEdited.connect(function(password) { root.enteredPassword = password })
    view.submitPassword.connect(function(password) { root.submitPassword(password) })
    view.clearFailureRequested.connect(function() { root.failureMessage = "" })
    view.wakeRequested.connect(function() { root.runWake() })
  }

  // The last-resort lock view: a plain password field with the same interface as LockView.qml.
  // Nothing in it can fail to load.
  Component {
    id: fallbackLockView
    Rectangle {
      id: fallback
      color: "black"
      property string passwordText: ""
      property bool authenticatingPassword: false
      property string failureMessage: ""
      property bool inputEnabled: true
      signal submitPassword(string password)
      signal passwordTextEdited(string password)
      signal clearFailureRequested()
      signal wakeRequested()
      onPasswordTextChanged: if (fallbackInput.text !== passwordText) fallbackInput.text = passwordText
      Text {
        anchors.bottom: fallbackInput.top; anchors.bottomMargin: 16; anchors.horizontalCenter: parent.horizontalCenter
        text: fallback.authenticatingPassword ? "Checking…" : (fallback.failureMessage || "Password")
        color: "white"; font.pixelSize: 24
      }
      TextInput {
        id: fallbackInput
        anchors.centerIn: parent
        width: 400; height: 48
        focus: true
        enabled: fallback.inputEnabled && !fallback.authenticatingPassword
        echoMode: TextInput.Password
        color: "white"; font.pixelSize: 28
        verticalAlignment: TextInput.AlignVCenter
        Rectangle { anchors.fill: parent; anchors.margins: -8; z: -1; color: "transparent"; border.color: "white"; border.width: 2 }
        onTextChanged: {
          fallback.passwordTextEdited(text)
          fallback.wakeRequested()
          if (text.length > 0 && fallback.failureMessage.length > 0) fallback.clearFailureRequested()
        }
        onAccepted: { var p = text; fallback.passwordTextEdited(""); if (p.length > 0) fallback.submitPassword(p) }
      }
      MouseArea { anchors.fill: parent; onClicked: { fallback.wakeRequested(); fallbackInput.forceActiveFocus() } }
      Component.onCompleted: fallbackInput.forceActiveFocus()
    }
  }

  WlSessionLock {
    id: sessionLock

    locked: false

    onSecureStateChanged: {
      root.logEvent("secure=" + secure)
      if (secure) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.startFingerprint()
      }
    }

    onLockStateChanged: {
      root.logEvent("session-locked=" + locked)

      if (locked) {
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
      }

      if (!locked && root.lockRequested) {
        root.lockRequested = false
        root.pendingSessionLock = false
        sessionLockStabilizeTimer.stop()
        pendingSessionLockTimer.stop()
        root.resetAuthenticationState()
        root.restorePointer()
        root.runWake()
      }
    }

    WlSessionLockSurface {
      id: lockSurface
      // Right-to-left languages read this window mirrored.
      Binding { target: lockSurface.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
      Binding { target: lockSurface.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }

      color: Commons.Color.background

      // Local change: the view loads through a Loader, so an error in LockView.qml (or MdrScreen.qml)
      // can't stop this service from compiling and leave the session with no lock at all. If it fails,
      // fallbackLockView, which lives in this file, takes over.
      Loader {
        id: lockViewLoader
        anchors.fill: parent
        source: Qt.resolvedUrl("LockView.qml")
        onStatusChanged: {
          if (status !== Loader.Error) return
          root.logEvent("lock-view-failed: using the fallback login")
          sourceComponent = fallbackLockView
        }
        onLoaded: root.wireLockView(item, false)
      }
    }
  }

  PanelWindow {
    id: previewWindow
    // Right-to-left languages read this window mirrored.
    Binding { target: previewWindow.contentItem; property: "LayoutMirroring.enabled"; value: Commons.I18n.rightToLeft }
    Binding { target: previewWindow.contentItem; property: "LayoutMirroring.childrenInherit"; value: true }

    visible: root.previewVisible
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omarchy-lock-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Loader {
      anchors.fill: parent
      source: Qt.resolvedUrl("LockView.qml")
      onStatusChanged: if (status === Loader.Error) sourceComponent = fallbackLockView
      onLoaded: root.wireLockView(item, true)
    }

    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.previewVisible = false
    }
  }

  PamContext {
    id: passwordPam
    config: "omarchy-lock-password"
    user: root.userName

    onResponseRequiredChanged: root.respondToPasswordPrompt()
    onPamMessage: root.respondToPasswordPrompt()

    onCompleted: function(result) {
      if (!root.authenticatingPassword) return
      if (!root.lockRequested) {
        root.authenticatingPassword = false
        root.pendingPassword = ""
        return
      }
      if (result === PamResult.Success) {
        root.authenticatingPassword = false
        root.pendingPassword = ""
        root.finishUnlock()
      } else {
        root.handlePasswordFailure()
      }
    }

    onError: function(error) {
      root.handlePasswordFailure()
    }
  }

  PamContext {
    id: fingerprintPam
    config: "omarchy-lock-fingerprint"
    user: root.userName

    onPamMessage: {
      if (!messageIsError) root.noteFingerprintReachedDevice()
    }

    onCompleted: function(result) {
      root.handleFingerprintFinished(result)
    }

    onError: function(error) {
      root.settleFingerprintAttempt(true)
    }
  }

  // Local change: Omarchy keeps each screen's lock wallpaper decoded ahead of the lock here, so its
  // first frame has the wallpaper. LockView.qml draws no wallpaper, so that preload is left out
  // rather than holding a decoded image per screen for nothing.

  Timer {
    id: fingerprintRetryTimer
    interval: FingerprintModel.MATCH_RETRY_MS
    repeat: false
    onTriggered: root.startFingerprint()
  }

  // Detect resume both during an active attempt and during backoff.
  Timer {
    id: fingerprintSleepWatch
    interval: 1000
    repeat: true
    running: root.lockRequested && root.fingerprintConfigured && (!root.fingerprintPaused || root.fingerprintAuthenticating)
    property double lastTickMs: 0
    onRunningChanged: lastTickMs = Date.now()
    onTriggered: {
      var now = Date.now()
      var slept = FingerprintModel.spannedSleep(now - lastTickMs, interval)
      lastTickMs = now
      if (slept) root.restartFingerprintAfterSleep()
    }
  }

  // Timers stand still through a suspend, so the first tick after a resume
  // sees the wall clock jump. Runs only for the seconds after a lock request
  // that a suspend can take to begin.
  Timer {
    id: fingerprintResumeTimer
    interval: 1000
    repeat: true
    property int ticksLeft: 0
    property double lastTickMs: 0
    onTriggered: {
      var now = Date.now()
      var slept = FingerprintModel.spannedSleep(now - lastTickMs, interval)
      lastTickMs = now
      if (slept && root.lockRequested && root.fingerprintPaused) {
        stop()
        root.fingerprintSleptWhilePaused = true
        // A panel blanked before the sleep stays dark through the resume, and
        // opening the lid is no input that would light it.
        if (!wakeProcess.running) wakeProcess.running = true
        // Local change: the displays are lit again, so the lock view's animation runs again too.
        root.displaysAsleep = false
        root.resumeFingerprint()
        root.armBlankTimer(idleBlankTimer.resumeMs)
      } else if (slept || !root.fingerprintPaused || --ticksLeft <= 0) {
        stop()
      }
    }
  }

  Timer {
    id: fingerprintReachTimer
    interval: FingerprintModel.REACH_TIMEOUT_MS
    repeat: false
    onTriggered: root.timeoutFingerprintReach()
  }

  Process {
    id: readlinkProc
    command: ["bash", "-c", "path=$(readlink -f -- \"$1\") && printf '%s\\n%s\\n' \"$path\" \"$(stat -Lc %Y:%s -- \"$path\" 2>/dev/null)\"", "_", root.currentBackgroundLink]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var next = String(lines[0] || "").trim()
        var signature = String(lines[1] || "").trim()
        if (next !== root.backgroundPath) {
          root.videoPosterPath = ""
          root.backgroundPath = next
          root.backgroundSignature = signature
          root.backgroundVersion += 1
        } else if (signature !== root.backgroundSignature) {
          root.backgroundSignature = signature
          root.backgroundVersion += 1
        }
        root.refreshPoster()
      }
    }
  }

  Process {
    id: posterProc
    property string sourcePath: ""
    command: ["bash", Quickshell.env("OMARCHY_PATH") + "/shell/plugins/lock/poster.sh", sourcePath]
    stdout: StdioCollector { id: posterOutput; waitForEnd: true }
    onExited: function(exitCode) {
      if (sourcePath !== root.backgroundPath) {
        root.refreshPoster()
      } else {
        root.videoPosterPath = exitCode === 0 ? String(posterOutput.text || "").trim() : ""
      }
    }
  }

  // Keep fprintd errors distinguishable from an explicit empty enrollment.
  Process {
    id: fingerprintCheckProc
    command: ["bash", "-c", "if [[ -f /etc/pam.d/omarchy-lock-fingerprint ]] && command -v fprintd-list >/dev/null 2>&1; then LC_ALL=C fprintd-list \"$USER\" 2>&1; else echo no; fi"]
    stdout: StdioCollector { id: fingerprintCheckStdout; waitForEnd: true }
    onExited: root.applyFingerprintProbe(fingerprintCheckStdout.text)
  }

  // Retries a probe that could not reach fprintd, paced like the attempt
  // retries so a daemon that stays unreachable is asked about ever less often.
  Timer {
    id: fingerprintRecheckTimer
    interval: FingerprintModel.ERROR_RETRY_BASE_MS
    repeat: false
    onTriggered: root.refreshFingerprintStatus()
  }

  Process {
    id: strandedLockCheckProc
    // $PPID is this shell: a crash re-execs in place, so its pid is the one to skip.
    command: ["bash", "-c", "omarchy-hyprland-session-lock-stranded \"$PPID\""]
    onExited: function(exitCode) {
      // No output to read the lock off yet.
      if (exitCode === 2) return

      root.strandedLockResolved = true

      // A lock taken while this was in flight is this shell's own.
      root.strandedLock = exitCode === 0 && !root.currentlyLocked()
      root.recoverStrandedLock()
    }
  }

  Process {
    id: wakeProcess
    command: ["bash", "-c", "omarchy-system-wake"]
  }

  Process {
    id: blankProcess
    command: ["bash", "-c", "omarchy-brightness-keyboard off; omarchy-brightness-display off"]
  }

  Timer {
    id: idleBlankTimer
    // Local change: Omarchy blanks the displays 5 seconds after locking (and after each wake). The lock
    // screen plays the MDR screen while idle (LockView.qml), so they stay lit for the displayOffSeconds
    // setting instead, and a resume never gets a shorter run-up than that.
    readonly property int idleMs: root.settings.displayOffSeconds * 1000
    // A resume reaches this as soon as the kernel thaws, seconds before the
    // panel lights (on NVIDIA it waits out a VT switch and a modeset), so the
    // idle run-up blanked the lock just as it appeared.
    readonly property int resumeMs: Math.max(15000, idleMs)
    interval: idleMs
    repeat: false
    property double armedAt: 0
    onTriggered: {
      // A countdown frozen by suspend fires right after resume, which would
      // blank the freshly woken unlock screen under the user. Wall-clock time
      // exposes the gap: take a fresh run-up instead of blanking.
      if (Date.now() - armedAt > interval + 2000) {
        root.armBlankTimer(resumeMs)
        return
      }
      // Only a password check in flight should hold the display up. The
      // fingerprint PAM stays armed for the whole lock, so gating on
      // `authenticating` here would keep the panel lit until unlock.
      if (root.lockRequested && !root.authenticatingPassword) root.runBlank()
    }
  }

  // Hyprland lights the panel for any key, but a bound key like volume never
  // reaches the lock surface, so nothing re-arms the blank and the lock stays
  // lit. Blank once input has been quiet for the run-up and no countdown is
  // pending, so the resume run-up is left alone.
  IdleMonitor {
    id: lockIdleMonitor
    enabled: root.lockRequested
    timeout: idleBlankTimer.idleMs / 1000
    respectInhibitors: false
    onIsIdleChanged: {
      if (isIdle && root.lockRequested && !root.authenticatingPassword && !idleBlankTimer.running) root.runBlank()
    }
  }

  Timer {
    id: sessionLockStabilizeTimer
    interval: 500
    repeat: false
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: pendingSessionLockTimer
    interval: 100
    repeat: true
    onTriggered: root.requestSessionLock()
  }

  Timer {
    id: strandedLockRetryTimer
    interval: 500
    repeat: true
    // Covers the compositor settling; screens coming back re-arm it.
    readonly property int budget: 20
    property int remaining: 20
    running: !root.strandedLockResolved && remaining > 0

    function rearm() {
      if (!root.strandedLockResolved) remaining = budget
    }

    onTriggered: {
      remaining -= 1
      root.checkStrandedLock()
    }
  }

  Connections {
    target: Quickshell
    function onScreensChanged() {
      var screens = root.realScreenCount()
      if (screens > root.knownScreenCount) {
        root.resumeFingerprint()
        if (root.lockRequested) root.armBlankTimer()
      }
      root.knownScreenCount = screens
      root.requestSessionLock()

      // A monitor still coming up has no workspace, so cannot answer yet.
      strandedLockRetryTimer.rearm()
      root.checkStrandedLock()
    }
  }

  onAuthenticatingPasswordChanged: {
    if (!lockRequested) return
    if (authenticatingPassword) idleBlankTimer.stop()
    else armBlankTimer()
  }

  FileView {
    path: "/etc/pam.d/omarchy-lock-password"
    watchChanges: true
    printErrors: false
    onLoaded: root.passwordPamConfigured = true
    onLoadFailed: root.passwordPamConfigured = false
    onFileChanged: reload()
  }

  // No lock before PAM is known good. An answer from before then may be stale --
  // the failsafe can be cleared from a TTY -- so re-ask rather than act on it.
  onPasswordPamConfiguredChanged: {
    if (!passwordPamConfigured) return

    strandedLock = false
    strandedLockResolved = false
    strandedLockRetryTimer.rearm()
    checkStrandedLock()
  }

  Component.onCompleted: {
    knownScreenCount = realScreenCount()
    refreshBackground()
    refreshFingerprintStatus()
    checkStrandedLock()
  }

  ShellIpc {
    target: "lock"

    function lock(): string {
      if (!root.passwordPamConfigured) return "missing-pam"
      // omarchy-system-sleep-lock asks for the lock before every suspend.
      if (root.currentlyLocked()) root.noteSleepRequested()
      if (!root.currentlyLocked() && !root.beginLock()) return "failed"
      return "ok"
    }

    function isLocked(): string {
      return root.currentlyLocked() ? "true" : "false"
    }

    function status(): string {
      return JSON.stringify({
        locked: root.currentlyLocked(),
        requested: root.lockRequested,
        pending: root.pendingSessionLock,
        sessionLocked: sessionLock.locked,
        secure: sessionLock.secure,
        realScreens: root.realScreenCount(),
        passwordPam: root.passwordPamConfigured,
        fingerprint: root.fingerprintConfigured,
        fingerprintUnavailable: root.fingerprintUnavailable,
        authenticating: root.authenticating,
        lastEvent: root.lastEvent,
        lastEventAt: root.lastEventAt
      })
    }

    function preview(): string {
      root.refreshBackground()
      root.refreshFingerprintStatus()
      root.previewVisible = true
      return "ok"
    }

    function hidePreview(): string {
      root.previewVisible = false
      return "ok"
    }
  }
}
