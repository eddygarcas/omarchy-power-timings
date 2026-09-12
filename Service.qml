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
// Reads shell.json's `idle` block through our own FileView and writes it via
// power_timings_ctl.py (see mutateIdleConfig below), instead of
// shell.shellConfig / shell.mutateShellConfig: Omarchy 4.0.3 scoped that
// bridge to bar-kind plugins mutating only config.bar, so for a
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
  // sibling keys (bar layout, other plugins' settings) survive untouched.
  // The actual read-merge-write happens out-of-process in
  // power_timings_ctl.py, never through this FileView: a plain path-based
  // open() (which is all FileView gives us) follows symlinks, so a symlink
  // planted at shell.json itself, or at an ancestor directory, could
  // silently redirect the overwrite to an arbitrary file this user can
  // write. The script instead holds an ancestor-nofollow, owner-checked
  // directory descriptor, revalidates shell.json's identity immediately
  // before committing, and commits via a same-directory temp file that's
  // fsync'd and atomically renamed over the real name -- safe even if
  // shell.json currently is (or becomes) a symlink, since rename(2) never
  // follows one. The UI updates optimistically below so sliders feel
  // instant; reloadShellConfig() reconciles from disk once the process
  // reports back, so a refused write (e.g. a detected symlink attack)
  // self-heals the displayed value instead of leaving a phantom setting.
  // At most one write helper runs at a time; a mutation requested while one
  // is still in flight (e.g. releasing a second slider right after the
  // first) is queued as the single next-to-run one rather than launched
  // concurrently or dropped -- only the final merged value matters, so
  // collapsing several queued mutations into "just run the latest" is
  // exact, not lossy.
  property var pendingMutation: null

  function mutateIdleConfig(key, value) {
    var config = root.shellConfigSnapshot && typeof root.shellConfigSnapshot === "object"
      ? JSON.parse(JSON.stringify(root.shellConfigSnapshot)) : ({})
    if (!config.idle || typeof config.idle !== "object") config.idle = {}
    config.idle[key] = value
    config.version = 1
    root.shellConfigSnapshot = config

    if (mutateProcess.running) {
      root.pendingMutation = { key: key, value: value }
    } else {
      root.launchMutateProcess(key, value)
    }
    return true
  }

  function launchMutateProcess(key, value) {
    mutateProcess.command = [
      Quickshell.env("PYTHON") || "python3", root.scriptPath(),
      key, JSON.stringify(value)
    ]
    mutateProcess.running = true
  }

  function scriptPath() {
    return Qt.resolvedUrl("power_timings_ctl.py").toString().replace(/^file:\/\//, "")
  }

  property Process mutateProcess: Process {
    stdout: StdioCollector {
      onStreamFinished: {
        var ok = false
        try {
          var result = JSON.parse(String(text || ""))
          ok = !!result.success
          if (!ok) console.warn("eduard.power-timings: shell.json write refused:", result.error)
        } catch (e) {
          console.warn("eduard.power-timings: could not parse write helper output:", e)
        }
        configFile.reload()
      }
    }
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0) console.warn("eduard.power-timings: write helper exited", exitCode)
      if (root.pendingMutation) {
        var next = root.pendingMutation
        root.pendingMutation = null
        root.launchMutateProcess(next.key, next.value)
      }
    }
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
