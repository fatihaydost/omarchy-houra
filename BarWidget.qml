import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Bridge.js" as Bridge
import "Theme.js" as Theme
import "components"

// Omarchy bar widget entry point (instantiated once per monitor by omarchy.bar).
// Connects to the singleton Service.qml via Bridge.js (with bar.serviceFor fallback),
// renders the signature HouraGlyph + stable-width MM:SS readout, and hosts BarPopout.
BarWidget {
  id: root
  moduleName: "io.github.fatihaydost.houra"

  property var liveService: null
  readonly property var svc: liveService || (root.bar && typeof root.bar.serviceFor === "function"
    ? root.bar.serviceFor("io.github.fatihaydost.houra")
    : null)
  readonly property string screenName: {
    var win = QsWindow.window
    return (win && win.screen && win.screen.name) ? String(win.screen.name) : ""
  }

  property var _bridgeCb: null

  Component.onCompleted: {
    Bridge.registerBarWidget(root)
    _bridgeCb = function(s) { root.liveService = s }
    Bridge.subscribe(_bridgeCb)
  }

  Component.onDestruction: {
    if (_bridgeCb) Bridge.unsubscribe(_bridgeCb)
    Bridge.unregisterBarWidget(root)
  }

  // Shape contract for omarchy-shell `shell toggle io.github.fatihaydost.houra`
  readonly property bool opened: popout.opened
  readonly property bool popoutSwitchClosing: popout.popoutSwitchClosing

  function open() { popout.open() }
  function close() { popout.close() }
  function togglePanel() { popout.toggle() }
  function closeForPopoutSwitch() { popout.closeForPopoutSwitch() }

  readonly property string phase: svc ? svc.phase : "idle"
  readonly property real progress: svc ? svc.progress : 0.0
  readonly property string lang: svc ? svc.lang : "en"
  readonly property bool showTimerPref: root.setting("showTimerInBar", true) !== false
  readonly property bool timerVisible: showTimerPref && phase !== "idle"
  readonly property string timerText: {
    if (!svc) return ""
    if (phase === "rest") return svc.restClockText
    if (phase === "focus" || phase === "paused") return svc.clockText
    return ""
  }

  readonly property string tooltipText: {
    if (!svc) return "Houra"
    if (phase === "focus" || phase === "paused") {
      let cname = svc.activeCategory ? svc.activeCategory.name : "Houra"
      let lbl = svc.sessionGoal ? (cname + " · " + svc.sessionGoal) : cname
      return lbl + " (" + svc.clockText + ")"
    }
    if (phase === "rest") {
      return Theme.t(lang, "Mola · ", "Break · ") + svc.restClockText
    }
    let mins = svc.todayData ? (svc.todayData.focusMinutes || 0) : 0
    return "Houra — " + Theme.t(lang, "Bugün ", "Today ") + Theme.formatMinutes(mins, lang)
  }

  readonly property color fgColor: root.bar ? root.bar.barForeground : Commons.Color.foreground
  readonly property int glyphPx: Style.space(18)

  // Reserve stable digit width ("88:88") so the bar pill never shifts every second
  TextMetrics {
    id: clockMetrics
    font.family: root.bar ? root.bar.fontFamily : Style.font.family
    font.pixelSize: Style.font.body
    text: "88:88"
  }

  readonly property real reservedContentWidth: timerVisible
    ? (glyphPx + Style.space(5) + Math.ceil(clockMetrics.width))
    : glyphPx

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarPopout {
    id: popout
    bar: root.bar
    anchorItem: button
    hostWidget: root
    service: root.svc
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: root.tooltipText
    labelVisible: false
    hasVisualContent: true
    active: root.opened
    useActiveColor: false
    fixedWidth: root.vertical
      ? -1
      : Math.ceil(root.reservedContentWidth + Style.spaceReal(horizontalMargin) * 2)
    fixedHeight: root.vertical
      ? Math.ceil(contentRow.implicitHeight + Style.spaceReal(verticalPadding) * 2)
      : -1

    onPressed: function(b) {
      if (b === Qt.MiddleButton) {
        if (!root.svc) return
        if (root.phase === "focus" || root.phase === "paused") root.svc.togglePause()
        else root.svc.openNewSession(0, "")
      } else if (b === Qt.RightButton) {
        root.close()
        if (root.svc) root.svc.openMainPanel("")
      } else {
        root.togglePanel()
      }
    }

    Row {
      id: contentRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      HouraGlyph {
        anchors.verticalCenter: parent.verticalCenter
        glyphSize: root.glyphPx
        phase: root.phase
        progress: root.progress
        inkColor: root.fgColor
      }

      Text {
        textFormat: Text.PlainText
        visible: root.timerVisible && !root.vertical
        width: Math.ceil(clockMetrics.width)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignLeft
        text: root.timerText
        font.family: root.bar ? root.bar.fontFamily : Style.font.family
        font.pixelSize: Style.font.body
        renderType: Text.NativeRendering
        color: root.fgColor
      }
    }
  }
}
