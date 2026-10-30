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
  property string focusArea: "list" // "notesFilter" | "categoryFilter" | "list"
  readonly property bool isEditingText: false

  onKbPageActiveChanged: {
    if (!kbPageActive) focusArea = "list"
  }

  readonly property var categories: service ? service.categories : []
  readonly property var historyDays: service ? service.historyData : []
  readonly property bool notesOnly: service ? service.historyNotesOnly : false
  readonly property int filterTopicId: service ? service.historyTopicId : 0
  readonly property string filterDay: service ? service.historyDayFilter : ""

  property var expandedMap: ({})
  property int confirmDeleteId: 0

  readonly property var flatBundle: {
    var list = []
    var idxMap = ({})
    for (var d = 0; d < historyDays.length; d++) {
      var sess = historyDays[d].sessions || []
      for (var i = 0; i < sess.length; i++) {
        var s = sess[i]
        idxMap[String(s.id)] = list.length
        list.push(s)
      }
    }
    return { list: list, indexById: idxMap }
  }
  readonly property var flatSessions: flatBundle.list
  readonly property var sessionNavIndexById: flatBundle.indexById

  onFlatSessionsChanged: {
    if (flatSessions.length === 0) kbIndex = 0
    else if (kbIndex >= flatSessions.length) kbIndex = flatSessions.length - 1
  }

  function releaseTextFocus() { return false }

  function hasOpenOverlay() { return false }

  function _focusStops() {
    var stops = ["notesFilter"]
    if (categories.length > 0) stops.push("categoryFilter")
    stops.push("list")
    return stops
  }

  function _applyStop(stop) {
    focusArea = stop
    if (stop === "notesFilter" || stop === "categoryFilter") {
      sessionsFlick.contentY = 0
    } else {
      kbActive = true
    }
  }

  function enterFromTab(delta) {
    var stops = _focusStops()
    _applyStop(delta >= 0 ? stops[0] : stops[stops.length - 1])
  }

  function stepFocus(delta) {
    var stops = _focusStops()
    var idx = stops.indexOf(focusArea)
    if (idx < 0) idx = (delta >= 0 ? -1 : stops.length)
    var next = idx + delta
    if (next < 0 || next >= stops.length) return false
    _applyStop(stops[next])
    return true
  }

  function dismissOverlay() {
    if (confirmDeleteId !== 0) {
      deleteResetTimer.stop()
      confirmDeleteId = 0
      return true
    }
    return false
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, sessionsFlick.contentHeight - sessionsFlick.height)
    sessionsFlick.contentY = Math.max(0, Math.min(maxY, sessionsFlick.contentY + dy))
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(sessionsFlick.contentItem, 0, 0)
    var top = pt.y - 28
    var bot = pt.y + item.height + 28
    if (top < sessionsFlick.contentY) {
      sessionsFlick.contentY = Math.max(0, top)
    } else if (bot > sessionsFlick.contentY + sessionsFlick.height) {
      var maxY = Math.max(0, sessionsFlick.contentHeight - sessionsFlick.height)
      sessionsFlick.contentY = Math.min(maxY, bot - sessionsFlick.height)
    }
  }

  function cycleCategoryFilter(delta) {
    if (!service) return
    var ids = [0]
    for (var i = 0; i < categories.length; i++) ids.push(Number(categories[i].id))
    var cur = ids.indexOf(filterTopicId)
    if (cur < 0) cur = 0
    var next = (cur + delta + ids.length) % ids.length
    service.setHistoryFilter(notesOnly, ids[next], filterDay)
  }

  function handleKey(event) {
    var k = event.key
    var count = flatSessions.length

    if (focusArea === "notesFilter") {
      if ((k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) && service) {
        service.setHistoryFilter(!notesOnly, filterTopicId, filterDay)
        return true
      }
      if (k === Qt.Key_Down) { _applyStop("list"); return true }
      return false
    }

    if (focusArea === "categoryFilter") {
      if (k === Qt.Key_Left) { cycleCategoryFilter(-1); return true }
      if (k === Qt.Key_Right) { cycleCategoryFilter(1); return true }
      if (k === Qt.Key_Down) { _applyStop("list"); return true }
      return false
    }

    if (k === Qt.Key_Left) {
      return "sidebar"
    }
    if (k === Qt.Key_Down) {
      if (count > 0) {
        if (!kbActive || !kbPageActive) kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        else kbIndex = Math.min(count - 1, kbIndex + 1)
        kbActive = true
      } else {
        scrollBy(64)
      }
      return true
    }
    if (k === Qt.Key_Up) {
      if (count > 0) {
        if (!kbActive || !kbPageActive) kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        else kbIndex = Math.max(0, kbIndex - 1)
        kbActive = true
      } else {
        scrollBy(-64)
      }
      return true
    }
    if (k === Qt.Key_PageDown) { scrollBy(Math.round(sessionsFlick.height * 0.72)); return true }
    if (k === Qt.Key_PageUp) { scrollBy(-Math.round(sessionsFlick.height * 0.72)); return true }
    if (k === Qt.Key_Home) {
      kbActive = true
      kbIndex = 0
      sessionsFlick.contentY = 0
      return true
    }
    if (k === Qt.Key_End) {
      kbActive = true
      if (count > 0) kbIndex = count - 1
      return true
    }
    if ((k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) && count > 0) {
      kbActive = true
      var s = flatSessions[Math.max(0, Math.min(count - 1, kbIndex))]
      if (s) toggleExpanded(s.id)
      return true
    }
    if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && count > 0 && service) {
      kbActive = true
      var target = flatSessions[Math.max(0, Math.min(count - 1, kbIndex))]
      if (target) {
        var sid = Number(target.id)
        if (confirmDeleteId !== sid) {
          confirmDeleteId = sid
          deleteResetTimer.restart()
        } else {
          deleteResetTimer.stop()
          confirmDeleteId = 0
          service.deleteSession(sid)
        }
      }
      return true
    }
    return false
  }

  Timer {
    id: deleteResetTimer
    interval: 3500
    repeat: false
    onTriggered: root.confirmDeleteId = 0
  }

  function isExpanded(sid) {
    return !!expandedMap[String(sid)]
  }

  function toggleExpanded(sid) {
    var key = String(sid)
    var next = ({})
    for (var k in expandedMap) next[k] = expandedMap[k]
    if (next[key]) delete next[key]
    else next[key] = true
    expandedMap = next
  }

  Flickable {
    id: sessionsFlick
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
      spacing: 18

      // Header: SESSIONS eyebrow + History title + [All | With notes] segmented top-right
      Item {
        width: parent.width
        height: 44

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3

          Text {
            text: Theme.t(root.lang, "OTURUMLAR", "SESSIONS")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.3
            color: root.tokens.muted || "#888888"
          }

          Text {
            text: Theme.t(root.lang, "Geçmiş", "History")
            font.family: root.fontFamily
            font.pixelSize: 26
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }
        }

        // [All | With notes] segmented control
        Rectangle {
          readonly property bool kbFocused: root.kbPageActive && root.focusArea === "notesFilter"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 32
          width: notesSegRow.implicitWidth + 6
          radius: 9
          color: root.tokens.card || "#17171c"
          border.width: kbFocused ? 1.5 : 1
          border.color: kbFocused ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.09))

          Row {
            id: notesSegRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
              model: [
                { onlyNotes: false, label: Theme.t(root.lang, "Tümü", "All") },
                { onlyNotes: true, label: Theme.t(root.lang, "Notlular", "With notes") }
              ]
              delegate: Rectangle {
                readonly property bool active: root.notesOnly === modelData.onlyNotes
                width: nfTxt.implicitWidth + 20
                height: 26
                radius: 7
                color: active ? (root.tokens.raised || "#2b2b33") : "transparent"

                Text {
                  id: nfTxt
                  anchors.centerIn: parent
                  text: modelData.label
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  font.weight: parent.active ? Font.DemiBold : Font.Normal
                  color: parent.active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#aaaaaa")
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.service) root.service.setHistoryFilter(modelData.onlyNotes, root.filterTopicId, root.filterDay)
                }
              }
            }
          }
        }
      }

      // Filter bar: All categories chip + Day chip + Category chips with CategorySwatch(14)
      Flow {
        width: parent.width
        spacing: 8

        Rectangle {
          readonly property bool active: root.filterTopicId === 0
          readonly property bool kbFocused: active && root.kbPageActive && root.focusArea === "categoryFilter"
          width: allCatsTxt.implicitWidth + 20
          height: 28
          radius: 14
          color: active ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card || "#17171c")
          border.width: kbFocused ? 2 : 1
          border.color: kbFocused ? (root.tokens.accent || "#3d8cff") : (active ? "transparent" : (root.tokens.line || Qt.rgba(1, 1, 1, 0.09)))

          Text {
            id: allCatsTxt
            anchors.centerIn: parent
            text: Theme.t(root.lang, "Tüm kategoriler", "All categories")
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: parent.active ? Font.DemiBold : Font.Normal
            color: parent.active ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#bbbbbb")
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.setHistoryFilter(root.notesOnly, 0, root.filterDay)
          }
        }

        // Day filter chip (when jumped from DayDrawer)
        Rectangle {
          visible: root.filterDay !== ""
          width: dayChipLbl.implicitWidth + 20
          height: 28
          radius: 14
          color: root.tokens.raised || "#2b2b33"
          border.width: 1
          border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.2)

          Text {
            id: dayChipLbl
            anchors.centerIn: parent
            text: root.filterDay + "  ×"
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.ink || "#ffffff"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.setHistoryFilter(root.notesOnly, root.filterTopicId, "")
          }
        }

        // Category filter chips
        Repeater {
          model: root.categories.length
          delegate: Rectangle {
            id: catFilterChip
            readonly property var cat: root.categories[index]
            readonly property bool active: root.filterTopicId === Number(cat.id)
            readonly property bool kbFocused: active && root.kbPageActive && root.focusArea === "categoryFilter"
            width: catRow.implicitWidth + 18
            height: 28
            radius: 14
            color: active
              ? Theme.withAlpha(cat.color || "#4c8df0", 0.24)
              : (root.tokens.card || "#17171c")
            border.width: kbFocused ? 2 : 1
            border.color: kbFocused ? (root.tokens.ink || "#ffffff") : (active ? (cat.color || "#4c8df0") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08)))

            Row {
              id: catRow
              anchors.centerIn: parent
              spacing: 6

              CategorySwatch {
                anchors.verticalCenter: parent.verticalCenter
                swatchSize: 14
                swatchColor: cat.color || "#4c8df0"
                emoji: cat.emoji || ""
                iconName: cat.icon || ""
                iconColor: cat.iconColor || ""
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: cat.name
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: catFilterChip.active ? Font.DemiBold : Font.Normal
                color: root.tokens.ink || "#ffffff"
              }
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (root.service) {
                  var nextId = active ? 0 : Number(cat.id)
                  root.service.setHistoryFilter(root.notesOnly, nextId, root.filterDay)
                }
              }
            }
          }
        }
      }

      // Empty state
      Rectangle {
        visible: root.historyDays.length === 0
        width: parent.width
        height: 110
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Text {
          anchors.centerIn: parent
          text: Theme.t(root.lang, "Seçili filtreyle eşleşen oturum bulunamadı.", "No sessions match the current filter.")
          font.family: root.fontFamily
          font.pixelSize: 13
          color: root.tokens.muted || "#777777"
        }
      }

      // Day groups
      Repeater {
        model: root.historyDays.length
        delegate: Column {
          readonly property var dgrp: root.historyDays[index]
          width: pageCol.width
          spacing: 8

          Item {
            width: parent.width
            height: 22

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.formatDayHeading(dgrp.day, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: Font.DemiBold
              color: root.tokens.secondary || "#cccccc"
            }

            Text {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.formatMinutes(dgrp.totalMinutes || 0, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 12
              color: root.tokens.muted || "#888888"
            }
          }

          Repeater {
            model: dgrp.sessions ? dgrp.sessions.length : 0
            delegate: Rectangle {
              id: sessCard
              readonly property var s: dgrp.sessions[index]
              readonly property bool expanded: root.isExpanded(s.id)
              readonly property bool hasDetails: (s.note && s.note.length > 0) || (s.todos && s.todos.length > 0)
              readonly property int navIdx: root.sessionNavIndexById[String(s.id)] !== undefined
                ? Number(root.sessionNavIndexById[String(s.id)])
                : -1
              readonly property bool kbSelected: root.kbPageActive && root.focusArea === "list" && root.kbActive && navIdx >= 0 && root.kbIndex === navIdx
              onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(sessCard)
              width: pageCol.width
              height: rowCol.implicitHeight + 22
              radius: 12
              color: kbSelected
                ? (root.tokens.raised || "#26262f")
                : (sHover.hovered ? (root.tokens.card2 || "#1f1f25") : (root.tokens.card || "#17171c"))
              border.width: kbSelected ? 1.5 : 1
              border.color: kbSelected
                ? (root.tokens.ink || "#ffffff")
                : (expanded
                  ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.18))
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08)))

              HoverHandler { id: sHover }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleExpanded(s.id)
              }

              Column {
                id: rowCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 11
                spacing: 8

                Item {
                  width: parent.width
                  height: 24

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    CategorySwatch {
                      anchors.verticalCenter: parent.verticalCenter
                      swatchSize: 22
                      swatchColor: s.color || "#4c8df0"
                      emoji: s.emoji || ""
                      iconName: s.icon || ""
                      iconColor: s.iconColor || ""
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: s.categoryName
                      font.family: root.fontFamily
                      font.pixelSize: 13
                      font.weight: Font.DemiBold
                      color: root.tokens.ink || "#ffffff"
                    }

                    Text {
                      visible: (s.goal || "").length > 0 && s.goal !== s.categoryName
                      anchors.verticalCenter: parent.verticalCenter
                      text: "·  " + s.goal
                      width: Math.min(280, implicitWidth)
                      elide: Text.ElideRight
                      font.family: root.fontFamily
                      font.pixelSize: 13
                      color: root.tokens.secondary || "#bbbbbb"
                    }

                    Rectangle {
                      visible: !!s.emergency
                      anchors.verticalCenter: parent.verticalCenter
                      width: emBadge.implicitWidth + 10
                      height: 18
                      radius: 5
                      color: Theme.withAlpha(root.tokens.danger || "#e06458", 0.18)

                      Text {
                        id: emBadge
                        anchors.centerIn: parent
                        text: Theme.t(root.lang, "acil çıkış", "early exit")
                        font.family: root.fontFamily
                        font.pixelSize: 9
                        color: root.tokens.danger || "#e06458"
                      }
                    }
                  }

                  Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                      visible: (s.note || "").length > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: "📝"
                      font.pixelSize: 11
                    }

                    Text {
                      visible: (Number(s.todosTotal) || 0) > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: (s.todosDone || 0) + "/" + (s.todosTotal || 0) + " " + Theme.t(root.lang, "görev", "tasks")
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      color: root.tokens.muted || "#888888"
                    }

                    Text {
                      visible: (s.rhythmLabel || "").length > 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: s.rhythmLabel || ""
                      font.family: "Monospace"
                      font.pixelSize: 10
                      color: root.tokens.muted || "#777777"
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      text: Theme.formatHM(s.start) + " – " + Theme.formatHM(s.end)
                      font.family: "Monospace"
                      font.pixelSize: 11
                      color: root.tokens.muted || "#888888"
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      width: 62
                      horizontalAlignment: Text.AlignRight
                      text: Theme.formatMinutesShort(s.focusMinutes || 0, root.lang)
                      font.family: "Monospace"
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                      color: root.tokens.ink || "#ffffff"
                    }

                    Rectangle {
                      readonly property bool confirming: root.confirmDeleteId === Number(s.id)
                      visible: sHover.hovered || expanded || confirming || sessCard.kbSelected
                      anchors.verticalCenter: parent.verticalCenter
                      width: delSessionLbl.implicitWidth + 14
                      height: 22
                      radius: 6
                      color: confirming
                        ? (delSessionArea.containsMouse ? (root.tokens.danger || "#e06458") : Theme.withAlpha(root.tokens.danger || "#e06458", 0.24))
                        : (delSessionArea.containsMouse ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.14) : (root.tokens.card2 || "#1f1f25"))
                      border.width: 1
                      border.color: confirming || delSessionArea.containsMouse
                        ? (root.tokens.danger || "#e06458")
                        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.10))

                      Text {
                        id: delSessionLbl
                        anchors.centerIn: parent
                        text: parent.confirming
                          ? Theme.t(root.lang, "Silinsin mi?", "Confirm?")
                          : Theme.t(root.lang, "Sil", "Delete")
                        font.family: root.fontFamily
                        font.pixelSize: 10
                        font.weight: parent.confirming ? Font.DemiBold : Font.Normal
                        color: parent.confirming
                          ? (delSessionArea.containsMouse ? "#ffffff" : (root.tokens.danger || "#e06458"))
                          : (delSessionArea.containsMouse ? (root.tokens.danger || "#e06458") : (root.tokens.muted || "#888888"))
                      }

                      MouseArea {
                        id: delSessionArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          var sid = Number(s.id)
                          if (root.confirmDeleteId !== sid) {
                            root.confirmDeleteId = sid
                            deleteResetTimer.restart()
                          } else {
                            deleteResetTimer.stop()
                            root.confirmDeleteId = 0
                            if (root.service) root.service.deleteSession(sid)
                          }
                        }
                      }
                    }
                  }
                }

                // Expanded details: attached tasks & framed note card
                Column {
                  visible: expanded
                  width: parent.width
                  spacing: 8

                  Rectangle {
                    width: parent.width
                    height: 1
                    color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
                  }

                  Repeater {
                    model: (expanded && s.todos) ? s.todos.length : 0
                    delegate: Row {
                      readonly property var stodo: s.todos[index]
                      width: rowCol.width
                      spacing: 8
                      Text { text: Theme.todoEmoji(stodo.state); font.pixelSize: 13 }
                      Text {
                        width: parent.width - 26
                        wrapMode: Text.WordWrap
                        text: stodo.detail ? (stodo.title + " — " + stodo.detail) : stodo.title
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: root.tokens.secondary || "#cccccc"
                      }
                    }
                  }

                  Rectangle {
                    visible: (s.note || "").length > 0
                    width: parent.width
                    height: noteBodyTxt.implicitHeight + 20
                    radius: 8
                    color: root.tokens.card2 || "#1f1f25"
                    border.width: 1
                    border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

                    Text {
                      id: noteBodyTxt
                      anchors.fill: parent
                      anchors.margins: 10
                      wrapMode: Text.WordWrap
                      text: s.note || ""
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      color: root.tokens.ink || "#ffffff"
                    }
                  }

                  Text {
                    visible: !hasDetails
                    text: Theme.t(root.lang, "Bu oturuma ait görev veya not yok.", "No tasks or notes attached to this session.")
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    color: root.tokens.muted || "#777777"
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
