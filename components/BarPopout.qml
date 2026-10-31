import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../Theme.js" as Theme

// Quick bar popout menu matching MenuBar.swift:
// - Idle: Today summary, Start session..., Repeat a recent session (top 5 or empty hint)
// - Focus/Paused: ● Category · Goal, remaining/elapsed + active todo, Pause/Resume, Finish session
// - Rest: Break countdown, Back to break, End break & new session...
// - Always: Show on screen (6 views + direct monitor pills when multi-monitor), Open panel..., Statistics..., Settings...
Item {
  id: root

  property QtObject bar: null
  property Item anchorItem: null
  property var hostWidget: null
  property var service: null
  property bool popoutSwitchClosing: false
  property bool confirmCancel: false
  property int kbIndex: 0
  property bool kbActive: false

  readonly property var styleOrder: ["tag", "strip", "capsule", "card", "ring", "none"]

  readonly property bool opened: panelController.open
  onOpenedChanged: {
    if (!opened) {
      confirmCancel = false
      popCancelResetTimer.stop()
      kbActive = false
    } else {
      kbIndex = 0
      kbActive = false
    }
  }

  readonly property var actionBundle: {
    var list = []
    var idxMap = ({})
    var ph = service ? service.phase : "idle"
    var pushAct = function(obj) {
      idxMap[obj.key] = list.length
      list.push(obj)
    }

    if (!service || ph === "idle") {
      pushAct({ key: "start", kind: "start" })
      var reps = (service && service.todayData && service.todayData.recentRepeats) ? service.todayData.recentRepeats : []
      for (var i = 0; i < reps.length; i++) {
        pushAct({ key: "rep:" + i, kind: "repeat", rep: reps[i] })
      }
    } else if (ph === "focus" || ph === "paused") {
      var stds = (service && service.sessionTodos) ? service.sessionTodos : []
      for (var t = 0; t < stds.length; t++) {
        pushAct({ key: "todo:" + stds[t].id, kind: "todo", td: stds[t] })
      }
      pushAct({ key: "pause", kind: "pause" })
      pushAct({ key: "finish", kind: "finish" })
      if (!confirmCancel) {
        pushAct({ key: "closeNoBreak", kind: "closeNoBreak" })
        pushAct({ key: "cancelAsk", kind: "cancelAsk" })
      } else {
        pushAct({ key: "cancelConfirm", kind: "cancelConfirm" })
        pushAct({ key: "cancelKeep", kind: "cancelKeep" })
      }
    } else if (ph === "rest") {
      pushAct({ key: "backToBreak", kind: "backToBreak" })
      pushAct({ key: "endBreakNew", kind: "endBreakNew" })
    }

    pushAct({ key: "nav:", kind: "nav", tab: "" })
    pushAct({ key: "nav:stats", kind: "nav", tab: "stats" })
    pushAct({ key: "nav:settings", kind: "nav", tab: "settings" })
    return { list: list, indexByKey: idxMap }
  }
  readonly property var actionItems: actionBundle.list
  readonly property var actionIndexByKey: actionBundle.indexByKey

  onActionItemsChanged: {
    if (actionItems.length === 0) kbIndex = 0
    else if (kbIndex >= actionItems.length) kbIndex = actionItems.length - 1
  }

  function isActionSelected(actKey) {
    return kbActive && actionIndexByKey[actKey] !== undefined && kbIndex === Number(actionIndexByKey[actKey])
  }

  function stepWidgetStyle(delta) {
    if (!service) return
    var cur = styleOrder.indexOf(service.widgetStyle)
    if (cur < 0) cur = 0
    var next = (cur + delta + styleOrder.length) % styleOrder.length
    service.setWidgetStyle(styleOrder[next])
  }

  function triggerAction(act, isSpace) {
    if (!act || !service) return
    if (act.kind === "start") {
      close()
      service.openNewSession(0, "")
    } else if (act.kind === "repeat" && act.rep) {
      close()
      service.quickStartSession(act.rep.categoryId, act.rep.goal, act.rep.workMin, act.rep.restMin)
    } else if (act.kind === "todo" && act.td) {
      if (isSpace) {
        service.cycleTodoState(act.td.id)
      } else {
        if (Number(act.td.state) !== 2) service.setTodoStateExplicit(act.td.id, 1)
        else service.cycleTodoState(act.td.id)
      }
    } else if (act.kind === "pause") {
      service.togglePause()
      close()
    } else if (act.kind === "finish") {
      close()
      service.finishSession()
    } else if (act.kind === "closeNoBreak") {
      close()
      service.closeSessionWithoutBreak()
    } else if (act.kind === "cancelAsk") {
      confirmCancel = true
      popCancelResetTimer.restart()
      if (actionIndexByKey["cancelConfirm"] !== undefined) {
        kbIndex = Number(actionIndexByKey["cancelConfirm"])
      }
    } else if (act.kind === "cancelConfirm") {
      popCancelResetTimer.stop()
      confirmCancel = false
      close()
      service.cancelSession()
    } else if (act.kind === "cancelKeep") {
      popCancelResetTimer.stop()
      confirmCancel = false
    } else if (act.kind === "backToBreak") {
      close()
      service.returnToBreak()
    } else if (act.kind === "endBreakNew") {
      close()
      service.endBreakAndStartNew()
    } else if (act.kind === "nav") {
      close()
      service.openMainPanel(act.tab)
    }
  }

  Timer {
    id: popCancelResetTimer
    interval: 4000
    repeat: false
    onTriggered: root.confirmCancel = false
  }
  readonly property string lang: service ? service.lang : "en"
  readonly property var tokens: service
    ? service.tokens
    : Theme.resolveTokens("omarchy", Commons.Color.background, Commons.Color.foreground, Commons.Color.accent, Commons.Color.urgent)

  function open() { panelController.show() }
  function close() { panelController.hide() }
  function toggle() { opened ? close() : open() }
  function closeForPopoutSwitch() {
    popoutSwitchClosing = true
    close()
    Qt.callLater(function() { popoutSwitchClosing = false })
  }

  PanelController {
    id: panelController
  }

  KeyboardPanel {
    id: popup
    anchorItem: root.anchorItem
    bar: root.bar
    owner: root.hostWidget || root
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: popup.fittedContentWidth(Style.space(314))
    contentHeight: popup.fittedContentHeight(menuCol.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.confirmCancel) {
          popCancelResetTimer.stop()
          root.confirmCancel = false
        } else {
          root.close()
        }
      }

      Keys.onPressed: function(event) {
        var k = event.key
        var mods = event.modifiers

        if ((mods & Qt.ControlModifier) && (k === Qt.Key_W || k === Qt.Key_Q)) {
          event.accepted = true
          root.close()
          return
        }
        if (!root.service) return

        var count = root.actionItems.length
        if (k === Qt.Key_Down || k === Qt.Key_Tab) {
          event.accepted = true
          if (count > 0) {
            root.kbIndex = root.kbActive ? ((root.kbIndex + 1) % count) : 0
            root.kbActive = true
          }
          return
        }
        if (k === Qt.Key_Up || k === Qt.Key_Backtab) {
          event.accepted = true
          if (count > 0) {
            root.kbIndex = root.kbActive ? ((root.kbIndex - 1 + count) % count) : 0
            root.kbActive = true
          }
          return
        }
        if (k === Qt.Key_Left) {
          event.accepted = true
          root.stepWidgetStyle(-1)
          return
        }
        if (k === Qt.Key_Right) {
          event.accepted = true
          root.stepWidgetStyle(1)
          return
        }
        if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && count > 0) {
          event.accepted = true
          root.kbActive = true
          var curAct = root.actionItems[Math.max(0, Math.min(count - 1, root.kbIndex))]
          root.triggerAction(curAct, k === Qt.Key_Space)
          return
        }
      }
    }

    // Scrolls only when the menu is taller than the space the popup gets (long task lists)
    Flickable {
      width: parent.width
      height: parent.height
      contentWidth: width
      contentHeight: menuCol.implicitHeight
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      clip: true

      Column {
        id: menuCol
        width: parent.width
        spacing: 8

        // --- PHASE HEADER & PRIMARY ACTIONS ---

        // 1. IDLE
        Column {
          visible: !root.service || root.service.phase === "idle"
          width: parent.width
          spacing: 8

          Column {
            width: parent.width
            spacing: 2

            Text {
              textFormat: Text.PlainText
              text: {
                var mins = root.service && root.service.todayData ? (root.service.todayData.focusMinutes || 0) : 0
                return Theme.t(root.lang, "Bugün ", "Today ") + Theme.formatMinutes(mins, root.lang) + Theme.t(root.lang, " odak", " focused")
              }
              font.family: Style.font.family
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: Commons.Color.popups.text
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var td = root.service && root.service.todayData ? root.service.todayData : null
                var sc = td ? (td.sessionsCount || 0) : 0
                var dn = td ? (td.doneTodos || 0) : 0
                var tt = td ? (td.totalTodos || 0) : 0
                return sc + " " + Theme.t(root.lang, "oturum", "sessions") + " · " + dn + " / " + tt + " " + Theme.t(root.lang, "görev", "tasks") + " 🥳"
              }
              font.family: Style.font.family
              font.pixelSize: 11
              color: Theme.withAlpha(Commons.Color.popups.text, 0.62)
            }
          }

          // Start session...
          Rectangle {
            readonly property bool kbSel: root.isActionSelected("start")
            width: parent.width
            height: 34
            radius: Math.max(6, Style.cornerRadius)
            color: (startHover.containsMouse || kbSel)
              ? Theme.withAlpha(Commons.Color.accent, 0.88)
              : Commons.Color.accent
            border.width: kbSel ? 1.5 : 0
            border.color: Commons.Color.popups.text

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              text: Theme.t(root.lang, "Oturum başlat…", "Start session…")
              font.family: Style.font.family
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.tokens.primaryInk
            }

            MouseArea {
              id: startHover
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.close()
                if (root.service) root.service.openNewSession(0, "")
              }
            }
          }

          // Repeat a recent session (top 5, always visible matching MenuBar.swift:73, 116)
          Column {
            id: repeatCol
            readonly property var repeats: root.service && root.service.todayData ? (root.service.todayData.recentRepeats || []) : []
            width: parent.width
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "SON OTURUMU TEKRARLA", "REPEAT A RECENT SESSION")
              font.family: Style.font.family
              font.pixelSize: 9
              font.weight: Font.DemiBold
              font.letterSpacing: 0.9
              color: Theme.withAlpha(Commons.Color.popups.text, 0.48)
            }

            Text {
              textFormat: Text.PlainText
              visible: repeatCol.repeats.length === 0
              text: Theme.t(root.lang, "Henüz oturum yok", "No sessions yet")
              font.family: Style.font.family
              font.pixelSize: 12
              color: Theme.withAlpha(Commons.Color.popups.text, 0.40)
            }

            Repeater {
              model: repeatCol.repeats.length
              delegate: Rectangle {
                readonly property var rep: repeatCol.repeats[index]
                readonly property bool kbSel: root.isActionSelected("rep:" + index)
                width: menuCol.width
                height: 28
                radius: 6
                color: (repHover.containsMouse || kbSel) ? Theme.withAlpha(Commons.Color.popups.text, 0.12) : "transparent"
                border.width: kbSel ? 1 : 0
                border.color: Theme.withAlpha(Commons.Color.popups.text, 0.55)

                Row {
                  anchors.fill: parent
                  anchors.leftMargin: 6
                  anchors.rightMargin: 6
                  spacing: 8

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 3
                    color: rep.color || "#4c8df0"
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: parent.width - 78
                    anchors.verticalCenter: parent.verticalCenter
                    text: rep.goal ? (rep.categoryName + " · " + rep.goal) : rep.categoryName
                    elide: Text.ElideRight
                    font.family: Style.font.family
                    font.pixelSize: 12
                    color: Commons.Color.popups.text
                  }

                  Text {
                    textFormat: Text.PlainText
                    width: 50
                    horizontalAlignment: Text.AlignRight
                    anchors.verticalCenter: parent.verticalCenter
                    text: "(" + (rep.rhythmLabel || Theme.formatRhythm(rep.workMin, rep.restMin, root.lang)) + ")"
                    font.family: "Monospace"
                    font.pixelSize: 10
                    color: Theme.withAlpha(Commons.Color.popups.text, 0.5)
                  }
                }

                MouseArea {
                  id: repHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.close()
                    if (root.service) {
                      root.service.quickStartSession(rep.categoryId, rep.goal, rep.workMin, rep.restMin)
                    }
                  }
                }
              }
            }
          }
        }

        // 2. FOCUS / PAUSED
        Column {
          visible: root.service && (root.service.phase === "focus" || root.service.phase === "paused")
          width: parent.width
          spacing: 8

          Column {
            width: parent.width
            spacing: 2

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: {
                if (!root.service) return ""
                var cname = root.service.activeCategory ? root.service.activeCategory.name : ""
                var g = root.service.sessionGoal || cname
                return "● " + cname + " · " + g
              }
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: Commons.Color.popups.text
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: {
                if (!root.service) return ""
                var base = root.service.workMinutes === 0
                  ? (Theme.t(root.lang, "serbest · ", "free · ") + root.service.clockText)
                  : (root.service.clockText + " " + Theme.t(root.lang, "kaldı", "left"))
                if (root.service.activeTodoTitle) {
                  base += " · " + Theme.t(root.lang, "şu an: ", "now: ") + root.service.activeTodoTitle
                }
                return base
              }
              elide: Text.ElideRight
              font.family: Style.font.family
              font.pixelSize: 12
              color: Theme.withAlpha(Commons.Color.popups.text, 0.65)
            }
          }

          // Attached session tasks with independent local emoji & Todoist completion buttons
          Column {
            id: popTasksCol
            readonly property var sTodos: root.service && root.service.sessionTodos ? root.service.sessionTodos : []
            visible: sTodos.length > 0
            width: parent.width
            spacing: 4

            Repeater {
              model: popTasksCol.sTodos.length
              delegate: Rectangle {
                id: popTdRow
                readonly property var td: popTasksCol.sTodos[index]
                readonly property int st: Number(td.state) || 0
                readonly property int prio: Number(td.priority) || 1
                readonly property string dueTimeStr: String(td.dueTime || "")
                readonly property bool hasTd: (td.todoistId || "") !== ""
                readonly property bool tdDone: !!td.todoistDone
                readonly property bool kbSel: root.isActionSelected("todo:" + td.id)
                width: menuCol.width
                height: 28
                radius: 6
                color: kbSel
                  ? Theme.withAlpha(Commons.Color.popups.text, 0.12)
                  : (st === 1
                    ? Theme.withAlpha(Commons.Color.popups.text, 0.08)
                    : Theme.withAlpha(Commons.Color.popups.text, 0.03))
                border.width: kbSel ? 1.5 : (st === 1 ? 1 : 0)
                border.color: kbSel
                  ? Theme.withAlpha(Commons.Color.popups.text, 0.65)
                  : Theme.withAlpha(Commons.Color.popups.text, 0.16)

                Rectangle {
                  id: popEmojiBtn
                  anchors.left: parent.left
                  anchors.leftMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  width: 22
                  height: 22
                  radius: 5
                  color: popEmojiArea.containsMouse
                    ? Theme.withAlpha(Commons.Color.popups.text, 0.14)
                    : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    text: Theme.todoEmoji(popTdRow.st)
                    font.pixelSize: 13
                  }

                  MouseArea {
                    id: popEmojiArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.cycleTodoState(popTdRow.td.id)
                  }
                }

                Rectangle {
                  id: popTdPill
                  visible: popTdRow.hasTd
                  anchors.right: parent.right
                  anchors.rightMargin: 4
                  anchors.verticalCenter: parent.verticalCenter
                  width: visible ? (popTdPillTxt.implicitWidth + 12) : 0
                  height: 20
                  radius: 5
                  color: popTdRow.tdDone
                    ? Theme.withAlpha("#4fc08d", popTdPillArea.containsMouse ? 0.28 : 0.16)
                    : Theme.withAlpha("#e44332", popTdPillArea.containsMouse ? 0.26 : 0.14)
                  border.width: 1
                  border.color: popTdRow.tdDone
                    ? Theme.withAlpha("#4fc08d", 0.50)
                    : Theme.withAlpha("#e44332", popTdPillArea.containsMouse ? 0.65 : 0.38)

                  Text {
                    textFormat: Text.PlainText
                    id: popTdPillTxt
                    anchors.centerIn: parent
                    text: popTdRow.tdDone
                      ? Theme.t(root.lang, "✓ Todoist", "✓ Todoist")
                      : Theme.t(root.lang, "○ Todoist'te tamamla", "○ Complete in Todoist")
                    font.family: Style.font.family
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: popTdRow.tdDone ? "#4fc08d" : "#e44332"
                  }

                  MouseArea {
                    id: popTdPillArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.service) {
                        root.service.setTodoistTaskCompleted(
                          popTdRow.td.todoistId,
                          !popTdRow.tdDone,
                          popTdRow.td.id
                        )
                      }
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  id: popPrioLbl
                  visible: popTdRow.prio > 1
                  anchors.left: popEmojiBtn.right
                  anchors.leftMargin: 5
                  anchors.verticalCenter: parent.verticalCenter
                  text: Theme.priorityLabel(popTdRow.prio)
                  font.family: "Monospace"
                  font.pixelSize: 10
                  font.weight: Font.Bold
                  color: Theme.priorityColor(popTdRow.prio, "#888888")
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.left: popTdRow.prio > 1 ? popPrioLbl.right : popEmojiBtn.right
                  anchors.leftMargin: 6
                  anchors.right: popTdRow.hasTd ? popTdPill.left : parent.right
                  anchors.rightMargin: 6
                  anchors.verticalCenter: parent.verticalCenter
                  text: popTdRow.dueTimeStr !== ""
                    ? ((popTdRow.td.title || "") + " · " + popTdRow.dueTimeStr)
                    : (popTdRow.td.title || "")
                  elide: Text.ElideRight
                  font.family: Style.font.family
                  font.pixelSize: 12
                  font.weight: popTdRow.st === 1 ? Font.Medium : Font.Normal
                  color: popTdRow.st === 2
                    ? Theme.withAlpha(Commons.Color.popups.text, 0.45)
                    : Commons.Color.popups.text

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: popTdRow.st !== 2 ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                      if (root.service && popTdRow.st !== 2) {
                        root.service.setTodoStateExplicit(popTdRow.td.id, 1)
                      }
                    }
                  }
                }
              }
            }
          }

          Row {
            width: parent.width
            spacing: 8

            Rectangle {
              readonly property bool kbSel: root.isActionSelected("pause")
              width: (parent.width - 8) / 2
              height: 32
              radius: Math.max(6, Style.cornerRadius)
              color: (prArea.containsMouse || kbSel)
                ? Theme.withAlpha(Commons.Color.popups.text, 0.16)
                : Theme.withAlpha(Commons.Color.popups.text, 0.08)
              border.width: kbSel ? 1.5 : 0
              border.color: Theme.withAlpha(Commons.Color.popups.text, 0.65)

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: root.service && root.service.phase === "paused"
                  ? Theme.t(root.lang, "Devam et", "Resume")
                  : Theme.t(root.lang, "Duraklat", "Pause")
                font.family: Style.font.family
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Commons.Color.popups.text
              }

              MouseArea {
                id: prArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.service) root.service.togglePause()
                  root.close()
                }
              }
            }

            Rectangle {
              readonly property bool kbSel: root.isActionSelected("finish")
              width: (parent.width - 8) / 2
              height: 32
              radius: Math.max(6, Style.cornerRadius)
              color: (fnArea.containsMouse || kbSel)
                ? Theme.withAlpha(Commons.Color.accent, 0.88)
                : Commons.Color.accent
              border.width: kbSel ? 1.5 : 0
              border.color: Commons.Color.popups.text

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Oturumu bitir", "Finish session")
                font.family: Style.font.family
                font.pixelSize: 12
                font.weight: Font.DemiBold
                color: root.tokens.primaryInk
              }

              MouseArea {
                id: fnArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.close()
                  if (root.service) root.service.finishSession()
                }
              }
            }
          }

          // Close & save without break + 2-step Cancel without saving in bar popout
          Item {
            width: parent.width
            height: 28

            Row {
              visible: !root.confirmCancel
              anchors.fill: parent
              spacing: 6

              Rectangle {
                readonly property bool kbSel: root.isActionSelected("closeNoBreak")
                width: Math.round((parent.width - 6) * 0.53)
                height: parent.height
                radius: Math.max(6, Style.cornerRadius)
                color: (popCloseNoBreakArea.containsMouse || kbSel)
                  ? Theme.withAlpha(Commons.Color.popups.text, 0.14)
                  : Theme.withAlpha(Commons.Color.popups.text, 0.06)
                border.width: kbSel ? 1 : 0
                border.color: Theme.withAlpha(Commons.Color.popups.text, 0.60)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  width: parent.width - 8
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: Theme.t(root.lang, "Molasız kapat (kaydet)", "Close & save")
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.weight: Font.Medium
                  color: Theme.withAlpha(Commons.Color.popups.text, 0.85)
                }

                MouseArea {
                  id: popCloseNoBreakArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.close()
                    if (root.service) root.service.closeSessionWithoutBreak()
                  }
                }
              }

              Rectangle {
                readonly property bool kbSel: root.isActionSelected("cancelAsk")
                width: parent.width - 6 - Math.round((parent.width - 6) * 0.53)
                height: parent.height
                radius: Math.max(6, Style.cornerRadius)
                color: (popCancelArea.containsMouse || kbSel)
                  ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.14)
                  : "transparent"
                border.width: kbSel ? 1 : 0
                border.color: root.tokens.danger || "#e06458"

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  width: parent.width - 8
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: Theme.t(root.lang, "İptal et (kaydetme)", "Cancel (no save)")
                  font.family: Style.font.family
                  font.pixelSize: 11
                  color: (popCancelArea.containsMouse || parent.kbSel)
                    ? (root.tokens.danger || "#e06458")
                    : Theme.withAlpha(Commons.Color.popups.text, 0.55)
                }

                MouseArea {
                  id: popCancelArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.confirmCancel = true
                    popCancelResetTimer.restart()
                  }
                }
              }
            }

            Row {
              visible: root.confirmCancel
              anchors.fill: parent
              spacing: 6

              Rectangle {
                readonly property bool kbSel: root.isActionSelected("cancelConfirm")
                width: Math.round((parent.width - 6) * 0.66)
                height: parent.height
                radius: Math.max(6, Style.cornerRadius)
                color: (popConfirmArea.containsMouse || kbSel)
                  ? (root.tokens.danger || "#e06458")
                  : Theme.withAlpha(root.tokens.danger || "#e06458", 0.22)
                border.width: kbSel ? 1.5 : 1
                border.color: root.tokens.danger || "#e06458"

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: Theme.t(root.lang, "Kaydetmeden iptal et", "Discard session")
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.weight: Font.DemiBold
                  color: (popConfirmArea.containsMouse || parent.kbSel) ? "#ffffff" : (root.tokens.danger || "#e06458")
                }

                MouseArea {
                  id: popConfirmArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    popCancelResetTimer.stop()
                    root.confirmCancel = false
                    root.close()
                    if (root.service) root.service.cancelSession()
                  }
                }
              }

              Rectangle {
                readonly property bool kbSel: root.isActionSelected("cancelKeep")
                width: parent.width - 6 - Math.round((parent.width - 6) * 0.66)
                height: parent.height
                radius: Math.max(6, Style.cornerRadius)
                color: (popKeepArea.containsMouse || kbSel)
                  ? Theme.withAlpha(Commons.Color.popups.text, 0.14)
                  : Theme.withAlpha(Commons.Color.popups.text, 0.07)
                border.width: kbSel ? 1 : 0
                border.color: Theme.withAlpha(Commons.Color.popups.text, 0.55)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: Theme.t(root.lang, "Vazgeç", "Keep")
                  font.family: Style.font.family
                  font.pixelSize: 11
                  color: Commons.Color.popups.text
                }

                MouseArea {
                  id: popKeepArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    popCancelResetTimer.stop()
                    root.confirmCancel = false
                  }
                }
              }
            }
          }
        }

        // 3. REST
        Column {
          visible: root.service && root.service.phase === "rest"
          width: parent.width
          spacing: 8

          Column {
            width: parent.width
            spacing: 2

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "Mola · ", "Break · ") + (root.service ? root.service.restClockText : "00:00")
              font.family: Style.font.family
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: Commons.Color.popups.text
            }

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "Mola ekranından acil durumla döndün.", "You left the break screen early.")
              font.family: Style.font.family
              font.pixelSize: 12
              color: Theme.withAlpha(Commons.Color.popups.text, 0.62)
            }
          }

          Row {
            width: parent.width
            spacing: 8

            Rectangle {
              readonly property bool kbSel: root.isActionSelected("backToBreak")
              width: (parent.width - 8) / 2
              height: 32
              radius: Math.max(6, Style.cornerRadius)
              color: (bbArea.containsMouse || kbSel)
                ? Theme.withAlpha(Commons.Color.popups.text, 0.16)
                : Theme.withAlpha(Commons.Color.popups.text, 0.08)
              border.width: kbSel ? 1.5 : 0
              border.color: Theme.withAlpha(Commons.Color.popups.text, 0.65)

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Molaya geri dön", "Back to break")
                font.family: Style.font.family
                font.pixelSize: 12
                color: Commons.Color.popups.text
              }

              MouseArea {
                id: bbArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.close()
                  if (root.service) root.service.returnToBreak()
                }
              }
            }

            Rectangle {
              readonly property bool kbSel: root.isActionSelected("endBreakNew")
              width: (parent.width - 8) / 2
              height: 32
              radius: Math.max(6, Style.cornerRadius)
              color: (ebArea.containsMouse || kbSel)
                ? Theme.withAlpha(Commons.Color.accent, 0.88)
                : Commons.Color.accent
              border.width: kbSel ? 1.5 : 0
              border.color: Commons.Color.popups.text

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Molayı bitir, yeni oturum…", "End break, new session…")
                elide: Text.ElideRight
                width: parent.width - 10
                horizontalAlignment: Text.AlignHCenter
                font.family: Style.font.family
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.tokens.primaryInk
              }

              MouseArea {
                id: ebArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.close()
                  if (root.service) root.service.endBreakAndStartNew()
                }
              }
            }
          }
        }

        // Divider
        Rectangle {
          width: parent.width
          height: 1
          color: Theme.withAlpha(Commons.Color.popups.text, 0.10)
        }

        // Show on screen selector (6 styles + real connected monitors only)
        Column {
          width: parent.width
          spacing: 5

          Text {
            textFormat: Text.PlainText
            text: Theme.t(root.lang, "EKRANDA GÖSTER", "SHOW ON SCREEN")
            font.family: Style.font.family
            font.pixelSize: 9
            font.weight: Font.DemiBold
            font.letterSpacing: 0.9
            color: Theme.withAlpha(Commons.Color.popups.text, 0.48)
          }

          Grid {
            width: parent.width
            columns: 3
            spacing: 5

            Repeater {
              model: [
                { key: "tag", label: Theme.t(root.lang, "Etiket", "Tag") },
                { key: "strip", label: Theme.t(root.lang, "İnce şerit", "Thin strip") },
                { key: "capsule", label: Theme.t(root.lang, "Kapsül", "Capsule") },
                { key: "card", label: Theme.t(root.lang, "Kart", "Card") },
                { key: "ring", label: Theme.t(root.lang, "Halka", "Ring") },
                { key: "none", label: Theme.t(root.lang, "Hiçbiri", "None") }
              ]
              delegate: Rectangle {
                readonly property bool selected: root.service && root.service.widgetStyle === modelData.key
                width: (menuCol.width - 10) / 3
                height: 26
                radius: 6
                color: selected
                  ? Theme.withAlpha(Commons.Color.accent, 0.22)
                  : (wsHover.containsMouse ? Theme.withAlpha(Commons.Color.popups.text, 0.09) : Theme.withAlpha(Commons.Color.popups.text, 0.04))
                border.width: selected ? 1 : 0
                border.color: Commons.Color.accent

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: modelData.label
                  font.family: Style.font.family
                  font.pixelSize: 11
                  font.weight: parent.selected ? Font.DemiBold : Font.Normal
                  color: Commons.Color.popups.text
                }

                MouseArea {
                  id: wsHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.service) root.service.setWidgetStyle(modelData.key)
                }
              }
            }
          }
        }

        // Divider
        Rectangle {
          width: parent.width
          height: 1
          color: Theme.withAlpha(Commons.Color.popups.text, 0.10)
        }

        // Navigation links: Open panel (preserves last tab) / Statistics / Settings
        Column {
          width: parent.width
          spacing: 2

          Repeater {
            model: [
              { tab: "", keyHint: "P", label: Theme.t(root.lang, "Paneli aç…", "Open panel…") },
              { tab: "stats", keyHint: "S", label: Theme.t(root.lang, "İstatistikler…", "Statistics…") },
              { tab: "settings", keyHint: ",", label: Theme.t(root.lang, "Ayarlar…", "Settings…") }
            ]
            delegate: Rectangle {
              readonly property bool kbSel: root.isActionSelected("nav:" + modelData.tab)
              width: menuCol.width
              height: 28
              radius: 6
              color: (navHover.containsMouse || kbSel) ? Theme.withAlpha(Commons.Color.popups.text, 0.12) : "transparent"
              border.width: kbSel ? 1 : 0
              border.color: Theme.withAlpha(Commons.Color.popups.text, 0.55)

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.label
                font.family: Style.font.family
                font.pixelSize: 12
                color: Commons.Color.popups.text
              }

              Text {
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: modelData.keyHint || "↗"
                font.family: "Monospace"
                font.pixelSize: 11
                color: Theme.withAlpha(Commons.Color.popups.text, 0.42)
              }

              MouseArea {
                id: navHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.close()
                  if (root.service) root.service.openMainPanel(modelData.tab)
                }
              }
            }
          }
        }
      }
    }
  }
}
