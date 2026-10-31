import QtQuick
import "../Theme.js" as Theme

// Hover/click slide-out detail panel attached to any of the 5 on-screen focus views.
// Matches DetailView.swift: FOCUS/PAUSED eyebrow, Capsule category pill, 20px goal,
// 60px hero clock, start -> plannedEnd (with live paused time), monochrome/accent progress line,
// 38px Pause/Resume + Finish buttons, always-visible 3-state To-do list, scrollable Notes editor,
// live Today total (+elapsed & +1 session) + DayStrip/DayColumn, and two-tone Up next break.
Item {
  id: root

  property var service: null
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"
  property bool drawerMode: false
  // -1: 4 rounded corners; 1: flat left screen edge; 0: flat right screen edge
  property int edgeSide: -1
  property real maxCardHeight: 760
  readonly property bool editingNote: noteField.activeFocus
  property bool pointerInside: cardHover.hovered
  property bool confirmCancel: false

  Timer {
    id: cancelResetTimer
    interval: 4000
    repeat: false
    onTriggered: root.confirmCancel = false
  }

  readonly property int cornerR: drawerMode ? 0 : 22

  width: drawerMode ? 380 : 360
  implicitHeight: drawerMode ? parent.height : Math.min(maxCardHeight, contentCol.implicitHeight + 36)
  height: drawerMode ? parent.height : implicitHeight
  clip: true

  // Edge-aware glass background (slices flat on the screen-snapped edge)
  Rectangle {
    x: (!root.drawerMode && root.edgeSide === 1) ? -root.cornerR : 0
    y: 0
    width: parent.width + ((!root.drawerMode && root.edgeSide >= 0) ? root.cornerR : 0)
    height: parent.height
    radius: root.cornerR
    color: root.tokens.popup || Qt.rgba(16 / 255, 16 / 255, 19 / 255, 0.97)
    border.width: 1
    border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)
  }

  HoverHandler {
    id: cardHover
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: function(mouse) {
      if (noteField.activeFocus) {
        var np = noteBox.mapToItem(root, 0, 0)
        if (mouse.x < np.x || mouse.x > np.x + noteBox.width || mouse.y < np.y || mouse.y > np.y + noteBox.height) {
          noteField.focus = false
        }
      }
      mouse.accepted = true
    }
  }

  readonly property var activeCat: service ? service.activeCategory : null
  readonly property var sessionTodos: service && service.sessionTodos ? service.sessionTodos : []
  readonly property int doneSessionTodos: {
    var d = 0
    for (var i = 0; i < sessionTodos.length; i++) {
      if (Number(sessionTodos[i].state) === 2) d++
    }
    return d
  }

  Connections {
    target: root.service
    function onSessionIdChanged() {
      if (!noteField.activeFocus && root.service) {
        noteField.text = root.service.sessionNote || ""
      }
    }
    function onSessionNoteChanged() {
      if (!noteField.activeFocus && root.service && noteField.text !== root.service.sessionNote) {
        noteField.text = root.service.sessionNote || ""
      }
    }
  }

  Component.onCompleted: {
    if (service) noteField.text = service.sessionNote || ""
  }

  Flickable {
    anchors.fill: parent
    anchors.margins: 18
    contentWidth: width
    contentHeight: contentCol.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: contentCol
      width: parent.width
      spacing: 13

      // Eyebrow + Capsule Category Pill
      Item {
        width: parent.width
        height: 26

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.service && root.service.phase === "paused"
            ? Theme.t(root.lang, "DURAKLATILDI", "PAUSED")
            : Theme.t(root.lang, "ODAK", "FOCUS")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 1.4
          color: root.tokens.muted || "#888888"
        }

        Rectangle {
          visible: !!root.activeCat
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: catPillRow.implicitWidth + 16
          height: 24
          radius: 12
          color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.06)
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.09)

          Row {
            id: catPillRow
            anchors.centerIn: parent
            spacing: 7

            CategorySwatch {
              anchors.verticalCenter: parent.verticalCenter
              swatchSize: 14
              swatchColor: root.activeCat ? root.activeCat.color : "#4c8df0"
              emoji: root.activeCat ? (root.activeCat.emoji || "") : ""
              iconName: root.activeCat ? (root.activeCat.icon || "") : ""
              iconColor: root.activeCat ? (root.activeCat.iconColor || "") : ""
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: root.activeCat ? root.activeCat.name : ""
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }
          }
        }
      }

      // Goal + clock with time span beside it
      Column {
        width: parent.width
        spacing: 4

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: {
            if (!root.service) return ""
            if (root.service.sessionGoal && root.service.sessionGoal.length > 0) return root.service.sessionGoal
            return root.activeCat ? root.activeCat.name : ""
          }
          wrapMode: Text.WordWrap
          maximumLineCount: 2
          elide: Text.ElideRight
          font.family: root.fontFamily
          font.pixelSize: 15
          font.weight: Font.DemiBold
          color: root.tokens.ink || "#ffffff"
        }

        Row {
        width: parent.width
        spacing: 12

        Text {
          textFormat: Text.PlainText
          id: heroClock
          text: root.service ? root.service.clockText : "00:00"
          font.family: "Monospace"
          font.pixelSize: 36
          font.weight: Font.Light
          color: root.tokens.ink || "#ffffff"
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width - heroClock.width - 12
          anchors.verticalCenter: parent.verticalCenter
          wrapMode: Text.WordWrap
          text: {
            if (!root.service) return ""
            var sHM = Theme.formatHM(root.service.sessionStart)
            if (root.service.workMinutes <= 0) {
              return Theme.t(
                root.lang,
                "Başlangıç " + sHM + " · serbest · 50. dakikada mola hatırlatılır",
                "Started " + sHM + " · free · break reminder at 50 min"
              )
            }
            var endEp = root.service.plannedEndEpoch > 0
              ? root.service.plannedEndEpoch
              : (root.service.sessionStart + root.service.workMinutes * 60)
            return sHM + " → " + Theme.formatHM(endEp) + " · " + root.service.workMinutes + " " + Theme.t(root.lang, "dk", "min")
          }
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.tokens.muted || "#888888"
        }
        }
      }

      // Progress line (monochrome white in Classic, theme accent in Omarchy)
      Rectangle {
        width: parent.width
        height: 4
        radius: 2
        color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.08)

        Rectangle {
          width: Math.max(4, parent.width * (root.service ? root.service.progress : 0))
          height: parent.height
          radius: 2
          color: root.tokens.primaryBg || "#ffffff"
        }
      }

      // Pause/Resume + Finish controls (38px tall)
      Row {
        width: parent.width
        spacing: 8

        Rectangle {
          width: (parent.width - 8) / 2
          height: 38
          radius: 11
          scale: pauseArea.pressed ? 0.98 : 1.0
          color: pauseArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
          border.width: 1
          border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.14)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: root.service && root.service.phase === "paused"
              ? Theme.t(root.lang, "Devam et", "Resume")
              : Theme.t(root.lang, "Duraklat", "Pause")
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.tokens.ink || "#ffffff"
          }

          MouseArea {
            id: pauseArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.togglePause()
          }
        }

        Rectangle {
          width: (parent.width - 8) / 2
          height: 38
          radius: 11
          scale: finishArea.pressed ? 0.98 : 1.0
          color: finishArea.containsMouse
            ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.88)
            : (root.tokens.primaryBg || "#ffffff")

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: Theme.t(root.lang, "Oturumu bitir", "Finish session")
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: root.tokens.primaryInk || "#0a0a0c"
          }

          MouseArea {
            id: finishArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.finishSession()
          }
        }
      }

      // Close & save without break + 2-step Cancel without saving
      Item {
        width: parent.width
        height: 30

        Row {
          visible: !root.confirmCancel
          anchors.fill: parent
          spacing: 8

          Rectangle {
            width: Math.round((parent.width - 8) * 0.52)
            height: parent.height
            radius: 8
            color: closeNoBreakArea.containsMouse
              ? (root.tokens.raised || "#2b2b33")
              : Theme.withAlpha(root.tokens.ink || "#ffffff", 0.04)
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.10)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - 8
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: Theme.t(root.lang, "Molasız kapat (kaydet)", "Close & save (no break)")
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.Medium
              color: root.tokens.secondary || "#cccccc"
            }

            MouseArea {
              id: closeNoBreakArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service) root.service.closeSessionWithoutBreak()
            }
          }

          Rectangle {
            width: parent.width - 8 - Math.round((parent.width - 8) * 0.52)
            height: parent.height
            radius: 8
            color: cancelStep1Area.containsMouse
              ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.12)
              : "transparent"
            border.width: 1
            border.color: cancelStep1Area.containsMouse
              ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.35)
              : (root.tokens.line || Qt.rgba(1, 1, 1, 0.07))

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              width: parent.width - 8
              horizontalAlignment: Text.AlignHCenter
              elide: Text.ElideRight
              text: Theme.t(root.lang, "İptal et (kaydetme)", "Cancel (don't save)")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: cancelStep1Area.containsMouse
                ? (root.tokens.danger || "#e06458")
                : (root.tokens.muted || "#888888")
            }

            MouseArea {
              id: cancelStep1Area
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.confirmCancel = true
                cancelResetTimer.restart()
              }
            }
          }
        }

        Row {
          visible: root.confirmCancel
          anchors.fill: parent
          spacing: 8

          Rectangle {
            width: Math.round((parent.width - 8) * 0.65)
            height: parent.height
            radius: 8
            color: cancelConfirmArea.containsMouse
              ? (root.tokens.danger || "#e06458")
              : Theme.withAlpha(root.tokens.danger || "#e06458", 0.22)
            border.width: 1
            border.color: root.tokens.danger || "#e06458"

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: Theme.t(root.lang, "Kaydetmeden iptal et", "Discard without saving")
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              color: cancelConfirmArea.containsMouse ? "#ffffff" : (root.tokens.danger || "#e06458")
            }

            MouseArea {
              id: cancelConfirmArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                cancelResetTimer.stop()
                root.confirmCancel = false
                if (root.service) root.service.cancelSession()
              }
            }
          }

          Rectangle {
            width: parent.width - 8 - Math.round((parent.width - 8) * 0.65)
            height: parent.height
            radius: 8
            color: cancelAbortArea.containsMouse
              ? (root.tokens.raised || "#2b2b33")
              : (root.tokens.card2 || "#1f1f25")
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.10)

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: Theme.t(root.lang, "Vazgeç", "Keep")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.secondary || "#bbbbbb"
            }

            MouseArea {
              id: cancelAbortArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                cancelResetTimer.stop()
                root.confirmCancel = false
              }
            }
          }
        }
      }

      // Divider 1
      Rectangle {
        width: parent.width
        height: 1
        color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
      }

      // Locked session To-do list (always visible with empty-state fallback)
      Column {
        width: parent.width
        spacing: 8

        Item {
          width: parent.width
          height: 16

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            text: Theme.t(root.lang, "YAPILACAKLAR", "TO-DO")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.2
            color: root.tokens.muted || "#888888"
          }

          Text {
            textFormat: Text.PlainText
            visible: root.sessionTodos.length > 0
            anchors.right: parent.right
            text: root.doneSessionTodos + "/" + root.sessionTodos.length
            font.family: "Monospace"
            font.pixelSize: 12
            color: root.tokens.muted || "#888888"
          }
        }

        Text {
          textFormat: Text.PlainText
          visible: root.sessionTodos.length === 0
          width: parent.width
          text: Theme.t(root.lang, "Bu oturum için liste yok.", "No list for this session.")
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.tokens.faint || "#666666"
        }

        Column {
          visible: root.sessionTodos.length > 0
          width: parent.width
          spacing: 3

          Repeater {
            model: root.sessionTodos.length
            delegate: Rectangle {
              id: tdRowRect
              readonly property var td: root.sessionTodos[index]
              readonly property int st: Number(td.state) || 0
              readonly property int prio: Number(td.priority) || 1
              readonly property string dueTimeStr: String(td.dueTime || "")
              readonly property bool hasTodoist: (td.todoistId || "") !== ""
              readonly property bool tdDone: !!td.todoistDone
              width: contentCol.width
              height: Math.max(40, tdTextCol.implicitHeight + 14)
              radius: 10
              color: st === 1
                ? Theme.withAlpha(root.tokens.ink || "#ffffff", 0.07)
                : "transparent"
              border.width: st === 1 ? 1 : 0
              border.color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.24)

              // Clicking row text sets non-done tasks to Doing (placed behind interactive buttons)
              MouseArea {
                anchors.left: parent.left
                anchors.leftMargin: 40
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                cursorShape: tdRowRect.st !== 2 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                  if (root.service && tdRowRect.st !== 2) {
                    root.service.setTodoStateExplicit(tdRowRect.td.id, 1)
                  }
                }
              }

              Row {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 10

                Rectangle {
                  width: 28
                  height: 28
                  radius: 8
                  color: Theme.withAlpha(root.tokens.ink || "#ffffff", emojiBtnArea.containsMouse ? 0.13 : 0.06)

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: Theme.todoEmoji(tdRowRect.st)
                    font.pixelSize: 15
                  }

                  MouseArea {
                    id: emojiBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.cycleTodoState(tdRowRect.td.id)
                  }
                }

                Column {
                  id: tdTextCol
                  width: parent.width - 42
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 4

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: tdRowRect.td.title || ""
                    wrapMode: Text.WordWrap
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: tdRowRect.st === 1 ? Font.Medium : Font.Normal
                    color: tdRowRect.st === 2
                      ? (root.tokens.faint || "#666666")
                      : (root.tokens.ink || "#ffffff")
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: (tdRowRect.td.detail || "").length > 0
                    width: parent.width
                    text: tdRowRect.td.detail || ""
                    wrapMode: Text.WordWrap
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: tdRowRect.st === 2
                      ? (root.tokens.faint || "#555555")
                      : (root.tokens.muted || "#888888")
                  }

                  // Priority / dueTime pills + independent Todoist completion action (does not end or close the session)
                  Flow {
                    visible: tdRowRect.prio > 1 || tdRowRect.dueTimeStr !== "" || tdRowRect.hasTodoist
                    width: parent.width
                    spacing: 6

                    Rectangle {
                      visible: tdRowRect.prio > 1
                      width: dcPrioTxt.implicitWidth + 10
                      height: 20
                      radius: 5
                      color: Theme.withAlpha(Theme.priorityColor(tdRowRect.prio, "#888888"), 0.16)
                      border.width: 1
                      border.color: Theme.withAlpha(Theme.priorityColor(tdRowRect.prio, "#888888"), 0.42)

                      Text {
                        textFormat: Text.PlainText
                        id: dcPrioTxt
                        anchors.centerIn: parent
                        text: Theme.priorityLabel(tdRowRect.prio)
                        font.family: "Monospace"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.priorityColor(tdRowRect.prio, "#888888")
                      }
                    }

                    Rectangle {
                      visible: tdRowRect.dueTimeStr !== ""
                      width: dcTimeTxt.implicitWidth + 10
                      height: 20
                      radius: 5
                      color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.06)
                      border.width: 1
                      border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.10)

                      Text {
                        textFormat: Text.PlainText
                        id: dcTimeTxt
                        anchors.centerIn: parent
                        text: tdRowRect.dueTimeStr
                        font.family: "Monospace"
                        font.pixelSize: 10
                        color: root.tokens.secondary || "#bbbbbb"
                      }
                    }

                    Rectangle {
                      visible: tdRowRect.hasTodoist
                      width: sessTdOriginTxt.implicitWidth + 14
                      height: 22
                      radius: 6
                      color: tdRowRect.tdDone
                        ? Theme.withAlpha("#4fc08d", sessTdCompleteArea.containsMouse ? 0.28 : 0.16)
                        : Theme.withAlpha("#e44332", sessTdCompleteArea.containsMouse ? 0.26 : 0.13)
                      border.width: 1
                      border.color: tdRowRect.tdDone
                        ? Theme.withAlpha("#4fc08d", 0.50)
                        : Theme.withAlpha("#e44332", sessTdCompleteArea.containsMouse ? 0.65 : 0.38)

                      Text {
                        textFormat: Text.PlainText
                        id: sessTdOriginTxt
                        anchors.centerIn: parent
                        text: tdRowRect.tdDone
                          ? Theme.t(root.lang, "✓ Todoist'te tamamlandı", "✓ Completed in Todoist")
                          : Theme.t(root.lang, "○ Todoist'te tamamla", "○ Complete in Todoist")
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.Medium
                        color: tdRowRect.tdDone ? "#4fc08d" : "#e44332"
                      }

                      MouseArea {
                        id: sessTdCompleteArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.service) {
                            root.service.setTodoistTaskCompleted(
                              tdRowRect.td.todoistId,
                              !tdRowRect.tdDone,
                              tdRowRect.td.id
                            )
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // Divider 2
      Rectangle {
        width: parent.width
        height: 1
        color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
      }

      // Live Notes editor (clipped & scrollable between 78..154px)
      Column {
        width: parent.width
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: Theme.t(root.lang, "NOTLAR", "NOTES")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
          color: root.tokens.muted || "#888888"
        }

        Rectangle {
          id: noteBox
          width: parent.width
          height: Math.max(78, Math.min(154, noteField.contentHeight + 18))
          radius: 12
          color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.04)
          border.width: 1
          border.color: noteField.activeFocus
            ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.28))
            : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))
          clip: true

          Flickable {
            id: noteFlick
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: width
            contentHeight: Math.max(height, noteField.contentHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Text {
              textFormat: Text.PlainText
              x: 2
              y: 1
              visible: noteField.text.length === 0
              text: Theme.t(root.lang, "Aklına geleni yaz…", "Write down whatever comes to mind…")
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.tokens.faint || "#666666"
            }

            TextEdit {
              textFormat: TextEdit.PlainText
              id: noteField
              width: noteFlick.width
              height: Math.max(noteFlick.height, contentHeight)
              wrapMode: TextEdit.Wrap
              font.family: root.fontFamily
              font.pixelSize: 13
              color: root.tokens.ink || "#ffffff"
              selectByMouse: true
              onCursorRectangleChanged: {
                if (cursorRectangle.y < noteFlick.contentY) {
                  noteFlick.contentY = cursorRectangle.y
                } else if (cursorRectangle.y + cursorRectangle.height > noteFlick.contentY + noteFlick.height) {
                  noteFlick.contentY = cursorRectangle.y + cursorRectangle.height - noteFlick.height
                }
              }
              onTextChanged: {
                if (activeFocus && root.service) {
                  root.service.updateSessionNote(text)
                }
              }
              Keys.onEscapePressed: focus = false
            }
          }
        }
      }

      // Divider 3
      Rectangle {
        width: parent.width
        height: 1
        color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
      }

      // Today summary (completed + live elapsed minutes, completed + 1 session) + timeline
      Column {
        width: parent.width
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: Theme.t(root.lang, "BUGÜN", "TODAY")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          font.letterSpacing: 1.2
          color: root.tokens.muted || "#888888"
        }

        Item {
          width: parent.width
          height: 26

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.baseline: parent.bottom
            text: {
              var td = root.service && root.service.todayData ? root.service.todayData : null
              var doneMins = td ? (td.focusMinutes || 0) : 0
              var liveMins = root.service ? Math.floor((root.service.elapsedSeconds || 0) / 60) : 0
              return Theme.formatMinutes(doneMins + liveMins, root.lang)
            }
            font.family: root.fontFamily
            font.pixelSize: 20
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.baseline: parent.bottom
            text: {
              var td = root.service && root.service.todayData ? root.service.todayData : null
              var sc = (td ? (td.sessionsCount || 0) : 0) + 1
              return sc + " " + Theme.t(root.lang, "oturum", sc === 1 ? "session" : "sessions")
            }
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.muted || "#888888"
          }
        }

        DayStrip {
          visible: !root.drawerMode
          width: parent.width
          sessions: root.service && root.service.todayData ? (root.service.todayData.timeline || []) : []
          hasActiveSession: !!root.service && (root.service.phase === "focus" || root.service.phase === "paused")
          activeSessionId: root.service ? root.service.sessionId : 0
          activeStartEpoch: root.service ? root.service.sessionStart : 0
          tokens: root.tokens
        }

        DayColumn {
          visible: root.drawerMode
          width: parent.width
          sessions: root.service && root.service.todayData ? (root.service.todayData.timeline || []) : []
          hasActiveSession: !!root.service && (root.service.phase === "focus" || root.service.phase === "paused")
          activeSessionId: root.service ? root.service.sessionId : 0
          activeCategoryName: root.activeCat ? root.activeCat.name : ""
          activeColor: root.activeCat ? root.activeCat.color : "#ffffff"
          activeGoal: root.service ? root.service.sessionGoal : ""
          activeStartEpoch: root.service ? root.service.sessionStart : 0
          activeEndEpoch: root.service && root.service.plannedEndEpoch > 0 ? root.service.plannedEndEpoch : (Date.now() / 1000.0)
          monochromeBlocks: true
          tokens: root.tokens
          lang: root.lang
          fontFamily: root.fontFamily
        }
      }

      // Two-tone Up next break hint (DetailView.swift:84-88)
      Row {
        spacing: 6

        Text {
          textFormat: Text.PlainText
          text: Theme.t(root.lang, "Sırada", "Up next")
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.tokens.muted || "#888888"
        }

        Text {
          textFormat: Text.PlainText
          text: {
            var rmin = root.service ? (root.service.restMinutes || 10) : 10
            return rmin + " " + Theme.t(root.lang, "dakika mola", "minute break")
          }
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.tokens.ink || "#ffffff"
        }
      }
    }
  }
}
