import QtQuick
import Quickshell
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
          spacing: Style.space(10)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          PanelSectionHeader {
            text: "SCREENSAVER AFTER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.screensaverPresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.screensaverSeconds === modelData.seconds
                onClicked: root.setIdleValue("screensaver", modelData.seconds)
              }
            }
          }
        }

        // ---------- Lock ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          PanelSectionHeader {
            text: "LOCK AFTER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.lockPresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.lockSeconds === modelData.seconds
                onClicked: root.setIdleValue("lock", modelData.seconds)
              }
            }
          }
        }

        // ---------- Suspend ----------
        Column {
          width: parent.width
          spacing: Style.space(10)
          enabled: root.timingsManaged
          opacity: root.timingsManaged ? 1.0 : 0.45

          Behavior on opacity { NumberAnimation { duration: 120 } }

          PanelSectionHeader {
            text: "SUSPEND AFTER"
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: Model.suspendPresets
              Button {
                required property var modelData
                text: modelData.label
                fontSize: Style.font.bodySmall
                foreground: root.bar.foreground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.suspendSeconds === modelData.seconds
                onClicked: root.setIdleValue("suspend", modelData.seconds)
              }
            }
          }

          Text {
            visible: root.suspendSeconds > 0 && root.suspendSeconds <= root.lockSeconds
            text: "Tip: keep Suspend longer than Lock so the screen locks first."
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
            width: parent.width
            wrapMode: Text.WordWrap
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
            onClicked: root.lockNow()
          }

          Button {
            text: "Suspend now"
            iconText: "󰒲"
            fontSize: Style.font.bodySmall
            foreground: root.bar.foreground
            fontFamily: root.bar.fontFamily
            bordered: true
            onClicked: root.suspendNow()
          }
        }
      }
    }
  }
}
