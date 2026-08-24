import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Model.js" as Model

// Auto-suspend after idle. Screensaver and lock timeouts are already owned
// by the built-in omarchy.idle service (idle.screensaver / idle.lock in
// shell.json); this service adds the missing third timeout (idle.suspend)
// and calls `systemctl suspend` once it elapses. omarchy-sleep-lock.service
// (a user systemd unit watching logind's PrepareForSleep signal) locks the
// session before ANY suspend, manual or automatic, so we don't need to lock
// here ourselves.
QtObject {
  id: root

  // Injected by omarchy-shell.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"
  readonly property var idleConfig: shell && shell.shellConfig && shell.shellConfig.idle ? shell.shellConfig.idle : ({})
  readonly property int suspendTimeoutSeconds: Model.clampSeconds(idleConfig.suspend, 0)
  readonly property bool suspendConfigured: suspendTimeoutSeconds > 0
  readonly property bool timingsManaged: idleConfig.timingsManaged !== false
  readonly property bool suspendEnabled: suspendConfigured && timingsManaged && stayAwakeStateLoaded && !stayAwake

  property bool stayAwake: false
  property bool stayAwakeStateLoaded: false
  property string lastEvent: "starting"

  function logEvent(event) {
    root.lastEvent = event
    console.log("eduard.power-timings " + new Date().toISOString() + " " + event)
  }

  function refreshStayAwake() {
    if (!stayAwakeProbe.running) stayAwakeProbe.running = true
  }

  function applyStayAwake(value) {
    var enabled = !!value
    if (root.stayAwakeStateLoaded && root.stayAwake === enabled) return
    root.stayAwake = enabled
    root.stayAwakeStateLoaded = true
    logEvent(enabled ? "stay-awake-on" : "stay-awake-off")
  }

  function triggerSuspend() {
    if (suspendProcess.running) return
    logEvent("suspend-triggered timeout=" + root.suspendTimeoutSeconds)
    suspendProcess.running = true
  }

  property var suspendMonitor: IdleMonitor {
    enabled: root.suspendEnabled
    timeout: Math.max(1, root.suspendTimeoutSeconds)
    respectInhibitors: true
    onIsIdleChanged: if (isIdle && root.suspendEnabled) root.triggerSuspend()
  }

  property Process suspendProcess: Process {
    command: ["systemctl", "suspend"]
    onExited: function(exitCode) { root.logEvent("suspend-exit code=" + exitCode) }
  }

  // Mirrors the same stay-awake state file the built-in idle indicator uses,
  // so toggling "Stay awake" also pauses auto-suspend.
  property Process stayAwakeProbe: Process {
    command: ["bash", "-lc", "if [[ -f \"$HOME/.local/state/omarchy/indicators/stay-awake\" ]]; then echo yes; else echo no; fi"]
    stdout: SplitParser {
      onRead: function(line) { root.applyStayAwake(String(line).trim() === "yes") }
    }
  }

  property FileView stayAwakeDirWatcher: FileView {
    path: root.stayAwakeDir
    watchChanges: true
    printErrors: false
    onFileChanged: root.refreshStayAwake()
  }

  Component.onCompleted: {
    logEvent("service-ready")
    refreshStayAwake()
  }
}
