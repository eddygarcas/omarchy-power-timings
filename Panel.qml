import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "eduard.power-timings"
  ipcTarget: moduleName

  readonly property var svc: bar && bar.shell ? bar.shell.serviceFor(root.moduleName) : null
  readonly property var idleConfig: bar && bar.shell && bar.shell.shellConfig && bar.shell.shellConfig.idle
    ? bar.shell.shellConfig.idle : ({})
  readonly property int screensaverSeconds: Model.clampSeconds(idleConfig.screensaver, 150)
  readonly property int lockSeconds: Model.clampSeconds(idleConfig.lock, 300)
  readonly property int suspendSeconds: Model.clampSeconds(idleConfig.suspend, 0)
  readonly property bool stayAwake: !!(svc && svc.stayAwake)
  readonly property bool timingsManaged: idleConfig.timingsManaged !== false

  // Slider positions, derived from the committed seconds. Config values are
  // always one of this list's own presets, so this is an exact match.
  readonly property int screensaverIndex: Model.nearestIndexForSeconds(Model.screensaverPresets, root.screensaverSeconds)
  readonly property int lockIndex: Model.nearestIndexForSeconds(Model.lockPresets, root.lockSeconds)
  readonly property int suspendIndex: Model.nearestIndexForSeconds(Model.suspendPresets, root.suspendSeconds)

  function setIdleValue(key, value) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function(config) {
      if (!config.idle || typeof config.idle !== "object") config.idle = {}
      config.idle[key] = value
    })
  }

  function setTimingsManaged(value) {
    root.setIdleValue("timingsManaged", value)
  }

  // Screensaver, lock, and suspend always keep screensaver < lock < suspend
  // (suspend's "Never" / 0 is exempt). Dragging one slider past a neighbor
  // pushes that neighbor's own slider forward to the next preset instead of
  // landing on an invalid ordering.
  function setScreensaverIndex(index) {
    var seconds = Model.screensaverPresets[index].seconds
    root.setIdleValue("screensaver", seconds)
    root.enforceLockFloor(seconds)
  }

  function setLockIndex(index) {
    var seconds = Model.lockPresets[index].seconds
    if (seconds <= root.screensaverSeconds)
      seconds = Model.lockPresets[Model.indexAboveSeconds(Model.lockPresets, root.screensaverSeconds)].seconds
    root.setIdleValue("lock", seconds)
    root.enforceSuspendFloor(seconds)
  }

  function setSuspendIndex(index) {
    var seconds = Model.suspendPresets[index].seconds
    if (seconds !== 0 && seconds <= root.lockSeconds)
      seconds = Model.suspendPresets[Model.indexAboveSeconds(Model.suspendPresets, root.lockSeconds)].seconds
    root.setIdleValue("suspend", seconds)
  }

  function enforceLockFloor(minSeconds) {
    if (root.lockSeconds > minSeconds) return
    var seconds = Model.lockPresets[Model.indexAboveSeconds(Model.lockPresets, minSeconds)].seconds
    root.setIdleValue("lock", seconds)
    root.enforceSuspendFloor(seconds)
  }

  function enforceSuspendFloor(minSeconds) {
    if (root.suspendSeconds === 0 || root.suspendSeconds > minSeconds) return
    var seconds = Model.suspendPresets[Model.indexAboveSeconds(Model.suspendPresets, minSeconds)].seconds
    root.setIdleValue("suspend", seconds)
  }

  function lockNow() {
    if (lockProcess.running) return
    lockProcess.running = true
  }

  function suspendNow() {
    if (suspendProcess.running) return
    suspendProcess.running = true
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process { id: lockProcess; command: ["omarchy-system-lock"] }
  Process { id: suspendProcess; command: ["systemctl", "suspend"] }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅶"
    slotSize: Style.bar.iconSlot
    tooltipText: "Power timings"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Row {
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "󰅶"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            spacing: Style.space(2)
            anchors.verticalCenter: parent.verticalCenter

            Text {
              text: "Power Timings"
              color: root.bar.foreground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              text: !root.timingsManaged
                ? "SYSTEM DEFAULTS — POWER TIMINGS OFF"
                : root.stayAwake
                  ? "STAY AWAKE IS ON — AUTO-SUSPEND PAUSED"
                  : "Screensaver " + Model.formatDuration(root.screensaverSeconds)
                    + " · Lock " + Model.formatDuration(root.lockSeconds)
                    + " · Suspend " + Model.formatDuration(root.suspendSeconds)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
              width: Style.space(300)
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Manage toggle ----------
        Toggle {
          width: parent.width
          label: "Manage power timings"
          description: root.timingsManaged
            ? "Screensaver, lock, and suspend follow the timings below."
            : "Off — screensaver and lock follow the system's own idle defaults, and auto-suspend is disabled."
          checked: root.timingsManaged
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          onClicked: root.setTimingsManaged(!root.timingsManaged)
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Screensaver ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          Item {
            width: parent.width
            implicitHeight: Math.max(screensaverHeader.implicitHeight, screensaverValue.implicitHeight)

            PanelSectionHeader {
              id: screensaverHeader
              text: "SCREENSAVER AFTER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: screensaverValue
              text: Model.formatDuration(Model.screensaverPresets[
                Math.round(screensaverSlider.dragging ? screensaverSlider.liveValue : root.screensaverIndex)
              ].seconds)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: screensaverSlider
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: Model.screensaverPresets.length - 1
            integer: true
            step: 1
            tickCount: Model.screensaverPresets.length
            value: root.screensaverIndex
            onReleased: function(v) { root.setScreensaverIndex(Math.round(v)) }
          }

          Row {
            width: parent.width
            Repeater {
              model: Model.screensaverPresets
              Text {
                required property var modelData
                text: modelData.label
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / Model.screensaverPresets.length
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }

        // ---------- Lock ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          Item {
            width: parent.width
            implicitHeight: Math.max(lockHeader.implicitHeight, lockValue.implicitHeight)

            PanelSectionHeader {
              id: lockHeader
              text: "LOCK AFTER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: lockValue
              text: Model.formatDuration(Model.lockPresets[
                Math.round(lockSlider.dragging ? lockSlider.liveValue : root.lockIndex)
              ].seconds)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: lockSlider
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: Model.lockPresets.length - 1
            integer: true
            step: 1
            tickCount: Model.lockPresets.length
            value: root.lockIndex
            onReleased: function(v) { root.setLockIndex(Math.round(v)) }
          }

          Row {
            width: parent.width
            Repeater {
              model: Model.lockPresets
              Text {
                required property var modelData
                text: modelData.label
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / Model.lockPresets.length
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }

        // ---------- Suspend ----------
        Column {
          width: parent.width
          spacing: Style.space(8)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          Item {
            width: parent.width
            implicitHeight: Math.max(suspendHeader.implicitHeight, suspendValue.implicitHeight)

            PanelSectionHeader {
              id: suspendHeader
              text: "SUSPEND AFTER"
              foreground: root.bar.foreground
              fontFamily: root.bar.fontFamily
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              id: suspendValue
              text: Model.formatDuration(Model.suspendPresets[
                Math.round(suspendSlider.dragging ? suspendSlider.liveValue : root.suspendIndex)
              ].seconds)
              color: Qt.darker(root.bar.foreground, 1.4)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          PanelSlider {
            id: suspendSlider
            bar: root.bar
            width: parent.width
            minimum: 0
            maximum: Model.suspendPresets.length - 1
            integer: true
            step: 1
            tickCount: Model.suspendPresets.length
            value: root.suspendIndex
            onReleased: function(v) { root.setSuspendIndex(Math.round(v)) }
          }

          Row {
            width: parent.width
            Repeater {
              model: Model.suspendPresets
              Text {
                required property var modelData
                text: modelData.label
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                width: parent.width / Model.suspendPresets.length
                horizontalAlignment: Text.AlignHCenter
              }
            }
          }
        }

        PanelSeparator { foreground: root.bar.foreground }

        // ---------- Quick actions ----------
        Row {
          width: parent.width
          spacing: Style.space(8)

          Button {
            text: "Lock now"
            iconText: "󰌾"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            radius: height / 2
            onClicked: root.lockNow()
          }

          Button {
            text: "Suspend now"
            iconText: "󰒲"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            radius: height / 2
            onClicked: root.suspendNow()
          }
        }
      }
    }
  }
}
