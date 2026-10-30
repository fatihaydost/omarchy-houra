import QtQuick
import "../Theme.js" as Theme

// Slide-over right drawer in Statistics showing a single day's unfiltered breakdown,
// stacked category bar, chronological sessions, and "Open in Sessions" jump.
Item {
  id: root

  property var dayData: null
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"

  signal closeRequested()
  signal openInSessions(string dayIso)
  signal deleteSession(int sessionId)
  signal stepDayRequested(int delta)

  property int confirmDeleteId: 0
  property int kbIndex: -1
  onDayDataChanged: {
    confirmDeleteId = 0
    kbIndex = (daySessions && daySessions.length > 0) ? 0 : -1
  }

  function dismissConfirm() {
    if (confirmDeleteId !== 0) {
      drawerDeleteTimer.stop()
      confirmDeleteId = 0
      return true
    }
    return false
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(drawerFlick.contentItem, 0, 0)
    var top = pt.y - 12
    var bot = pt.y + item.height + 12
    if (top < drawerFlick.contentY) {
      drawerFlick.contentY = Math.max(0, top)
    } else if (bot > drawerFlick.contentY + drawerFlick.height) {
      drawerFlick.contentY = Math.min(Math.max(0, drawerFlick.contentHeight - drawerFlick.height), bot - drawerFlick.height)
    }
  }

  function handleKey(event) {
    if (!dayData) return false
    var k = event.key
    var count = daySessions ? daySessions.length : 0
    if (k === Qt.Key_Down) {
      if (count > 0) kbIndex = Math.min(count - 1, kbIndex < 0 ? 0 : kbIndex + 1)
      return true
    }
    if (k === Qt.Key_Up) {
      if (count > 0) kbIndex = Math.max(0, kbIndex <= 0 ? 0 : kbIndex - 1)
      return true
    }
    if (k === Qt.Key_Left) {
      stepDayRequested(-1)
      return true
    }
    if (k === Qt.Key_Right) {
      stepDayRequested(1)
      return true
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (dayData && count > 0) openInSessions(dayData.day)
      return true
    }
    if (k === Qt.Key_Delete || k === Qt.Key_Backspace) {
      let sid = (count > 0 && kbIndex >= 0 && kbIndex < count) ? Number(daySessions[kbIndex].id) : 0
      if (sid > 0) {
        if (confirmDeleteId !== sid) {
          confirmDeleteId = sid
          drawerDeleteTimer.restart()
        } else {
          drawerDeleteTimer.stop()
          confirmDeleteId = 0
          deleteSession(sid)
        }
      }
      return true
    }
    return false
  }

  Timer {
    id: drawerDeleteTimer
    interval: 3500
    repeat: false
    onTriggered: root.confirmDeleteId = 0
  }

  anchors.fill: parent
  visible: dayData !== null
  z: 35

  readonly property int dayTotalMins: {
    if (!dayData) return 0
    if (dayData.allTotalMinutes !== undefined) return Number(dayData.allTotalMinutes) || 0
    return Number(dayData.totalMinutes) || 0
  }

  readonly property var dayCategories: {
    if (!dayData) return []
    return dayData.allByCategory || dayData.byCategory || []
  }

  readonly property var daySessions: {
    if (!dayData) return []
    return dayData.allSessions || dayData.sessions || []
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.38)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeRequested()
    }
  }

  Rectangle {
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Math.min(392, parent.width - 40)
    color: root.tokens.card || "#16161a"
    border.width: 1
    border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

    MouseArea {
      anchors.fill: parent
      onClicked: function(mouse) { mouse.accepted = true }
    }

    Column {
      anchors.fill: parent
      anchors.margins: 20
      spacing: 14

      // Header + close
      Item {
        width: parent.width
        height: 28

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.dayData ? Theme.formatDayHeading(root.dayData.day, root.lang) : ""
          font.family: root.fontFamily
          font.pixelSize: 13
          font.weight: Font.DemiBold
          color: root.tokens.ink || "#ffffff"
        }

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 26
          height: 26
          radius: 7
          color: root.tokens.card2 || "#1f1f25"
          Text { anchors.centerIn: parent; text: "×"; font.pixelSize: 16; color: root.tokens.secondary || "#aaaaaa" }
          MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.closeRequested() }
        }
      }

      // Big day total
      Text {
        text: root.dayData
          ? (Theme.formatMinutes(root.dayTotalMins, root.lang) + " " + Theme.t(root.lang, "odak", "focused"))
          : ""
        font.family: root.fontFamily
        font.pixelSize: 24
        font.weight: Font.Light
        color: root.tokens.ink || "#ffffff"
      }

      // Stacked category bar
      Rectangle {
        visible: root.dayData !== null && root.dayTotalMins > 0
        width: parent.width
        height: 8
        radius: 4
        color: root.tokens.card2 || "#202026"
        clip: true

        Row {
          anchors.fill: parent
          Repeater {
            model: root.dayCategories.length
            delegate: Rectangle {
              readonly property var seg: root.dayCategories[index]
              readonly property real tot: Math.max(1, root.dayTotalMins)
              width: Math.max(2, parent.width * ((seg.minutes || 0) / tot))
              height: parent.height
              color: seg.color || "#4c8df0"
            }
          }
        }
      }

      // Category legend chips
      Flow {
        visible: root.dayCategories.length > 0
        width: parent.width
        spacing: 8

        Repeater {
          model: root.dayCategories.length
          delegate: Row {
            readonly property var seg: root.dayCategories[index]
            spacing: 5
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 8
              height: 8
              radius: 4
              color: seg.color || "#4c8df0"
            }
            Text {
              text: seg.categoryName + " · " + Theme.formatMinutesShort(seg.minutes || 0, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.secondary || "#bbbbbb"
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
      }

      // Sessions list
      Flickable {
        id: drawerFlick
        width: parent.width
        height: Math.max(120, parent.height - 236)
        contentWidth: width
        contentHeight: sessCol.implicitHeight
        clip: true

        Column {
          id: sessCol
          width: parent.width
          spacing: 8

          Text {
            visible: root.daySessions.length === 0
            text: Theme.t(root.lang, "Bu günde kayıtlı oturum yok.", "No recorded sessions on this day.")
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.muted || "#777777"
          }

          Repeater {
            model: root.daySessions.length
            delegate: Rectangle {
              id: drawerSessRow
              readonly property var s: root.daySessions[index]
              readonly property bool confirming: root.confirmDeleteId === Number(s.id)
              readonly property bool kbSelected: root.kbIndex === index
              onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(drawerSessRow)
              width: sessCol.width
              height: sInner.implicitHeight + 18
              radius: 9
              color: (drawerRowHover.hovered || kbSelected) ? (root.tokens.raised || "#25252c") : (root.tokens.card2 || "#1e1e24")
              border.width: kbSelected ? 1.5 : 1
              border.color: kbSelected
                ? (root.tokens.ink || "#ffffff")
                : (root.tokens.line || Qt.rgba(1, 1, 1, 0.07))

              HoverHandler { id: drawerRowHover }

              Column {
                id: sInner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 9
                spacing: 4

                Item {
                  width: parent.width
                  height: 20

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 7

                    CategorySwatch {
                      swatchSize: 18
                      swatchColor: s.color || "#4c8df0"
                      emoji: s.emoji || ""
                      iconName: s.icon || ""
                      iconColor: s.iconColor || ""
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: s.categoryName || ""
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      font.weight: Font.Medium
                      color: root.tokens.ink || "#ffffff"
                    }
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: {
                        var base = Theme.formatHM(s.start) + " – " + Theme.formatHM(s.end)
                        if (s.rhythmLabel) base += " · " + s.rhythmLabel
                        base += " · " + Theme.formatMinutesShort(s.focusMinutes || 0, root.lang)
                        return base
                      }
                      font.family: "Monospace"
                      font.pixelSize: 10
                      color: root.tokens.muted || "#888888"
                    }

                    Rectangle {
                      visible: drawerRowHover.hovered || confirming || drawerSessRow.kbSelected
                      anchors.verticalCenter: parent.verticalCenter
                      width: drawerDelLbl.implicitWidth + 10
                      height: 18
                      radius: 5
                      color: confirming
                        ? (drawerDelArea.containsMouse ? (root.tokens.danger || "#e06458") : Theme.withAlpha(root.tokens.danger || "#e06458", 0.24))
                        : (drawerDelArea.containsMouse ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.14) : (root.tokens.card || "#17171c"))
                      border.width: 1
                      border.color: confirming || drawerDelArea.containsMouse
                        ? (root.tokens.danger || "#e06458")
                        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.10))

                      Text {
                        id: drawerDelLbl
                        anchors.centerIn: parent
                        text: confirming
                          ? Theme.t(root.lang, "Sil?", "Sure?")
                          : Theme.t(root.lang, "Sil", "Del")
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        font.weight: confirming ? Font.DemiBold : Font.Normal
                        color: confirming
                          ? (drawerDelArea.containsMouse ? "#ffffff" : (root.tokens.danger || "#e06458"))
                          : (drawerDelArea.containsMouse ? (root.tokens.danger || "#e06458") : (root.tokens.muted || "#888888"))
                      }

                      MouseArea {
                        id: drawerDelArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          var sid = Number(s.id)
                          if (root.confirmDeleteId !== sid) {
                            root.confirmDeleteId = sid
                            drawerDeleteTimer.restart()
                          } else {
                            drawerDeleteTimer.stop()
                            root.confirmDeleteId = 0
                            root.deleteSession(sid)
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: (s.goal || "").length > 0 && s.goal !== s.categoryName
                  width: parent.width
                  text: s.goal || ""
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  color: root.tokens.secondary || "#cccccc"
                }

                Text {
                  visible: (Number(s.todosTotal) || 0) > 0
                  text: (s.todosDone || 0) + "/" + (s.todosTotal || 0) + " " + Theme.t(root.lang, "görev tamamlandı", "tasks completed")
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  color: root.tokens.muted || "#888888"
                }

                Text {
                  visible: (s.note || "").length > 0
                  width: parent.width
                  text: "“" + s.note + "”"
                  wrapMode: Text.WordWrap
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  font.italic: true
                  color: root.tokens.muted || "#888888"
                }
              }
            }
          }
        }
      }

      // Open in Sessions button
      Rectangle {
        visible: root.daySessions.length > 0
        width: parent.width
        height: 34
        radius: 8
        color: openArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
        border.width: 1
        border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.14)

        Text {
          anchors.centerIn: parent
          text: Theme.t(root.lang, "Oturumlar sayfasında aç →", "Open in Sessions →")
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.Medium
          color: root.tokens.ink || "#ffffff"
        }

        MouseArea {
          id: openArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.dayData) root.openInSessions(root.dayData.day)
        }
      }
    }
  }
}
