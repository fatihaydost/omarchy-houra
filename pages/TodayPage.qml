import QtQuick
import "../Theme.js" as Theme
import "../components"

Item {
  id: root

  property var service: null
  property var tokens: service ? service.tokens : ({})
  property string lang: service ? service.lang : "en"
  property string fontFamily: "Sans Serif"
  property bool kbPageActive: false
  property bool kbActive: false
  property int kbIndex: 0
  property string kbZone: "list"             // "horizons" | "list" | "localComposer" | "todoistComposer"
  property string localHorizonTab: "today"   // "today" | "week" | "month" | "upcoming" | "inbox"
  property string _popoverTargetKind: ""     // "localComposer" | "todoistComposer" | "editLocal" | "editTodoist"
  property int _popoverLocalTodoId: 0
  property string _popoverTodoistId: ""
  property string todoistNoticeText: ""

  readonly property var horizonTabs: [
    { key: "today", tr: "Bugün", en: "Today" },
    { key: "week", tr: "Hafta", en: "Week" },
    { key: "month", tr: "Ay", en: "Month" },
    { key: "upcoming", tr: "Yaklaşan", en: "Upcoming" },
    { key: "inbox", tr: "Kutu", en: "Inbox" }
  ]

  readonly property bool isEditingText: (
    localComposer.isEditingText
    || todoistComposer.isEditingText
    || schedulePopover.isEditingText
  )

  readonly property var today: service && service.todayData ? service.todayData : ({})
  readonly property var todos: today.todos || []
  readonly property var horizons: today.horizons || ({})
  readonly property var horizonCounts: horizons.counts || ({})
  readonly property var visibleLocalTodos: {
    var hz = horizons || ({})
    if (localHorizonTab === "week") return hz.week || []
    if (localHorizonTab === "month") return hz.month || []
    if (localHorizonTab === "upcoming") return hz.upcoming || []
    if (localHorizonTab === "inbox") return hz.inbox || []
    return hz.today || todos
  }
  readonly property var timeline: today.timeline || []
  readonly property var weekly: service && service.weeklyData ? service.weeklyData : ({})
  readonly property var weeklyGroups: weekly.groups || []
  readonly property var todoist: service && service.todoistData ? service.todoistData : ({})
  readonly property var todoistGroups: todoist.groups || []
  readonly property bool hasActive: !!service && (service.phase === "focus" || service.phase === "paused")
  readonly property var activeCat: service ? service.activeCategory : null
  readonly property int liveFocusMinutes: (Number(today.focusMinutes) || 0) + (hasActive ? Math.floor((Number(service.elapsedSeconds) || 0) / 60) : 0)
  readonly property bool weeklyConfigured: !!(
    service
    && service.settings
    && service.settings.weeklyOn
    && String(service.settings.weeklyTemplate || "").trim().length > 0
  )
  readonly property bool todoistConfigured: !!(
    service
    && service.settings
    && service.settings.todoistOn
    && todoist.hasToken
  )
  readonly property var importedTodoistIds: {
    var map = ({})
    var allLocal = (horizons.today || todos).concat(horizons.openPlanned || [])
    for (var i = 0; i < allLocal.length; i++) {
      var tid = String(allLocal[i].todoistId || "")
      if (tid.length > 0) map[tid] = true
    }
    return map
  }

  readonly property var navBundle: {
    var list = []
    var idxMap = ({})
    for (var i = 0; i < visibleLocalTodos.length; i++) {
      var td = visibleLocalTodos[i]
      var k1 = "todo:" + td.id
      idxMap[k1] = list.length
      list.push({ key: k1, kind: "todo", item: td })
    }
    if (todoistConfigured) {
      for (var g = 0; g < todoistGroups.length; g++) {
        var tasks = todoistGroups[g].tasks || []
        for (var t = 0; t < tasks.length; t++) {
          var tdist = tasks[t]
          var k2 = "td:" + String(tdist.key || tdist.id || (g + "_" + t))
          idxMap[k2] = list.length
          list.push({ key: k2, kind: "todoist", item: tdist })
        }
      }
    }
    if (weeklyConfigured) {
      for (var wg = 0; wg < weeklyGroups.length; wg++) {
        var wtasks = weeklyGroups[wg].tasks || []
        for (var w = 0; w < wtasks.length; w++) {
          var wt = wtasks[w]
          var k3 = "wk:" + String(wt.key || (wg + "_" + w))
          idxMap[k3] = list.length
          list.push({ key: k3, kind: "weekly", item: wt })
        }
      }
    }
    return { list: list, indexByKey: idxMap }
  }
  readonly property var navItems: navBundle.list
  readonly property var navIndexByKey: navBundle.indexByKey

  onNavItemsChanged: {
    if (navItems.length === 0) kbIndex = 0
    else if (kbIndex >= navItems.length) kbIndex = navItems.length - 1
  }

  function releaseTextFocus() {
    if (!isEditingText) return false
    localComposer.releaseTextFocus()
    todoistComposer.releaseTextFocus()
    schedulePopover.releaseTextFocus()
    return true
  }

  function dismissOverlay() {
    if (schedulePopover.open) {
      schedulePopover.cancelNow()
      return true
    }
    if (todayCancelBtn.confirming) {
      todayCancelTimer.stop()
      todayCancelBtn.confirming = false
      return true
    }
    return false
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, todayFlick.contentHeight - todayFlick.height)
    todayFlick.contentY = Math.max(0, Math.min(maxY, todayFlick.contentY + dy))
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(todayFlick.contentItem, 0, 0)
    var top = pt.y - 28
    var bot = pt.y + item.height + 28
    if (top < todayFlick.contentY) {
      todayFlick.contentY = Math.max(0, top)
    } else if (bot > todayFlick.contentY + todayFlick.height) {
      var maxY = Math.max(0, todayFlick.contentHeight - todayFlick.height)
      todayFlick.contentY = Math.min(maxY, bot - todayFlick.height)
    }
  }

  function hasOpenOverlay() {
    return schedulePopover.open || todayCancelBtn.confirming
  }

  function _openSchedulePopoverAt(targetKind, initObj, sourceItem, localX, localY) {
    _popoverTargetKind = targetKind
    _popoverLocalTodoId = Number(initObj.todoId) || 0
    _popoverTodoistId = String(initObj.todoistId || "")
    schedulePopover.openFor(initObj)
    var pt = sourceItem ? sourceItem.mapToItem(root, localX || 0, localY || 0) : { x: 40, y: 120 }
    var maxX = Math.max(12, root.width - schedulePopover.width - 14)
    var maxY = Math.max(12, root.height - schedulePopover.height - 14)
    schedulePopover.x = Math.round(Math.max(12, Math.min(maxX, pt.x)))
    schedulePopover.y = Math.round(Math.max(12, Math.min(maxY, pt.y)))
  }

  function _focusStops() {
    var stops = ["horizons"]
    if (navItems.length > 0) stops.push("list")
    stops.push("localComposer")
    if (todoistConfigured) stops.push("todoistComposer")
    return stops
  }

  function _applyStop(stop) {
    kbZone = stop
    if (stop === "localComposer") {
      kbActive = false
      ensureItemVisible(localComposer)
      localComposer.focusTitle()
    } else if (stop === "todoistComposer") {
      kbActive = false
      ensureItemVisible(todoistComposer)
      todoistComposer.focusTitle()
    } else if (stop === "horizons") {
      releaseTextFocus()
      kbActive = false
      ensureItemVisible(horizonTabBar)
    } else {
      releaseTextFocus()
      kbActive = true
    }
  }

  function enterFromTab(delta) {
    var stops = _focusStops()
    var target = delta >= 0 ? (navItems.length > 0 ? "list" : stops[0]) : stops[stops.length - 1]
    _applyStop(target)
  }

  function stepFocus(delta) {
    if (schedulePopover.open) return true
    var stops = _focusStops()
    var cur = kbZone
    if (localComposer.isEditingText) cur = "localComposer"
    else if (todoistComposer.isEditingText) cur = "todoistComposer"
    var idx = stops.indexOf(cur)
    if (idx < 0) idx = (delta >= 0 ? -1 : stops.length)
    var next = idx + delta
    if (next < 0 || next >= stops.length) return false
    _applyStop(stops[next])
    return true
  }

  function _stepHorizonTab(delta) {
    var keys = ["today", "week", "month", "upcoming", "inbox"]
    var curIdx = Math.max(0, keys.indexOf(localHorizonTab))
    var nextIdx = curIdx + delta
    if (nextIdx < 0) return false
    if (nextIdx >= keys.length) nextIdx = keys.length - 1
    localHorizonTab = keys[nextIdx]
    kbIndex = 0
    return true
  }

  function handleKey(event) {
    if (schedulePopover.open) {
      return schedulePopover.handleKey(event)
    }
    if (isEditingText) return false
    var k = event.key
    var mods = event.modifiers
    var count = navItems.length

    if (kbZone === "horizons") {
      if (k === Qt.Key_Right) {
        _stepHorizonTab(1)
        return true
      }
      if (k === Qt.Key_Left) {
        if (!_stepHorizonTab(-1)) return "sidebar"
        return true
      }
      if (k === Qt.Key_Down) {
        if (count > 0) {
          kbZone = "list"
          kbActive = true
          kbIndex = 0
        } else {
          _applyStop("localComposer")
        }
        return true
      }
    }

    if (k === Qt.Key_Left) {
      return "sidebar"
    }
    if (k === Qt.Key_Down) {
      kbZone = "list"
      if (count > 0) {
        if (!kbActive || !kbPageActive) {
          kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        } else {
          kbIndex = Math.min(count - 1, kbIndex + 1)
        }
        kbActive = true
      } else {
        scrollBy(64)
      }
      return true
    }
    if (k === Qt.Key_Up) {
      if (count > 0 && kbActive && kbIndex === 0) {
        kbActive = false
        kbZone = "horizons"
        ensureItemVisible(horizonTabBar)
        return true
      }
      kbZone = "list"
      if (count > 0) {
        if (!kbActive || !kbPageActive) {
          kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        } else {
          kbIndex = Math.max(0, kbIndex - 1)
        }
        kbActive = true
      } else {
        scrollBy(-64)
      }
      return true
    }
    if (k === Qt.Key_PageDown) { scrollBy(Math.round(todayFlick.height * 0.72)); return true }
    if (k === Qt.Key_PageUp) { scrollBy(-Math.round(todayFlick.height * 0.72)); return true }
    if (k === Qt.Key_Home) {
      kbZone = "list"
      kbActive = true
      kbIndex = 0
      todayFlick.contentY = 0
      return true
    }
    if (k === Qt.Key_End) {
      kbZone = "list"
      kbActive = true
      if (count > 0) kbIndex = count - 1
      else scrollBy(99999)
      return true
    }

    var cur = (count > 0 && kbIndex >= 0 && kbIndex < count) ? navItems[kbIndex] : null
    if (!cur || !service) return false

    if (k === Qt.Key_Space) {
      kbActive = true
      if (cur.kind === "todo") {
        service.cycleTodoState(cur.item.id)
      } else if (cur.kind === "todoist") {
        if (cur.item.id) service.setTodoistTaskCompleted(cur.item.id, true, 0)
      } else if (cur.kind === "weekly") {
        service.openNewSessionForWeekly(cur.item)
      }
      return true
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      kbActive = true
      if (cur.kind === "todo") {
        if (mods & Qt.ShiftModifier) service.openNewSessionForTodo(cur.item)
        else service.cycleTodoState(cur.item.id)
      } else if (cur.kind === "todoist") {
        service.openNewSessionForTodoist(cur.item)
      } else if (cur.kind === "weekly") {
        service.openNewSessionForWeekly(cur.item)
      }
      return true
    }
    if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && cur.kind === "todo") {
      kbActive = true
      service.deleteTodo(cur.item.id)
      return true
    }
    return false
  }

  // Poll Markdown / Today snapshot every 20s while visible so external Obsidian edits reflect live
  Timer {
    interval: 20000
    running: root.visible && !!root.service
    repeat: true
    onTriggered: if (root.service) root.service.refreshSnapshot()
  }

  function _findCat(catId) {
    var cats = service && service.categories ? service.categories : []
    for (var i = 0; i < cats.length; i++) {
      if (Number(cats[i].id) === Number(catId)) return cats[i]
    }
    return null
  }

  Timer {
    id: todoistNoticeTimer
    interval: 3800
    repeat: false
    onTriggered: root.todoistNoticeText = ""
  }

  function _horizonHeading() {
    if (localHorizonTab === "week") return Theme.t(lang, "BU HAFTA & HAFTALIK HEDEFLER", "THIS WEEK & WEEKLY GOALS")
    if (localHorizonTab === "month") return Theme.t(lang, "AYLIK PLAN & HEDEFLER", "MONTHLY PLAN & GOALS")
    if (localHorizonTab === "upcoming") return Theme.t(lang, "YAKLAŞAN GÖREVLER", "UPCOMING TASKS")
    if (localHorizonTab === "inbox") return Theme.t(lang, "GELEN KUTUSU (TARİHSİZ)", "INBOX (UNDATED)")
    return Theme.t(lang, "BUGÜNÜN YAPILACAKLARI", "TODAY'S TO-DO")
  }

  function _horizonEmptyText() {
    if (localHorizonTab === "week") return Theme.t(lang, "Haftalık hedef veya bu haftaya planlı görev yok.", "No weekly goals or tasks scheduled this week.")
    if (localHorizonTab === "month") return Theme.t(lang, "Bu aya planlı görev yok. Aşağıdan ekleyebilirsin.", "No monthly tasks yet. Add one below.")
    if (localHorizonTab === "upcoming") return Theme.t(lang, "İleri tarihli planlanmış görev yok.", "No upcoming scheduled tasks.")
    if (localHorizonTab === "inbox") return Theme.t(lang, "Tarihsiz görev kutusu boş.", "Inbox has no undated tasks.")
    return Theme.t(lang, "Henüz görev yok. Aşağıdan ekleyebilirsin.", "No tasks yet. Add one below.")
  }

  Flickable {
    id: todayFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: pageCol.implicitHeight + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pageCol
      x: 28
      y: 24
      width: parent.width - 56
      spacing: 20

      // Eyebrow + Hero Focus Total
      Column {
        width: parent.width
        spacing: 4

        Text {
          text: Theme.formatTodayEyebrow(root.lang)
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 1.3
          color: root.tokens.muted || "#888888"
        }

        Item {
          width: parent.width
          height: 40

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.formatMinutes(root.liveFocusMinutes, root.lang) + " " + Theme.t(root.lang, "odaklanıldı", "focused")
            font.family: root.fontFamily
            font.pixelSize: 28
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }

          // Active session pill + explicit Finish / Close (no break) / Cancel actions
          Row {
            visible: root.hasActive
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Rectangle {
              width: liveRow.implicitWidth + 18
              height: 30
              radius: 15
              color: root.tokens.card2 || "#1f1f25"
              border.width: 1
              border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.18)

              Row {
                id: liveRow
                anchors.centerIn: parent
                spacing: 8

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 7
                  height: 7
                  radius: 3.5
                  color: root.activeCat ? (root.activeCat.color || "#4fc08d") : "#4fc08d"
                }

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.service ? root.service.clockText : "00:00") + " · " +
                        (root.service && root.service.phase === "paused"
                          ? Theme.t(root.lang, "Duraklatıldı", "Paused")
                          : Theme.t(root.lang, "Odakta", "Focusing"))
                  font.family: "Monospace"
                  font.pixelSize: 11
                  color: root.tokens.ink || "#ffffff"
                }
              }
            }

            Rectangle {
              visible: !todayCancelBtn.confirming
              width: todayFinishLbl.implicitWidth + 18
              height: 30
              radius: 15
              color: todayFinishArea.containsMouse
                ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.88)
                : (root.tokens.primaryBg || "#ffffff")

              Text {
                id: todayFinishLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Oturumu bitir", "Finish session")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.tokens.primaryInk || "#000000"
              }

              MouseArea {
                id: todayFinishArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.finishSession()
              }
            }

            Rectangle {
              visible: !todayCancelBtn.confirming
              width: todayCloseNoBreakLbl.implicitWidth + 18
              height: 30
              radius: 15
              color: todayCloseNoBreakArea.containsMouse
                ? (root.tokens.raised || "#2b2b33")
                : (root.tokens.card || "#17171c")
              border.width: 1
              border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.14)

              Text {
                id: todayCloseNoBreakLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Molasız kapat", "Close & save")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.tokens.secondary || "#cccccc"
              }

              MouseArea {
                id: todayCloseNoBreakArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.closeSessionWithoutBreak()
              }
            }

            Rectangle {
              id: todayCancelBtn
              property bool confirming: false
              width: todayCancelLbl.implicitWidth + 18
              height: 30
              radius: 15
              color: confirming
                ? (todayCancelArea.containsMouse ? (root.tokens.danger || "#e06458") : Theme.withAlpha(root.tokens.danger || "#e06458", 0.22))
                : (todayCancelArea.containsMouse ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.14) : (root.tokens.card || "#17171c"))
              border.width: 1
              border.color: confirming || todayCancelArea.containsMouse
                ? (root.tokens.danger || "#e06458")
                : (root.tokens.line || Qt.rgba(1, 1, 1, 0.10))

              Timer {
                id: todayCancelTimer
                interval: 3500
                repeat: false
                onTriggered: todayCancelBtn.confirming = false
              }

              Text {
                id: todayCancelLbl
                anchors.centerIn: parent
                text: todayCancelBtn.confirming
                  ? Theme.t(root.lang, "Kaydetmeden iptal et?", "Discard without saving?")
                  : Theme.t(root.lang, "İptal et", "Cancel")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: todayCancelBtn.confirming ? Font.DemiBold : Font.Normal
                color: todayCancelBtn.confirming
                  ? (todayCancelArea.containsMouse ? "#ffffff" : (root.tokens.danger || "#e06458"))
                  : (todayCancelArea.containsMouse ? (root.tokens.danger || "#e06458") : (root.tokens.muted || "#888888"))
              }

              MouseArea {
                id: todayCancelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!todayCancelBtn.confirming) {
                    todayCancelBtn.confirming = true
                    todayCancelTimer.restart()
                  } else {
                    todayCancelTimer.stop()
                    todayCancelBtn.confirming = false
                    if (root.service) root.service.cancelSession()
                  }
                }
              }
            }
          }
        }
      }

      // 4 Metric Cards (Sessions, Breaks duration + count, Tasks, Emergency)
      Row {
        width: parent.width
        spacing: 12

        Repeater {
          model: [
            {
              title: Theme.t(root.lang, "Oturumlar", "Sessions"),
              value: String(root.today.sessionsCount || 0),
              sub: (root.today.pomodoro50Count || 0) + " × 50+10"
            },
            {
              title: Theme.t(root.lang, "Molalar", "Breaks"),
              value: Theme.formatMinutes(root.today.breakMinutes || 0, root.lang),
              sub: (root.today.breaksCount || 0) + " " + Theme.t(root.lang, "mola", "breaks")
            },
            {
              title: Theme.t(root.lang, "Görevler", "Tasks"),
              value: (root.today.doneTodos || 0) + " / " + (root.today.totalTodos || 0) + " 🥳",
              sub: Theme.t(root.lang, "bugünün listesi", "today's list")
            },
            {
              title: Theme.t(root.lang, "Acil çıkış", "Emergency"),
              value: String(root.today.emergencyCount || 0),
              sub: Theme.t(root.lang, "erken dönüş", "early returns")
            }
          ]
          delegate: Rectangle {
            width: (pageCol.width - 36) / 4
            height: 82
            radius: 12
            color: root.tokens.card || "#17171c"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

            Column {
              anchors.fill: parent
              anchors.margins: 13
              spacing: 4

              Text {
                text: modelData.title
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.tokens.muted || "#888888"
              }

              Text {
                width: parent.width
                elide: Text.ElideRight
                text: modelData.value
                font.family: root.fontFamily
                font.pixelSize: 20
                font.weight: Font.DemiBold
                color: root.tokens.ink || "#ffffff"
              }

              Text {
                text: modelData.sub
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.secondary || "#aaaaaa"
              }
            }
          }
        }
      }

      // Main 2-column content: Left (Today's To-do + This week), Right (Day flow)
      Row {
        width: parent.width
        spacing: 16

        // LEFT COLUMN
        Column {
          id: leftCol
          width: Math.round((parent.width - 16) * 0.56)
          spacing: 16

          // Today's To-do Card
          Rectangle {
            width: parent.width
            height: todoCardInner.implicitHeight + 32
            radius: 14
            color: root.tokens.card || "#17171c"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

            Column {
              id: todoCardInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 16
              spacing: 10

              Item {
                width: parent.width
                height: 20

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root._horizonHeading()
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.Bold
                  font.letterSpacing: 1.1
                  color: root.tokens.muted || "#888888"
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 8

                  Text {
                    visible: root.visibleLocalTodos.length > 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.localHorizonTab === "today"
                      ? ((root.today.doneTodos || 0) + " / " + (root.today.totalTodos || 0))
                      : String(root.visibleLocalTodos.length)
                    font.family: "Monospace"
                    font.pixelSize: 11
                    color: root.tokens.secondary || "#aaaaaa"
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "🤓 → 🙂‍↔️ → 🥳"
                    font.pixelSize: 11
                    color: root.tokens.faint || "#666666"
                  }
                }
              }

              // Multi-Horizon Tab Bar (Bugün · Hafta · Ay · Yaklaşan · Kutu)
              Row {
                id: horizonTabBar
                width: parent.width
                spacing: 5

                Repeater {
                  model: root.horizonTabs
                  delegate: Rectangle {
                    required property var modelData
                    readonly property bool active: root.localHorizonTab === modelData.key
                    readonly property bool kbTabRing: root.kbPageActive && root.kbZone === "horizons" && active
                    readonly property int cnt: Number(root.horizonCounts[modelData.key]) || 0
                    readonly property bool hasOverdue: modelData.key === "today" && (Number(root.horizonCounts.overdue) || 0) > 0
                    width: hzTabRow.implicitWidth + 14
                    height: 26
                    radius: 7
                    color: active
                      ? (root.tokens.raised || "#282830")
                      : (hzTabMa.containsMouse ? (root.tokens.card2 || "#1f1f25") : "transparent")
                    border.width: kbTabRing ? 2 : 1
                    border.color: kbTabRing
                      ? (root.tokens.ink || "#ffffff")
                      : (active
                          ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.22))
                          : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08)))

                    Row {
                      id: hzTabRow
                      anchors.centerIn: parent
                      spacing: 5

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t(root.lang, modelData.tr, modelData.en)
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: active ? Font.DemiBold : Font.Medium
                        color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#aaaaaa")
                      }

                      Rectangle {
                        visible: cnt > 0
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(16, cntTxt.implicitWidth + 8)
                        height: 15
                        radius: 7
                        color: hasOverdue
                          ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.22)
                          : (active ? (root.tokens.card2 || "#1f1f25") : Theme.withAlpha(root.tokens.ink || "#ffffff", 0.07))

                        Text {
                          id: cntTxt
                          anchors.centerIn: parent
                          text: String(cnt)
                          font.family: "Monospace"
                          font.pixelSize: 9
                          font.weight: Font.DemiBold
                          color: hasOverdue
                            ? (root.tokens.danger || "#e06458")
                            : (active ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#888888"))
                        }
                      }
                    }

                    MouseArea {
                      id: hzTabMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.localHorizonTab = modelData.key
                        root.kbIndex = 0
                      }
                    }
                  }
                }
              }

              Text {
                visible: root.visibleLocalTodos.length === 0
                text: root._horizonEmptyText()
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.muted || "#777777"
              }

              Column {
                width: parent.width
                spacing: 5

                Repeater {
                  model: root.visibleLocalTodos.length
                  delegate: Rectangle {
                    id: todoRowRect
                    readonly property var td: root.visibleLocalTodos[index]
                    readonly property int st: Number(td.state) || 0
                    readonly property int prio: Number(td.priority) || 1
                    readonly property color prioCol: Theme.priorityColor(prio, root.tokens.muted || "#888888")
                    readonly property string navKey: "todo:" + td.id
                    readonly property int navIdx: root.navIndexByKey[navKey] !== undefined ? Number(root.navIndexByKey[navKey]) : -1
                    readonly property bool kbSelected: root.kbPageActive && root.kbActive && navIdx >= 0 && root.kbIndex === navIdx
                    readonly property string metaScheduleSummary: {
                      var parts = []
                      var dl = String(td.dueLabel || "")
                      var sc = String(td.scope || "day")
                      var showDue = (root.localHorizonTab !== "today") || sc !== "day" || !!td.isPastDue
                      if (showDue && dl) parts.push(dl)
                      if (td.dueTime) parts.push(String(td.dueTime))
                      if (td.recurrenceLabel) parts.push("↻ " + String(td.recurrenceLabel))
                      return parts.join(" · ")
                    }
                    onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(todoRowRect)
                    width: todoCardInner.width
                    height: Math.max(38, tdCol.implicitHeight + 14)
                    radius: 8
                    color: (st === 1 || kbSelected)
                      ? (root.tokens.raised || "#26262f")
                      : (rowHover.hovered ? (root.tokens.card2 || "#1f1f25") : "transparent")
                    border.width: kbSelected ? 2 : (st === 1 ? 1 : 0)
                    border.color: kbSelected
                      ? (root.tokens.ink || "#ffffff")
                      : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16))

                    HoverHandler { id: rowHover }

                    Row {
                      anchors.fill: parent
                      anchors.leftMargin: 6
                      anchors.rightMargin: 6
                      spacing: 8

                      Rectangle {
                        width: 28
                        height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        radius: 7
                        color: emojiArea.containsMouse
                          ? (root.tokens.raised || "#2d2d36")
                          : (todoRowRect.prio > 1 && st !== 2 ? Theme.withAlpha(todoRowRect.prioCol, 0.12) : "transparent")
                        border.width: (todoRowRect.prio > 1 && st !== 2) ? 1 : 0
                        border.color: todoRowRect.prioCol

                        Text {
                          anchors.centerIn: parent
                          text: Theme.todoEmoji(st)
                          font.pixelSize: 15
                        }

                        MouseArea {
                          id: emojiArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: if (root.service) root.service.cycleTodoState(td.id)
                        }
                      }

                      Column {
                        id: tdCol
                        width: Math.max(80, parent.width - tdRowActions.width - 52)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        Text {
                          width: parent.width
                          text: td.title || ""
                          wrapMode: Text.WordWrap
                          font.family: root.fontFamily
                          font.pixelSize: 13
                          font.weight: st === 1 ? Font.Medium : Font.Normal
                          font.strikeout: st === 2
                          color: st === 2 ? (root.tokens.muted || "#777777") : (root.tokens.ink || "#ffffff")
                        }

                        Text {
                          visible: (td.detail || "").length > 0
                          width: parent.width
                          text: td.detail || ""
                          wrapMode: Text.WordWrap
                          font.family: root.fontFamily
                          font.pixelSize: 11
                          color: root.tokens.muted || "#777777"
                        }

                        // Metadata badges row: Priority (P1..P3), Schedule/Time/Recurrence/Overdue, Category, Todoist Close
                        Flow {
                          visible: todoRowRect.prio > 1
                            || todoRowRect.metaScheduleSummary !== ""
                            || (Number(td.categoryId) || 0) > 0
                            || (td.todoistId || "") !== ""
                          width: parent.width
                          spacing: 5

                          Rectangle {
                            visible: todoRowRect.prio > 1
                            width: pBadgeTxt.implicitWidth + 10
                            height: 18
                            radius: 5
                            color: Theme.withAlpha(todoRowRect.prioCol, 0.18)
                            border.width: 1
                            border.color: Theme.withAlpha(todoRowRect.prioCol, 0.55)

                            Text {
                              id: pBadgeTxt
                              anchors.centerIn: parent
                              text: Theme.priorityLabel(todoRowRect.prio)
                              font.family: root.fontFamily
                              font.pixelSize: 9
                              font.weight: Font.Bold
                              color: todoRowRect.prioCol
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                root._openSchedulePopoverAt("editLocal", {
                                  todoId: td.id,
                                  scope: td.scope || "day",
                                  day: td.day || "",
                                  endDay: td.endDay || "",
                                  dueTime: td.dueTime || "",
                                  recurrence: td.recurrence || "",
                                  priority: todoRowRect.prio,
                                  isTodoist: false,
                                  titleText: td.title || ""
                                }, todoRowRect, 12, todoRowRect.height + 4)
                              }
                            }
                          }

                          Rectangle {
                            visible: todoRowRect.metaScheduleSummary !== ""
                            width: schedBadgeTxt.implicitWidth + 12
                            height: 18
                            radius: 5
                            color: td.isOverdue
                              ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.16)
                              : (root.tokens.card2 || "#1f1f25")
                            border.width: 1
                            border.color: td.isOverdue
                              ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.50)
                              : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                            Text {
                              id: schedBadgeTxt
                              anchors.centerIn: parent
                              text: todoRowRect.metaScheduleSummary
                              font.family: root.fontFamily
                              font.pixelSize: 10
                              font.weight: td.isOverdue ? Font.DemiBold : Font.Normal
                              color: td.isOverdue
                                ? (root.tokens.danger || "#e06458")
                                : (root.tokens.secondary || "#aaaaaa")
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                root._openSchedulePopoverAt("editLocal", {
                                  todoId: td.id,
                                  scope: td.scope || "day",
                                  day: td.day || "",
                                  endDay: td.endDay || "",
                                  dueTime: td.dueTime || "",
                                  recurrence: td.recurrence || "",
                                  priority: todoRowRect.prio,
                                  isTodoist: false,
                                  titleText: td.title || ""
                                }, todoRowRect, 12, todoRowRect.height + 4)
                              }
                            }
                          }

                          Rectangle {
                            visible: (Number(td.categoryId) || 0) > 0 && (td.categoryName || "") !== ""
                            width: catChipRow.implicitWidth + 12
                            height: 18
                            radius: 5
                            color: root.tokens.card2 || "#1f1f25"
                            border.width: 1
                            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

                            Row {
                              id: catChipRow
                              anchors.centerIn: parent
                              spacing: 4

                              Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: td.categoryColor || "#4c8df0"
                              }

                              Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: td.categoryName || ""
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                color: root.tokens.secondary || "#aaaaaa"
                              }
                            }
                          }

                          Rectangle {
                            readonly property bool tdDone: !!td.todoistDone
                            visible: (td.todoistId || "") !== ""
                            width: tdOriginTxt.implicitWidth + 12
                            height: 18
                            radius: 5
                            color: tdDone
                              ? Theme.withAlpha("#4fc08d", todayTdCompleteArea.containsMouse ? 0.28 : 0.16)
                              : Theme.withAlpha("#e44332", todayTdCompleteArea.containsMouse ? 0.26 : 0.14)
                            border.width: 1
                            border.color: tdDone
                              ? Theme.withAlpha("#4fc08d", 0.50)
                              : Theme.withAlpha("#e44332", todayTdCompleteArea.containsMouse ? 0.65 : 0.35)

                            Text {
                              id: tdOriginTxt
                              anchors.centerIn: parent
                              text: parent.tdDone
                                ? Theme.t(root.lang, "✓ Todoist'te tamamlandı", "✓ Completed in Todoist")
                                : Theme.t(root.lang, "○ Todoist'te tamamla", "○ Complete in Todoist")
                              font.family: root.fontFamily
                              font.pixelSize: 10
                              font.weight: Font.Medium
                              color: parent.tdDone ? "#4fc08d" : "#e44332"
                            }

                            MouseArea {
                              id: todayTdCompleteArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                if (root.service) {
                                  root.service.setTodoistTaskCompleted(td.todoistId, !parent.tdDone, td.id)
                                }
                              }
                            }
                          }
                        }
                      }

                      Row {
                        id: tdRowActions
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3

                        // Edit Schedule & Priority inline
                        Rectangle {
                          visible: rowHover.hovered || todoRowRect.kbSelected
                          width: 22
                          height: 22
                          radius: 6
                          color: editSchedMa.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "🗓"
                            font.pixelSize: 11
                          }

                          MouseArea {
                            id: editSchedMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              root._openSchedulePopoverAt("editLocal", {
                                todoId: td.id,
                                scope: td.scope || "day",
                                day: td.day || "",
                                endDay: td.endDay || "",
                                dueTime: td.dueTime || "",
                                recurrence: td.recurrence || "",
                                priority: todoRowRect.prio,
                                isTodoist: false,
                                titleText: td.title || ""
                              }, todoRowRect, 12, todoRowRect.height + 4)
                            }
                          }
                        }

                        // Start focus session with this task
                        Rectangle {
                          visible: (rowHover.hovered || todoRowRect.kbSelected) && st !== 2
                          width: 22
                          height: 22
                          radius: 6
                          color: startTodoSessMa.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "▶"
                            font.pixelSize: 10
                            color: root.tokens.ink || "#ffffff"
                          }

                          MouseArea {
                            id: startTodoSessMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.service) root.service.openNewSessionForTodo(td)
                          }
                        }

                        Rectangle {
                          visible: rowHover.hovered || todoRowRect.kbSelected
                          width: 22
                          height: 22
                          radius: 6
                          color: delHov.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "×"
                            font.pixelSize: 14
                            color: root.tokens.muted || "#888888"
                          }

                          MouseArea {
                            id: delHov
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.service) root.service.deleteTodo(td.id)
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Multi-Horizon Local Task Composer
              TaskComposer {
                id: localComposer
                width: parent.width
                mode: "local"
                defaultHorizon: root.localHorizonTab
                categories: root.service ? (root.service.categories || []) : []
                kbFocused: root.kbPageActive && root.kbZone === "localComposer"
                tokens: root.tokens
                lang: root.lang
                fontFamily: root.fontFamily
                onRequestSchedulePicker: function(curSched, ax, ay) {
                  root._openSchedulePopoverAt("localComposer", curSched, localComposer, ax, ay)
                }
                onSubmitted: function(payload) {
                  if (!root.service) return
                  root.service.addTodo(payload.title, payload.detail, {
                    scope: payload.scope,
                    day: payload.day,
                    endDay: payload.endDay,
                    dueTime: payload.dueTime,
                    recurrence: payload.recurrence,
                    priority: payload.priority,
                    categoryId: payload.categoryId
                  })
                }
              }
            }
          }

          // Optional TODOIST Card (2-way sync: filter horizons, create, edit priority/schedule, complete, start session)
          Rectangle {
            visible: root.todoistConfigured
            width: parent.width
            height: todoistInner.implicitHeight + 32
            radius: 14
            color: root.tokens.card || "#17171c"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

            Column {
              id: todoistInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 16
              spacing: 10

              Item {
                width: parent.width
                height: 22

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 8

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TODOIST"
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Bold
                    font.letterSpacing: 1.1
                    color: root.tokens.muted || "#888888"
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.todoist.filter || "today | overdue"
                    font.family: "Monospace"
                    font.pixelSize: 10
                    color: root.tokens.faint || "#666666"
                  }
                }

                Row {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 6

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (root.service && root.service.todoistSyncing)
                      ? Theme.t(root.lang, "eşitleniyor…", "syncing…")
                      : ((root.todoist.openCount || 0) + " " + Theme.t(root.lang, "açık", "open"))
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    color: root.tokens.secondary || "#aaaaaa"
                  }

                  Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    radius: 6
                    color: tdSyncBtnArea.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                    Text {
                      anchors.centerIn: parent
                      text: "↻"
                      font.pixelSize: 13
                      color: tdSyncBtnArea.containsMouse ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#aaaaaa")
                    }

                    MouseArea {
                      id: tdSyncBtnArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: if (root.service) root.service.syncTodoistNow("", null)
                    }
                  }
                }
              }

              // Quick Todoist Horizon Filter Pills
              Flow {
                width: parent.width
                spacing: 5

                Repeater {
                  model: [
                    { query: "today | overdue", tr: "Bugün", en: "Today" },
                    { query: "7 days | overdue", tr: "7 Gün", en: "7 Days" },
                    { query: "30 days | overdue", tr: "30 Gün", en: "30 Days" },
                    { query: "no date", tr: "Tarihsiz", en: "Undated" },
                    { query: "all", tr: "Tümü", en: "All" }
                  ]

                  delegate: Rectangle {
                    required property var modelData
                    readonly property string curFilter: String(root.todoist.filter || "today | overdue").trim()
                    readonly property bool active: curFilter.toLowerCase() === modelData.query.toLowerCase()
                    width: tdFiltTxt.implicitWidth + 14
                    height: 22
                    radius: 6
                    color: active
                      ? (root.tokens.raised || "#282830")
                      : (tdFiltMa.containsMouse ? (root.tokens.card2 || "#1f1f25") : "transparent")
                    border.width: 1
                    border.color: active
                      ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.22))
                      : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                    Text {
                      id: tdFiltTxt
                      anchors.centerIn: parent
                      text: Theme.t(root.lang, modelData.tr, modelData.en)
                      font.family: root.fontFamily
                      font.pixelSize: 10
                      font.weight: active ? Font.DemiBold : Font.Normal
                      color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#888888")
                    }

                    MouseArea {
                      id: tdFiltMa
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (root.service) root.service.syncTodoistNow(modelData.query, null)
                      }
                    }
                  }
                }
              }

              Text {
                visible: (root.todoist.error || "") !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.todoist.error || ""
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.danger || "#e06458"
              }

              Text {
                visible: root.todoistNoticeText !== "" && (root.todoist.error || "") === ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.todoistNoticeText
                font.family: root.fontFamily
                font.pixelSize: 11
                color: "#4fc08d"
              }

              Text {
                visible: (root.todoist.error || "") === "" && root.todoistGroups.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: Theme.t(
                  root.lang,
                  "Bu filtrede açık Todoist görevi yok 🎉",
                  "No open Todoist tasks for this filter 🎉"
                )
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.secondary || "#aaaaaa"
              }

              Repeater {
                model: root.todoistGroups.length
                delegate: Column {
                  readonly property var grp: root.todoistGroups[index]
                  readonly property var grpCat: root._findCat(grp.categoryId)
                  width: todoistInner.width
                  spacing: 4

                  Item {
                    width: parent.width
                    height: 20

                    Row {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 7

                      CategorySwatch {
                        visible: !!grpCat
                        anchors.verticalCenter: parent.verticalCenter
                        swatchSize: 14
                        swatchColor: grpCat ? (grpCat.color || "#4c8df0") : "#4c8df0"
                        emoji: grpCat ? (grpCat.emoji || "") : ""
                        iconName: grpCat ? (grpCat.icon || "") : ""
                        iconColor: grpCat ? (grpCat.iconColor || "") : ""
                      }

                      Rectangle {
                        visible: !grpCat
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: "#e44332"
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: grp.name || ""
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: root.tokens.secondary || "#cccccc"
                      }
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(grp.tasks ? grp.tasks.length : 0)
                      font.family: "Monospace"
                      font.pixelSize: 10
                      color: root.tokens.muted || "#777777"
                    }
                  }

                  Repeater {
                    id: tdistTaskRep
                    model: grp.tasks ? grp.tasks.length : 0
                    delegate: Rectangle {
                      id: tdistRow
                      readonly property var tdist: grp.tasks[index]
                      readonly property int prio: Number(tdist.priority) || 1
                      readonly property color prioCol: Theme.priorityColor(prio, root.tokens.muted || "#888888")
                      readonly property bool alreadyInToday: !!root.importedTodoistIds[String(tdist.id || "")]
                      readonly property string navKey: "td:" + String(tdist.key || tdist.id || index)
                      readonly property int navIdx: root.navIndexByKey[navKey] !== undefined ? Number(root.navIndexByKey[navKey]) : -1
                      readonly property bool kbSelected: root.kbPageActive && root.kbActive && navIdx >= 0 && root.kbIndex === navIdx
                      onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(tdistRow)
                      width: todoistInner.width
                      height: Math.max(32, tdistTitleTxt.implicitHeight + 12)
                      radius: 7
                      color: kbSelected
                        ? (root.tokens.raised || "#26262f")
                        : ((tdistHover.hovered) ? (root.tokens.card2 || "#1f1f25") : "transparent")
                      border.width: kbSelected ? 2 : 0
                      border.color: root.tokens.ink || "#ffffff"

                      HoverHandler { id: tdistHover }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (root.service) {
                            root.service.openNewSessionForTodoist(tdistRow.tdist)
                          }
                        }
                      }

                      Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.right: tdistActionsRow.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        // Clickable Todoist completion circle
                        Rectangle {
                          id: tdistCheckCircle
                          readonly property color ringColor: tdistRow.prioCol
                          anchors.verticalCenter: parent.verticalCenter
                          width: 18
                          height: 18
                          radius: 9
                          color: tdistCompleteArea.containsMouse
                            ? Theme.withAlpha("#4fc08d", 0.24)
                            : Theme.withAlpha(ringColor, tdistRow.prio >= 3 ? 0.12 : 0.0)
                          border.width: tdistRow.prio >= 3 ? 2 : 1
                          border.color: tdistCompleteArea.containsMouse ? "#4fc08d" : ringColor

                          Text {
                            visible: tdistCompleteArea.containsMouse
                            anchors.centerIn: parent
                            text: "✓"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: "#4fc08d"
                          }

                          MouseArea {
                            id: tdistCompleteArea
                            anchors.fill: parent
                            anchors.margins: -3
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              if (root.service && tdistRow.tdist && tdistRow.tdist.id) {
                                root.service.setTodoistTaskCompleted(tdistRow.tdist.id, true, 0)
                              }
                            }
                          }
                        }

                        Text {
                          id: tdistTitleTxt
                          width: Math.max(60, parent.width - 28)
                          anchors.verticalCenter: parent.verticalCenter
                          text: tdistRow.tdist.title || ""
                          wrapMode: Text.WordWrap
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          color: root.tokens.ink || "#ffffff"
                        }
                      }

                      Row {
                        id: tdistActionsRow
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Rectangle {
                          visible: tdistRow.prio > 1
                          anchors.verticalCenter: parent.verticalCenter
                          width: tdPrioBadgeTxt.implicitWidth + 8
                          height: 17
                          radius: 5
                          color: Theme.withAlpha(tdistRow.prioCol, 0.16)
                          border.width: 1
                          border.color: Theme.withAlpha(tdistRow.prioCol, 0.50)

                          Text {
                            id: tdPrioBadgeTxt
                            anchors.centerIn: parent
                            text: Theme.priorityLabel(tdistRow.prio)
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            font.weight: Font.Bold
                            color: tdistRow.prioCol
                          }
                        }

                        Text {
                          visible: (tdistRow.tdist.dueLabel || "").length > 0
                          anchors.verticalCenter: parent.verticalCenter
                          text: (tdistRow.tdist.isRecurring ? "↻ " : "") + (tdistRow.tdist.dueLabel || "")
                          font.family: root.fontFamily
                          font.pixelSize: 10
                          color: tdistRow.tdist.isOverdue
                            ? (root.tokens.danger || "#e06458")
                            : (root.tokens.muted || "#777777")
                        }

                        // Edit Todoist schedule & priority
                        Rectangle {
                          visible: tdistHover.hovered || tdistRow.kbSelected
                          anchors.verticalCenter: parent.verticalCenter
                          width: 22
                          height: 22
                          radius: 6
                          color: tdEditSchedMa.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "🗓"
                            font.pixelSize: 11
                          }

                          MouseArea {
                            id: tdEditSchedMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              var hasDue = String(tdistRow.tdist.dueDate || "") !== ""
                              root._openSchedulePopoverAt("editTodoist", {
                                todoistId: String(tdistRow.tdist.id || ""),
                                scope: hasDue ? "day" : "inbox",
                                day: hasDue ? String(tdistRow.tdist.dueDate) : "",
                                endDay: "",
                                dueTime: String(tdistRow.tdist.dueTime || ""),
                                recurrence: "",
                                priority: tdistRow.prio,
                                isTodoist: true,
                                titleText: tdistRow.tdist.title || ""
                              }, tdistRow, 12, tdistRow.height + 4)
                            }
                          }
                        }

                        Text {
                          visible: tdistRow.alreadyInToday
                          anchors.verticalCenter: parent.verticalCenter
                          text: "✓"
                          font.pixelSize: 11
                          color: "#4fc08d"
                        }

                        Rectangle {
                          visible: !tdistRow.alreadyInToday && (tdistHover.hovered || tdistRow.kbSelected)
                          anchors.verticalCenter: parent.verticalCenter
                          width: 22
                          height: 22
                          radius: 6
                          color: pullTodayArea.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: "+"
                            font.pixelSize: 14
                            color: root.tokens.ink || "#ffffff"
                          }

                          MouseArea {
                            id: pullTodayArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (root.service) root.service.importTodoistTaskToToday(tdistRow.tdist)
                          }
                        }

                        Text {
                          visible: tdistHover.hovered || tdistRow.kbSelected
                          anchors.verticalCenter: parent.verticalCenter
                          text: "▶"
                          font.pixelSize: 10
                          color: root.tokens.ink || "#ffffff"
                        }
                      }
                    }
                  }
                }
              }

              // Direct Todoist Task Creation Composer
              TaskComposer {
                id: todoistComposer
                width: parent.width
                mode: "todoist"
                defaultHorizon: {
                  var f = String(root.todoist.filter || "today | overdue").toLowerCase()
                  if (f === "no date") return "inbox"
                  return "today"
                }
                categories: root.service ? (root.service.categories || []) : []
                projects: root.todoist.projects || []
                busy: !!(root.service && root.service.todoistSyncing)
                kbFocused: root.kbPageActive && root.kbZone === "todoistComposer"
                tokens: root.tokens
                lang: root.lang
                fontFamily: root.fontFamily
                onRequestSchedulePicker: function(curSched, ax, ay) {
                  root._openSchedulePopoverAt("todoistComposer", curSched, todoistComposer, ax, ay)
                }
                onSubmitted: function(payload) {
                  if (!root.service) return
                  root.service.createTodoistTask(payload, function(res) {
                    if (res && res.todoistCreated) {
                      if (!res.todoistCreated.visibleInFilter) {
                        root.todoistNoticeText = Theme.t(
                          root.lang,
                          "✓ Todoist'e eklendi (aktif filtre dışında)",
                          "✓ Added to Todoist (outside active filter)"
                        )
                      } else {
                        root.todoistNoticeText = Theme.t(root.lang, "✓ Todoist'e eklendi", "✓ Added to Todoist")
                      }
                      todoistNoticeTimer.restart()
                    }
                  })
                }
              }
            }
          }

          // Optional THIS WEEK Markdown Card
          Rectangle {
            visible: root.weeklyConfigured
            width: parent.width
            height: weekInner.implicitHeight + 32
            radius: 14
            color: root.tokens.card || "#17171c"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

            Column {
              id: weekInner
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 16
              spacing: 12

              Item {
                width: parent.width
                height: 18

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: Theme.t(root.lang, "BU HAFTA", "THIS WEEK")
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.Bold
                  font.letterSpacing: 1.1
                  color: root.tokens.muted || "#888888"
                }

                Text {
                  visible: !!root.weekly.exists
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: (root.weekly.fileName || "") + " · " + (root.weekly.openCount || 0) + " " + Theme.t(root.lang, "açık", "open")
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.tokens.secondary || "#aaaaaa"
                }
              }

              Text {
                visible: !root.weekly.exists
                width: parent.width
                wrapMode: Text.WordWrap
                text: Theme.t(
                  root.lang,
                  "Bu haftanın Markdown dosyası bulunamadı. Ayarlar'dan yol şablonunu kontrol edebilirsin.",
                  "This week's Markdown file was not found. Check your path template in Settings."
                )
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.muted || "#777777"
              }

              Text {
                visible: !!root.weekly.exists && root.weeklyGroups.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: Theme.t(
                  root.lang,
                  "Bu haftanın tüm açık görevleri tamamlandı 🎉",
                  "No open tasks left in this week's file 🎉"
                )
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.secondary || "#aaaaaa"
              }

              Repeater {
                model: root.weeklyGroups.length
                delegate: Column {
                  readonly property var grp: root.weeklyGroups[index]
                  readonly property var grpCat: root._findCat(grp.categoryId)
                  width: weekInner.width
                  spacing: 4

                  Item {
                    width: parent.width
                    height: 20

                    Row {
                      anchors.left: parent.left
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 7

                      CategorySwatch {
                        visible: !!grpCat
                        anchors.verticalCenter: parent.verticalCenter
                        swatchSize: 14
                        swatchColor: grpCat ? (grpCat.color || "#4c8df0") : "#4c8df0"
                        emoji: grpCat ? (grpCat.emoji || "") : ""
                        iconName: grpCat ? (grpCat.icon || "") : ""
                        iconColor: grpCat ? (grpCat.iconColor || "") : ""
                      }

                      Rectangle {
                        visible: !grpCat
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: root.tokens.muted || "#666666"
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: grp.name || ""
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: Font.DemiBold
                        color: root.tokens.secondary || "#cccccc"
                      }
                    }

                    Text {
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      text: String(grp.tasks ? grp.tasks.length : 0)
                      font.family: "Monospace"
                      font.pixelSize: 10
                      color: root.tokens.muted || "#777777"
                    }
                  }

                  Repeater {
                    model: grp.tasks ? grp.tasks.length : 0
                    delegate: Column {
                      readonly property var wt: grp.tasks[index]
                      readonly property var prevWt: index > 0 ? grp.tasks[index - 1] : null
                      readonly property bool showSubHeader: !!(
                        wt.subgroup
                        && (Number(wt.depth) || 0) === 0
                        && (!prevWt || prevWt.subgroup !== wt.subgroup)
                      )
                      readonly property int indentPx: Math.min(2, Number(wt.depth) || 0) * 16
                      width: weekInner.width
                      spacing: 2

                      Text {
                        visible: showSubHeader
                        leftPadding: 6
                        topPadding: 3
                        text: wt.subgroup || ""
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                        color: root.tokens.muted || "#888888"
                      }

                      Rectangle {
                        id: wkRowRect
                        readonly property string navKey: "wk:" + String(wt.key || index)
                        readonly property int navIdx: root.navIndexByKey[navKey] !== undefined ? Number(root.navIndexByKey[navKey]) : -1
                        readonly property bool kbSelected: root.kbPageActive && root.kbActive && navIdx >= 0 && root.kbIndex === navIdx
                        onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(wkRowRect)
                        width: weekInner.width
                        height: Math.max(28, wtTitleTxt.implicitHeight + 10)
                        radius: 7
                        color: kbSelected
                          ? (root.tokens.raised || "#26262f")
                          : (wkRowArea.containsMouse ? (root.tokens.card2 || "#1f1f25") : "transparent")
                        border.width: kbSelected ? 1.5 : 0
                        border.color: root.tokens.ink || "#ffffff"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: 6 + indentPx
                          anchors.rightMargin: 8
                          spacing: 7

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wt.waiting ? "◌" : "○"
                            font.pixelSize: 12
                            color: root.tokens.muted || "#777777"
                          }

                          Text {
                            id: wtTitleTxt
                            width: Math.max(60, parent.width - ((wkRowArea.containsMouse || wkRowRect.kbSelected) ? 48 : 22))
                            anchors.verticalCenter: parent.verticalCenter
                            text: wt.title || ""
                            wrapMode: Text.WordWrap
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: wt.waiting ? (root.tokens.secondary || "#aaaaaa") : (root.tokens.ink || "#ffffff")
                          }

                          Text {
                            visible: wkRowArea.containsMouse || wkRowRect.kbSelected
                            anchors.verticalCenter: parent.verticalCenter
                            text: "▶"
                            font.pixelSize: 10
                            color: root.tokens.ink || "#ffffff"
                          }
                        }

                        MouseArea {
                          id: wkRowArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            if (root.service) {
                              root.service.openNewSessionForWeekly(wt)
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

        // RIGHT COLUMN: Day flow vertical hourly timeline
        Rectangle {
          width: parent.width - leftCol.width - 16
          height: Math.max(460, Math.min(620, dayFlowCol.implicitHeight + 66))
          radius: 14
          color: root.tokens.card || "#17171c"
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Item {
              width: parent.width
              height: 18

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.t(root.lang, "GÜN AKIŞI", "DAY FLOW")
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.1
                color: root.tokens.muted || "#888888"
              }

              Text {
                visible: !root.hasActive && root.timeline.length === 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.t(root.lang, "henüz oturum yok", "no sessions yet")
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.muted || "#777777"
              }
            }

            Flickable {
              width: parent.width
              height: parent.height - 28
              contentWidth: width
              contentHeight: dayFlowCol.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

              DayColumn {
                id: dayFlowCol
                width: parent.width
                sessions: root.timeline
                hasActiveSession: root.hasActive
                activeSessionId: root.service ? root.service.sessionId : 0
                activeCategoryName: root.activeCat ? (root.activeCat.name || "") : ""
                activeColor: root.activeCat ? (root.activeCat.color || "#4c8df0") : "#4c8df0"
                activeGoal: root.service ? root.service.sessionGoal : ""
                activeStartEpoch: root.service ? root.service.sessionStart : 0
                activeEndEpoch: root.service && root.service.sessionStart > 0
                  ? (root.service.sessionStart + Math.max(60, root.service.elapsedSeconds))
                  : 0
                tokens: root.tokens
                lang: root.lang
                fontFamily: root.fontFamily
              }
            }
          }
        }
      }
    }
  }

  // Click-outside backdrop + shared TaskSchedulePopover overlay
  MouseArea {
    visible: schedulePopover.open
    anchors.fill: parent
    z: 75
    onClicked: schedulePopover.cancelNow()
  }

  TaskSchedulePopover {
    id: schedulePopover
    z: 80
    tokens: root.tokens
    lang: root.lang
    fontFamily: root.fontFamily
    onApplied: function(sched) {
      if (root._popoverTargetKind === "localComposer") {
        localComposer.applySchedulePatch(sched)
        localComposer.focusTitle()
      } else if (root._popoverTargetKind === "todoistComposer") {
        todoistComposer.applySchedulePatch(sched)
        todoistComposer.focusTitle()
      } else if (root._popoverTargetKind === "editLocal" && root._popoverLocalTodoId > 0 && root.service) {
        root.service.updateTodo(root._popoverLocalTodoId, sched)
      } else if (root._popoverTargetKind === "editTodoist" && root._popoverTodoistId !== "" && root.service) {
        root.service.updateTodoistTask(root._popoverTodoistId, {
          scope: sched.scope,
          day: sched.day,
          endDay: sched.endDay,
          dueTime: sched.dueTime,
          recurrence: sched.recurrence,
          priority: sched.priority,
          clearDue: sched.scope === "inbox"
        }, null)
      }
    }
  }
}
