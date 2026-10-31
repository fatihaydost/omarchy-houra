import QtQuick
import "../Theme.js" as Theme

// Dynamic vertical hourly day-flow timeline matching DetailView.swift:196-238 & Panel.swift:222:
// Spans dynamically from firstHour to lastHour at 56px/hour, labels every hour,
// renders both completed sessions and the live running session (start -> plannedEnd/now),
// and places the current-time pill in the left gutter.
Item {
  id: root

  property var sessions: []
  property bool hasActiveSession: false
  property int activeSessionId: 0
  property string activeCategoryName: ""
  property string activeColor: "#ffffff"
  property string activeGoal: ""
  property real activeStartEpoch: 0
  property real activeEndEpoch: 0
  property bool monochromeBlocks: false
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"
  property real hourHeight: 56

  property real nowHourFrac: _computeNowFrac()
  property string nowLabel: _computeNowLabel()

  function _computeNowFrac() {
    var d = new Date()
    return d.getHours() + d.getMinutes() / 60.0 + d.getSeconds() / 3600.0
  }

  function _computeNowLabel() {
    var d = new Date()
    var hh = d.getHours()
    var mm = d.getMinutes()
    return (hh < 10 ? "0" + hh : String(hh)) + ":" + (mm < 10 ? "0" + mm : String(mm))
  }

  function _epochToHourFrac(ep) {
    if (!ep || ep <= 0) return nowHourFrac
    var d = new Date(Number(ep) * 1000)
    return d.getHours() + d.getMinutes() / 60.0 + d.getSeconds() / 3600.0
  }

  Timer {
    interval: 20000
    running: root.visible
    repeat: true
    onTriggered: {
      root.nowHourFrac = root._computeNowFrac()
      root.nowLabel = root._computeNowLabel()
    }
  }

  onVisibleChanged: {
    if (visible) {
      nowHourFrac = _computeNowFrac()
      nowLabel = _computeNowLabel()
    }
  }

  readonly property var combinedBlocks: {
    var arr = []
    var list = root.sessions || []
    for (var i = 0; i < list.length; i++) {
      var s = list[i]
      if (!s.completed) continue
      if (root.hasActiveSession && Number(s.id) === root.activeSessionId) continue
      arr.push({
        categoryName: s.categoryName || "",
        goal: s.goal || "",
        color: s.color || "#4c8df0",
        startEpoch: Number(s.start) || 0,
        endEpoch: Number(s.end) || Number(s.start) || 0,
        startH: Number(s.startHourFrac) || 0,
        endH: Number(s.endHourFrac) || 0,
        isLive: false
      })
    }
    if (root.hasActiveSession && root.activeStartEpoch > 0) {
      var sF = root._epochToHourFrac(root.activeStartEpoch)
      var endEp = root.activeEndEpoch > root.activeStartEpoch ? root.activeEndEpoch : (Date.now() / 1000.0)
      var eF = Math.max(sF + 0.08, Math.min(24.0, root._epochToHourFrac(endEp)))
      arr.push({
        categoryName: root.activeCategoryName || "",
        goal: root.activeGoal || "",
        color: root.activeColor || "#ffffff",
        startEpoch: root.activeStartEpoch,
        endEpoch: endEp,
        startH: sF,
        endH: eF,
        isLive: true
      })
    }
    return arr
  }

  readonly property int firstHour: {
    var minH = Math.floor(nowHourFrac)
    for (var i = 0; i < combinedBlocks.length; i++) {
      minH = Math.min(minH, Math.floor(combinedBlocks[i].startH))
    }
    return Math.max(0, Math.min(22, minH - (combinedBlocks.length === 0 ? 1 : 0)))
  }

  readonly property int lastHour: {
    var maxH = Math.ceil(nowHourFrac + 0.02)
    for (var i = 0; i < combinedBlocks.length; i++) {
      maxH = Math.max(maxH, Math.ceil(combinedBlocks[i].endH + 0.02))
    }
    return Math.max(firstHour + 2, Math.min(24, maxH))
  }

  readonly property int spanHours: Math.max(1, lastHour - firstHour)
  readonly property real gutterW: 46
  readonly property real plotTop: 10

  implicitHeight: spanHours * hourHeight + 20

  function yForHour(h) {
    var clamped = Math.max(firstHour, Math.min(lastHour, h))
    return plotTop + (clamped - firstHour) * hourHeight
  }

  // Every-hour grid lines & labels
  Repeater {
    model: root.spanHours + 1
    delegate: Item {
      readonly property int hr: root.firstHour + index
      y: root.yForHour(hr)
      width: root.width
      height: 1

      Text {
        textFormat: Text.PlainText
        x: 0
        y: -6
        width: root.gutterW - 8
        horizontalAlignment: Text.AlignRight
        text: (hr < 10 ? "0" + hr : String(hr)) + ":00"
        font.family: "Monospace"
        font.pixelSize: 10
        color: root.tokens.faint || "#555555"
      }

      Rectangle {
        x: root.gutterW
        width: Math.max(0, root.width - root.gutterW)
        height: 1
        color: root.tokens.line || Qt.rgba(1, 1, 1, 0.06)
      }
    }
  }

  // Session blocks
  Repeater {
    model: root.combinedBlocks.length
    delegate: Rectangle {
      readonly property var blk: root.combinedBlocks[index]
      readonly property real topY: root.yForHour(blk.startH) + 1
      readonly property real blkH: Math.max(18, root.yForHour(blk.endH) - root.yForHour(blk.startH) - 2)
      x: root.gutterW + 8
      y: topY
      width: Math.max(24, root.width - root.gutterW - 8)
      height: blkH
      radius: Math.min(7, Math.max(4, blkH * 0.2))
      color: root.monochromeBlocks
        ? Theme.withAlpha(root.tokens.ink || "#ffffff", blk.isLive ? 0.16 : 0.07)
        : Theme.withAlpha(blk.color || "#4c8df0", blk.isLive ? 0.22 : 0.12)
      border.width: blk.isLive ? 1 : (root.monochromeBlocks ? 0 : 1)
      border.color: root.monochromeBlocks
        ? Theme.withAlpha(root.tokens.ink || "#ffffff", blk.isLive ? 0.40 : 0.0)
        : Theme.withAlpha(blk.color || "#4c8df0", blk.isLive ? 0.65 : 0.35)
      clip: true

      Column {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: (blk.goal && blk.goal !== blk.categoryName)
            ? (blk.categoryName + " · " + blk.goal)
            : (blk.goal || blk.categoryName)
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.Medium
          color: root.tokens.ink || "#ffffff"
        }

        Text {
          textFormat: Text.PlainText
          visible: parent.parent.height > 34
          text: Theme.formatHM(blk.startEpoch) + " – " + Theme.formatHM(blk.endEpoch)
          font.family: "Monospace"
          font.pixelSize: 10
          color: root.tokens.muted || "#888888"
        }
      }
    }
  }

  // Current time pill in left gutter (matching DetailView.swift:231-235)
  Rectangle {
    visible: root.nowHourFrac >= root.firstHour && root.nowHourFrac <= root.lastHour
    x: 0
    y: root.yForHour(root.nowHourFrac) - 9
    width: root.gutterW - 6
    height: 18
    radius: 5
    color: root.tokens.primaryBg || "#ffffff"

    Text {
      textFormat: Text.PlainText
      anchors.centerIn: parent
      text: root.nowLabel
      font.family: "Monospace"
      font.pixelSize: 10
      font.weight: Font.DemiBold
      color: root.tokens.primaryInk || "#000000"
    }
  }
}
