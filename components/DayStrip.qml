import QtQuick
import "../Theme.js" as Theme

// Compact horizontal 08:00..20:00 timeline strip used inside DetailCard (DetailView.swift:163-193):
// Renders completed sessions, live growing current session block, and live current-time cursor.
Item {
  id: root

  property var sessions: []
  property int activeSessionId: 0
  property real activeStartEpoch: 0
  property bool hasActiveSession: false
  property var tokens: ({})
  property int startHour: 8
  property int endHour: 20

  implicitHeight: 44
  height: 44

  readonly property real spanHours: Math.max(1, endHour - startHour)
  property real nowHourFrac: _computeNowFrac()

  function _computeNowFrac() {
    var d = new Date()
    return d.getHours() + d.getMinutes() / 60.0 + d.getSeconds() / 3600.0
  }

  function _epochToHourFrac(ep) {
    if (!ep || ep <= 0) return 0
    var d = new Date(Number(ep) * 1000)
    return d.getHours() + d.getMinutes() / 60.0 + d.getSeconds() / 3600.0
  }

  Timer {
    interval: 15000
    running: root.visible
    repeat: true
    onTriggered: root.nowHourFrac = root._computeNowFrac()
  }

  onVisibleChanged: {
    if (visible) nowHourFrac = _computeNowFrac()
  }

  Rectangle {
    id: track
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    height: 26
    radius: 7
    color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.05)
    clip: true

    // Completed sessions today
    Repeater {
      model: root.sessions ? root.sessions.length : 0
      delegate: Rectangle {
        readonly property var sess: root.sessions[index]
        readonly property bool isCompletedOther: !!sess.completed && Number(sess.id) !== root.activeSessionId
        readonly property real sH: Math.max(root.startHour, Math.min(root.endHour, Number(sess.startHourFrac) || 0))
        readonly property real eH: Math.max(sH, Math.min(root.endHour, Number(sess.endHourFrac) || 0))
        visible: isCompletedOther && eH > root.startHour && sH < root.endHour
        x: ((sH - root.startHour) / root.spanHours) * track.width
        y: 5
        width: Math.max(3, ((eH - sH) / root.spanHours) * track.width)
        height: 16
        radius: 4
        color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.45)
      }
    }

    // Live active session block (start -> now)
    Rectangle {
      readonly property real liveStartH: Math.max(root.startHour, Math.min(root.endHour, root._epochToHourFrac(root.activeStartEpoch)))
      readonly property real liveEndH: Math.max(liveStartH, Math.min(root.endHour, root.nowHourFrac))
      visible: root.hasActiveSession && root.nowHourFrac > root.startHour && liveStartH < root.endHour
      x: ((liveStartH - root.startHour) / root.spanHours) * track.width
      y: 5
      width: Math.max(3, ((liveEndH - liveStartH) / root.spanHours) * track.width)
      height: 16
      radius: 4
      color: Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.90)
    }

    // Current-time marker
    Rectangle {
      visible: root.nowHourFrac >= root.startHour && root.nowHourFrac <= root.endHour
      x: Math.round(((root.nowHourFrac - root.startHour) / root.spanHours) * track.width)
      y: 0
      width: 1.5
      height: track.height
      color: root.tokens.ink || "#ffffff"
    }
  }

  Item {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    height: 13

    Repeater {
      model: [8, 11, 14, 17, 20]
      delegate: Text {
        readonly property int hr: modelData
        x: hr === 8 ? 0 : (hr === 20 ? parent.width - implicitWidth : ((hr - root.startHour) / root.spanHours) * parent.width - implicitWidth / 2)
        text: (hr < 10 ? "0" + hr : String(hr))
        font.family: "Monospace"
        font.pixelSize: 10
        color: root.tokens.faint || "#666666"
      }
    }
  }
}
