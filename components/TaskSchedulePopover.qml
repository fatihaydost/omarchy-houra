import QtQuick
import "../Theme.js" as Theme

// Todoist-style schedule, horizon (day / week / month / date range / undated), time, recurrence, and priority popover.
Rectangle {
  id: root

  property bool open: false
  property string titleText: ""
  property bool isTodoist: false
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"

  signal applied(var schedule)
  signal cancelled()

  visible: open
  width: 348
  height: mainCol.implicitHeight + 26
  radius: 12
  color: root.tokens.popup || "#141418"
  border.width: 1
  border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.18)
  z: 60

  property string draftScope: "day"     // "day" | "week" | "month" | "range" | "inbox"
  property string draftDay: ""
  property string draftEndDay: ""
  property string draftDueTime: ""
  property string draftRecurrence: ""   // "" | "daily" | "weekday" | "weekly" | "monthly"
  property int draftPriority: 1         // 4=P1, 3=P2, 2=P3, 1=P4
  property string pickingSide: "start"  // "start" | "end" (for "range")
  property int calYear: 2026
  property int calMonth: 10             // 1..12

  readonly property bool isEditingText: timeInput.activeFocus

  function releaseTextFocus() {
    if (timeInput.activeFocus) timeInput.focus = false
  }

  function _syncCalendarToDay(isoStr) {
    var d = isoStr ? Theme.parseIsoDay(isoStr) : new Date()
    calYear = d.getFullYear()
    calMonth = d.getMonth() + 1
  }

  function openFor(initObj) {
    var src = initObj || ({})
    var todayIso = Theme.toIsoDay(new Date())
    titleText = String(src.titleText || "")
    isTodoist = !!src.isTodoist
    var sc = String(src.scope || "day")
    if (["day", "week", "month", "range", "inbox"].indexOf(sc) === -1) sc = "day"
    draftScope = sc

    var baseDay = String(src.day || todayIso)
    if (sc === "week") {
      var wb = Theme.weekBoundsIso(baseDay)
      draftDay = wb.start
      draftEndDay = wb.end
    } else if (sc === "month") {
      var mb = Theme.monthBoundsIso(baseDay)
      draftDay = mb.start
      draftEndDay = mb.end
    } else if (sc === "range") {
      draftDay = baseDay
      draftEndDay = String(src.endDay || Theme.addDaysIso(baseDay, 3))
      if (draftEndDay < draftDay) draftEndDay = draftDay
    } else if (sc === "inbox") {
      draftDay = todayIso
      draftEndDay = ""
    } else {
      draftDay = baseDay
      draftEndDay = ""
    }

    draftDueTime = String(src.dueTime || "")
    timeInput.text = draftDueTime
    draftRecurrence = sc === "inbox" ? "" : String(src.recurrence || "")
    var pr = Number(src.priority) || 1
    draftPriority = Math.max(1, Math.min(4, pr))
    pickingSide = "start"
    _syncCalendarToDay(draftDay || todayIso)
    open = true
  }

  function _sanitizeTimeText(raw) {
    var s = String(raw || "").trim()
    if (!s) return ""
    var m = s.match(/^([01]?\d|2[0-3]):([0-5]\d)$/)
    if (!m) return ""
    var hh = Number(m[1])
    var mm = Number(m[2])
    return (hh < 10 ? ("0" + hh) : String(hh)) + ":" + (mm < 10 ? ("0" + mm) : String(mm))
  }

  function selectPreset(presetKey) {
    var todayIso = Theme.toIsoDay(new Date())
    if (presetKey === "today") {
      draftScope = "day"
      draftDay = todayIso
      draftEndDay = ""
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "tomorrow") {
      draftScope = "day"
      draftDay = Theme.addDaysIso(todayIso, 1)
      draftEndDay = ""
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "thisWeek") {
      draftScope = "week"
      var wb = Theme.weekBoundsIso(todayIso)
      draftDay = wb.start
      draftEndDay = wb.end
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "nextWeek") {
      draftScope = "week"
      var nwb = Theme.weekBoundsIso(Theme.addDaysIso(todayIso, 7))
      draftDay = nwb.start
      draftEndDay = nwb.end
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "thisMonth") {
      draftScope = "month"
      var mb = Theme.monthBoundsIso(todayIso)
      draftDay = mb.start
      draftEndDay = mb.end
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "nextMonth") {
      draftScope = "month"
      var nmFirst = Theme.shiftMonthFirstIso(todayIso, 1)
      var nmb = Theme.monthBoundsIso(nmFirst)
      draftDay = nmb.start
      draftEndDay = nmb.end
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "range") {
      draftScope = "range"
      var base = draftDay || todayIso
      draftDay = base
      if (!draftEndDay || draftEndDay <= draftDay) {
        draftEndDay = Theme.addDaysIso(base, 3)
      }
      pickingSide = "start"
      _syncCalendarToDay(draftDay)
    } else if (presetKey === "inbox") {
      draftScope = "inbox"
      draftDay = todayIso
      draftEndDay = ""
      draftDueTime = ""
      timeInput.text = ""
      draftRecurrence = ""
    }
  }

  function isPresetActive(presetKey) {
    var todayIso = Theme.toIsoDay(new Date())
    if (presetKey === "today") return draftScope === "day" && draftDay === todayIso
    if (presetKey === "tomorrow") return draftScope === "day" && draftDay === Theme.addDaysIso(todayIso, 1)
    if (presetKey === "thisWeek") return draftScope === "week" && draftDay === Theme.weekBoundsIso(todayIso).start
    if (presetKey === "nextWeek") return draftScope === "week" && draftDay === Theme.weekBoundsIso(Theme.addDaysIso(todayIso, 7)).start
    if (presetKey === "thisMonth") return draftScope === "month" && draftDay === Theme.monthBoundsIso(todayIso).start
    if (presetKey === "nextMonth") return draftScope === "month" && draftDay === Theme.monthBoundsIso(Theme.shiftMonthFirstIso(todayIso, 1)).start
    if (presetKey === "range") return draftScope === "range"
    if (presetKey === "inbox") return draftScope === "inbox"
    return false
  }

  function stepMonth(delta) {
    var m = calMonth + delta
    var y = calYear
    if (m < 1) { m = 12; y-- }
    if (m > 12) { m = 1; y++ }
    calYear = y
    calMonth = m
    if (draftScope === "month") {
      var mm = calMonth < 10 ? ("0" + calMonth) : String(calMonth)
      var mb = Theme.monthBoundsIso(calYear + "-" + mm + "-01")
      draftDay = mb.start
      draftEndDay = mb.end
    }
  }

  readonly property var monthCells: {
    var first = new Date(calYear, calMonth - 1, 1)
    var isoDow = first.getDay() === 0 ? 7 : first.getDay()
    var daysInMonth = new Date(calYear, calMonth, 0).getDate()
    var cells = []
    for (var pad = 1; pad < isoDow; pad++) cells.push({ day: 0, iso: "" })
    for (var dom = 1; dom <= daysInMonth; dom++) {
      var mm = calMonth < 10 ? ("0" + calMonth) : String(calMonth)
      var dd = dom < 10 ? ("0" + dom) : String(dom)
      cells.push({ day: dom, iso: calYear + "-" + mm + "-" + dd })
    }
    return cells
  }

  readonly property string summaryText: {
    if (draftScope === "inbox") return Theme.t(root.lang, "Tarihsiz (Kutu)", "Undated (Inbox)")
    var base = ""
    if (draftScope === "day") {
      base = Theme.formatShortDay(draftDay, root.lang)
    } else if (draftScope === "week") {
      base = Theme.t(root.lang, "Hafta · ", "Week · ") + Theme.formatShortDay(draftDay, root.lang) + "–" + Theme.formatShortDay(draftEndDay, root.lang)
    } else if (draftScope === "month") {
      var d = Theme.parseIsoDay(draftDay)
      base = Theme.monthFull(d.getMonth() + 1, root.lang) + " " + d.getFullYear()
    } else {
      base = Theme.formatShortDay(draftDay, root.lang) + " – " + Theme.formatShortDay(draftEndDay || draftDay, root.lang)
    }
    var cleanTm = _sanitizeTimeText(timeInput.text)
    if (cleanTm) base += " · " + cleanTm
    return base
  }

  function applyNow() {
    var cleanTm = draftScope === "inbox" ? "" : _sanitizeTimeText(timeInput.text)
    draftDueTime = cleanTm
    var outScope = draftScope
    var outDay = draftDay || Theme.toIsoDay(new Date())
    var outEnd = draftEndDay
    if (outScope === "range" && (!outEnd || outEnd === outDay)) {
      outScope = "day"
      outEnd = ""
    }
    root.open = false
    root.applied({
      scope: outScope,
      day: outDay,
      endDay: (outScope === "week" || outScope === "month" || outScope === "range") ? outEnd : "",
      dueTime: cleanTm,
      recurrence: outScope === "inbox" ? "" : draftRecurrence,
      priority: draftPriority
    })
  }

  function cancelNow() {
    releaseTextFocus()
    root.open = false
    root.cancelled()
  }

  function _nudgeDay(step) {
    if (draftScope === "inbox") return
    if (draftScope === "week") {
      var nw = Theme.weekBoundsIso(Theme.addDaysIso(draftDay, step > 0 ? 7 : -7))
      draftDay = nw.start
      draftEndDay = nw.end
      _syncCalendarToDay(draftDay)
      return
    }
    if (draftScope === "month") {
      stepMonth(step > 0 ? 1 : -1)
      return
    }
    if (draftScope === "range" && pickingSide === "end") {
      draftEndDay = Theme.addDaysIso(draftEndDay || draftDay, step)
      if (draftEndDay < draftDay) draftDay = draftEndDay
      _syncCalendarToDay(draftEndDay)
      return
    }
    draftDay = Theme.addDaysIso(draftDay || Theme.toIsoDay(new Date()), step)
    if (draftScope === "range" && draftEndDay < draftDay) draftEndDay = draftDay
    _syncCalendarToDay(draftDay)
  }

  function handleKey(event) {
    if (!root.open) return false
    var k = event.key
    if (k === Qt.Key_Escape) {
      if (timeInput.activeFocus) {
        timeInput.focus = false
        return true
      }
      cancelNow()
      return true
    }
    if (timeInput.activeFocus) {
      if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        timeInput.focus = false
        applyNow()
        return true
      }
      return false
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      applyNow()
      return true
    }
    if (k === Qt.Key_Left) { _nudgeDay(-1); return true }
    if (k === Qt.Key_Right) { _nudgeDay(1); return true }
    if (k === Qt.Key_Up) { _nudgeDay(-7); return true }
    if (k === Qt.Key_Down) { _nudgeDay(7); return true }
    return true
  }

  MouseArea {
    anchors.fill: parent
    onPressed: function(mouse) { mouse.accepted = true }
  }

  Column {
    id: mainCol
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 13
    spacing: 9

    // Header
    Item {
      width: parent.width
      height: 22

      Text {
        anchors.left: parent.left
        anchors.right: closeBtn.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.titleText !== ""
          ? root.titleText
          : Theme.t(root.lang, "Zaman & Önem", "Schedule & Priority")
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.tokens.ink || "#ffffff"
        elide: Text.ElideRight
      }

      Rectangle {
        id: closeBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 22
        height: 22
        radius: 6
        color: closeMa.containsMouse ? (root.tokens.card2 || "#222228") : "transparent"

        Text {
          anchors.centerIn: parent
          text: "✕"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.tokens.muted || "#8a8d96"
        }

        MouseArea {
          id: closeMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.cancelNow()
        }
      }
    }

    // Horizon quick presets (Flow of compact pills)
    Flow {
      width: parent.width
      spacing: 5

      Repeater {
        model: [
          { key: "today", tr: "Bugün", en: "Today" },
          { key: "tomorrow", tr: "Yarın", en: "Tomorrow" },
          { key: "thisWeek", tr: "Bu hafta", en: "This week" },
          { key: "nextWeek", tr: "Gelecek hf.", en: "Next week" },
          { key: "thisMonth", tr: "Bu ay", en: "This month" },
          { key: "nextMonth", tr: "Gelecek ay", en: "Next month" },
          { key: "range", tr: "Tarih aralığı", en: "Date range" },
          { key: "inbox", tr: "Tarihsiz", en: "Undated" }
        ]

        delegate: Rectangle {
          required property var modelData
          readonly property bool active: root.isPresetActive(modelData.key)
          width: presetLbl.implicitWidth + 16
          height: 24
          radius: 6
          color: active
            ? (root.tokens.primaryBg || "#ffffff")
            : (presetMa.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24"))
          border.width: 1
          border.color: active ? "transparent" : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Text {
            id: presetLbl
            anchors.centerIn: parent
            text: Theme.t(root.lang, modelData.tr, modelData.en)
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: active ? Font.DemiBold : Font.Medium
            color: active ? (root.tokens.primaryInk || "#0a0a0c") : (root.tokens.secondary || "#b4b4bc")
          }

          MouseArea {
            id: presetMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectPreset(modelData.key)
          }
        }
      }
    }

    // Range Start / End selector when in "range" mode
    Row {
      visible: root.draftScope === "range"
      width: parent.width
      spacing: 6

      Repeater {
        model: [
          { key: "start", label: Theme.t(root.lang, "Başlangıç", "From"), val: root.draftDay },
          { key: "end", label: Theme.t(root.lang, "Bitiş", "To"), val: root.draftEndDay }
        ]

        delegate: Rectangle {
          required property var modelData
          readonly property bool active: root.pickingSide === modelData.key
          width: (mainCol.width - 6) / 2
          height: 36
          radius: 7
          color: active ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24")
          border.width: 1
          border.color: active
            ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
            : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Column {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 9
            spacing: 1

            Text {
              text: modelData.label
              font.family: root.fontFamily
              font.pixelSize: 9
              color: root.tokens.muted || "#8a8d96"
            }

            Text {
              text: Theme.formatShortDay(modelData.val, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.pickingSide = modelData.key
              root._syncCalendarToDay(modelData.val)
            }
          }
        }
      }
    }

    // Calendar block (hidden for "inbox")
    Column {
      visible: root.draftScope !== "inbox"
      width: parent.width
      spacing: 4

      Item {
        width: parent.width
        height: 24

        Rectangle {
          width: 24
          height: 22
          radius: 6
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          color: prevCalMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent"

          Text {
            anchors.centerIn: parent
            text: "‹"
            font.family: root.fontFamily
            font.pixelSize: 14
            color: root.tokens.secondary || "#b4b4bc"
          }

          MouseArea {
            id: prevCalMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.stepMonth(-1)
          }
        }

        Text {
          anchors.centerIn: parent
          text: Theme.monthFull(root.calMonth, root.lang) + " " + root.calYear
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.tokens.ink || "#ffffff"
        }

        Rectangle {
          width: 24
          height: 22
          radius: 6
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          color: nextCalMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent"

          Text {
            anchors.centerIn: parent
            text: "›"
            font.family: root.fontFamily
            font.pixelSize: 14
            color: root.tokens.secondary || "#b4b4bc"
          }

          MouseArea {
            id: nextCalMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.stepMonth(1)
          }
        }
      }

      Row {
        width: parent.width
        Repeater {
          model: [1, 2, 3, 4, 5, 6, 7]
          delegate: Text {
            required property int modelData
            width: mainCol.width / 7
            horizontalAlignment: Text.AlignHCenter
            text: Theme.weekdayShort(modelData, root.lang)
            font.family: root.fontFamily
            font.pixelSize: 10
            color: root.tokens.muted || "#8a8d96"
          }
        }
      }

      Grid {
        width: parent.width
        columns: 7
        rowSpacing: 2

        Repeater {
          model: root.monthCells
          delegate: Item {
            required property var modelData
            width: mainCol.width / 7
            height: 26

            readonly property string cellIso: modelData.iso || ""
            readonly property string spanStart: root.draftDay
            readonly property string spanEnd: (root.draftScope === "week" || root.draftScope === "month" || root.draftScope === "range")
              ? (root.draftEndDay || root.draftDay)
              : root.draftDay
            readonly property bool isEdge: cellIso !== "" && (cellIso === spanStart || cellIso === spanEnd)
            readonly property bool inSpan: cellIso !== "" && spanStart !== "" && spanEnd !== "" && cellIso >= spanStart && cellIso <= spanEnd

            Rectangle {
              visible: modelData.day > 0
              anchors.centerIn: parent
              width: parent.width - 3
              height: 24
              radius: 6
              color: isEdge
                ? (root.tokens.primaryBg || "#ffffff")
                : (inSpan
                    ? (root.tokens.raised || "#282830")
                    : (dayCellMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent"))

              Text {
                anchors.centerIn: parent
                text: modelData.day > 0 ? String(modelData.day) : ""
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: isEdge ? Font.DemiBold : Font.Normal
                color: isEdge
                  ? (root.tokens.primaryInk || "#0a0a0c")
                  : (inSpan ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#b4b4bc"))
              }

              MouseArea {
                id: dayCellMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!cellIso) return
                  if (root.draftScope === "week") {
                    var wb = Theme.weekBoundsIso(cellIso)
                    root.draftDay = wb.start
                    root.draftEndDay = wb.end
                  } else if (root.draftScope === "month") {
                    var mb = Theme.monthBoundsIso(cellIso)
                    root.draftDay = mb.start
                    root.draftEndDay = mb.end
                  } else if (root.draftScope === "range") {
                    if (root.pickingSide === "start") {
                      root.draftDay = cellIso
                      if (!root.draftEndDay || root.draftEndDay < cellIso) root.draftEndDay = cellIso
                      root.pickingSide = "end"
                    } else {
                      root.draftEndDay = cellIso
                      if (root.draftEndDay < root.draftDay) root.draftDay = cellIso
                    }
                  } else {
                    root.draftScope = "day"
                    root.draftDay = cellIso
                    root.draftEndDay = ""
                  }
                }
              }
            }
          }
        }
      }
    }

    Rectangle {
      width: parent.width
      height: 1
      color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
    }

    // Time (HH:MM) + presets
    Row {
      visible: root.draftScope !== "inbox"
      width: parent.width
      spacing: 5

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        text: Theme.t(root.lang, "Saat", "Time")
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#8a8d96"
      }

      Rectangle {
        width: 68
        height: 26
        radius: 6
        color: root.tokens.card2 || "#1e1e24"
        border.width: 1
        border.color: timeInput.activeFocus
          ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.28))
          : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

        TextInput {
          id: timeInput
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          verticalAlignment: TextInput.AlignVCenter
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.tokens.ink || "#ffffff"
          maximumLength: 5
          selectByMouse: true
          clip: true
          onTextEdited: {
            var clean = root._sanitizeTimeText(text)
            if (clean) root.draftDueTime = clean
            else if (text.trim() === "") root.draftDueTime = ""
          }
        }

        Text {
          visible: timeInput.text.length === 0
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: 8
          text: Theme.t(root.lang, "SS:DD", "HH:MM")
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.tokens.muted || "#8a8d96"
        }
      }

      Repeater {
        model: ["09:00", "13:00", "18:00"]
        delegate: Rectangle {
          required property string modelData
          readonly property bool active: timeInput.text === modelData
          width: 44
          height: 26
          radius: 6
          color: active
            ? (root.tokens.raised || "#282830")
            : (tmChipMa.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24"))
          border.width: 1
          border.color: active
            ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
            : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Text {
            anchors.centerIn: parent
            text: modelData
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: active ? Font.DemiBold : Font.Normal
            color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#b4b4bc")
          }

          MouseArea {
            id: tmChipMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (timeInput.text === modelData) {
                timeInput.text = ""
                root.draftDueTime = ""
              } else {
                timeInput.text = modelData
                root.draftDueTime = modelData
              }
            }
          }
        }
      }

      Rectangle {
        visible: timeInput.text.length > 0
        width: 24
        height: 26
        radius: 6
        color: clrTmMa.containsMouse ? (root.tokens.raised || "#282830") : "transparent"

        Text {
          anchors.centerIn: parent
          text: "✕"
          font.family: root.fontFamily
          font.pixelSize: 10
          color: root.tokens.muted || "#8a8d96"
        }

        MouseArea {
          id: clrTmMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            timeInput.text = ""
            root.draftDueTime = ""
          }
        }
      }
    }

    // Recurrence pills
    Row {
      visible: root.draftScope !== "inbox"
      width: parent.width
      spacing: 4

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        text: Theme.t(root.lang, "Tekrar", "Repeat")
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#8a8d96"
      }

      Repeater {
        model: [
          { key: "", tr: "Yok", en: "None" },
          { key: "daily", tr: "Gün", en: "Day" },
          { key: "weekday", tr: "H.içi", en: "Wkday" },
          { key: "weekly", tr: "Hafta", en: "Week" },
          { key: "monthly", tr: "Ay", en: "Month" }
        ]

        delegate: Rectangle {
          required property var modelData
          readonly property bool active: root.draftRecurrence === modelData.key
          width: recLbl.implicitWidth + 12
          height: 24
          radius: 6
          color: active
            ? (root.tokens.primaryBg || "#ffffff")
            : (recMa.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24"))
          border.width: 1
          border.color: active ? "transparent" : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Text {
            id: recLbl
            anchors.centerIn: parent
            text: Theme.t(root.lang, modelData.tr, modelData.en)
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: active ? Font.DemiBold : Font.Medium
            color: active ? (root.tokens.primaryInk || "#0a0a0c") : (root.tokens.secondary || "#b4b4bc")
          }

          MouseArea {
            id: recMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.draftRecurrence = modelData.key
          }
        }
      }
    }

    // Priority (P1..P4)
    Row {
      width: parent.width
      spacing: 5

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 44
        text: Theme.t(root.lang, "Önem", "Priority")
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#8a8d96"
      }

      Repeater {
        model: [
          { prio: 4, label: "P1", tr: "Acil", en: "High" },
          { prio: 3, label: "P2", tr: "Yüksek", en: "Med+" },
          { prio: 2, label: "P3", tr: "Orta", en: "Med" },
          { prio: 1, label: "P4", tr: "Normal", en: "Low" }
        ]

        delegate: Rectangle {
          required property var modelData
          readonly property bool active: root.draftPriority === modelData.prio
          readonly property color pCol: Theme.priorityColor(modelData.prio, root.tokens.muted || "#8a8d96")
          width: 62
          height: 26
          radius: 6
          color: active
            ? Theme.withAlpha(pCol, 0.22)
            : (prMa.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24"))
          border.width: 1
          border.color: active ? pCol : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Row {
            anchors.centerIn: parent
            spacing: 4

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: 7
              height: 7
              radius: 4
              color: pCol
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.label
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: active ? Font.Bold : Font.Medium
              color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#b4b4bc")
            }
          }

          MouseArea {
            id: prMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.draftPriority = modelData.prio
          }
        }
      }
    }

    // Subtle Todoist note when week/month/range is chosen on a Todoist task
    Text {
      visible: root.isTodoist && (root.draftScope === "week" || root.draftScope === "month" || root.draftScope === "range")
      width: parent.width
      text: Theme.t(
        root.lang,
        "Todoist'te dönem bitiş tarihi olarak kaydedilir.",
        "Saved on Todoist using the period's end date."
      )
      font.family: root.fontFamily
      font.pixelSize: 10
      color: root.tokens.muted || "#8a8d96"
      wrapMode: Text.WordWrap
    }

    // Summary & Action buttons
    Item {
      width: parent.width
      height: 30

      Text {
        anchors.left: parent.left
        anchors.right: actionBtns.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.summaryText
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#8a8d96"
        elide: Text.ElideRight
      }

      Row {
        id: actionBtns
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Rectangle {
          width: cancelLbl.implicitWidth + 18
          height: 28
          radius: 7
          color: cancelActMa.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1e1e24")
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Text {
            id: cancelLbl
            anchors.centerIn: parent
            text: Theme.t(root.lang, "İptal", "Cancel")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.secondary || "#b4b4bc"
          }

          MouseArea {
            id: cancelActMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancelNow()
          }
        }

        Rectangle {
          width: applyLbl.implicitWidth + 20
          height: 28
          radius: 7
          color: root.tokens.primaryBg || "#ffffff"
          opacity: applyActMa.containsMouse ? 0.90 : 1.0

          Text {
            id: applyLbl
            anchors.centerIn: parent
            text: Theme.t(root.lang, "Uygula", "Apply")
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: root.tokens.primaryInk || "#0a0a0c"
          }

          MouseArea {
            id: applyActMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applyNow()
          }
        }
      }
    }
  }
}
