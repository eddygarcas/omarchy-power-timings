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
//
// Reads and writes shell.json's `idle` block through our own FileView
// instead of shell.shellConfig / shell.mutateShellConfig: Omarchy 4.0.3
// scoped that bridge to bar-kind plugins mutating only config.bar, so for a
// service+bar-widget plugin like this one it now silently no-ops (and
// shell.shellConfig is undefined entirely on the scoped API). Going straight
// to the file keeps reads live and writes working regardless.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stayAwakeDir: home + "/.local/state/omarchy/indicators"
  readonly property string shellConfigPath: home + "/.config/omarchy/shell.json"

  property var shellConfigSnapshot: ({})
  readonly property var idleConfig: shellConfigSnapshot && typeof shellConfigSnapshot.idle === "object" && shellConfigSnapshot.idle
    ? shellConfigSnapshot.idle : ({})

  function reloadShellConfig() {
    var raw = String(configFile.text() || "").trim()
    if (!raw) {
      root.shellConfigSnapshot = ({})
      return
    }
    try {
      var parsed = JSON.parse(raw)
      root.shellConfigSnapshot = (parsed && typeof parsed === "object") ? parsed : ({})
    } catch (e) {
      console.warn("eduard.power-timings: shell.json parse failed, keeping last known config:", e)
    }
  }

  // Merges one idle.* key into shell.json and writes the whole file back, so
  // sibling keys (bar layout, other plugins' settings) survive untouched. On
  // a parse failure we refuse to write rather than clobber the file with a
  // partial config.
  function mutateIdleConfig(key, value) {
    var raw = String(configFile.text() || "").trim()
    var config = {}
    if (raw) {
      try {
        var parsed = JSON.parse(raw)
        if (parsed && typeof parsed === "object") config = parsed
      } catch (e) {
        console.warn("eduard.power-timings: shell.json parse failed, refusing to write:", e)
        return false
      }
    }
    if (!config.idle || typeof config.idle !== "object") config.idle = {}
    config.idle[key] = value
    config.version = 1
    root.shellConfigSnapshot = config
    configFile.setText(JSON.stringify(config, null, 2) + "\n")
    return true
  }

  property FileView configFile: FileView {
    path: root.shellConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.reloadShellConfig()
    onLoadFailed: function(error) { root.reloadShellConfig() }
    onFileChanged: reload()
  }

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
    onExited: function(exitCode, exitStatus) { root.logEvent("suspend-exit code=" + exitCode) }
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
