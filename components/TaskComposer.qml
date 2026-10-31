import QtQuick
import "../Theme.js" as Theme

// Reusable Todoist-style task composer for both local Houra tasks and remote Todoist tasks.
Column {
  id: root

  property string mode: "local"            // "local" | "todoist"
  property string defaultHorizon: "today"  // "today" | "week" | "month" | "upcoming" | "inbox"
  property var categories: []
  property var projects: []
  property bool busy: false
  property bool kbFocused: false
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"

  signal submitted(var taskPayload)
  signal requestSchedulePicker(var currentSchedule, real anchorX, real anchorY)

  spacing: 6

  property string draftScope: "day"
  property string draftDay: ""
  property string draftEndDay: ""
  property string draftDueTime: ""
  property string draftRecurrence: ""
  property int draftPriority: 1
  property int draftCategoryId: 0
  property string draftProjectId: ""
  property bool _scheduleManuallyChosen: false

  readonly property bool isEditingText: titleInput.activeFocus || detailInput.activeFocus

  function focusTitle() {
    titleInput.forceActiveFocus()
  }

  function releaseTextFocus() {
    if (titleInput.activeFocus) titleInput.focus = false
    if (detailInput.activeFocus) detailInput.focus = false
  }

  function applySchedulePatch(sched) {
    if (!sched) return
    draftScope = String(sched.scope || "day")
    draftDay = String(sched.day || "")
    draftEndDay = String(sched.endDay || "")
    draftDueTime = String(sched.dueTime || "")
    draftRecurrence = String(sched.recurrence || "")
    if (sched.priority !== undefined) {
      draftPriority = Math.max(1, Math.min(4, Number(sched.priority) || 1))
    }
    _scheduleManuallyChosen = true
  }

  function _resetToHorizon(hz) {
    var todayIso = Theme.toIsoDay(new Date())
    draftDueTime = ""
    draftRecurrence = ""
    if (hz === "week") {
      var wb = Theme.weekBoundsIso(todayIso)
      draftScope = "week"
      draftDay = wb.start
      draftEndDay = wb.end
    } else if (hz === "month") {
      var mb = Theme.monthBoundsIso(todayIso)
      draftScope = "month"
      draftDay = mb.start
      draftEndDay = mb.end
    } else if (hz === "upcoming") {
      draftScope = "day"
      draftDay = Theme.addDaysIso(todayIso, 1)
      draftEndDay = ""
    } else if (hz === "inbox") {
      draftScope = "inbox"
      draftDay = todayIso
      draftEndDay = ""
    } else {
      draftScope = "day"
      draftDay = todayIso
      draftEndDay = ""
    }
    _scheduleManuallyChosen = false
  }

  Component.onCompleted: _resetToHorizon(defaultHorizon)

  onDefaultHorizonChanged: {
    if (titleInput.text.trim() === "" && !_scheduleManuallyChosen) {
      _resetToHorizon(defaultHorizon)
    }
  }

  function _selectQuickHorizon(key) {
    var todayIso = Theme.toIsoDay(new Date())
    if (key === "today") {
      draftScope = "day"
      draftDay = todayIso
      draftEndDay = ""
    } else if (key === "tomorrow") {
      draftScope = "day"
      draftDay = Theme.addDaysIso(todayIso, 1)
      draftEndDay = ""
    } else if (key === "week") {
      var wb = Theme.weekBoundsIso(todayIso)
      draftScope = "week"
      draftDay = wb.start
      draftEndDay = wb.end
    } else if (key === "month") {
      var mb = Theme.monthBoundsIso(todayIso)
      draftScope = "month"
      draftDay = mb.start
      draftEndDay = mb.end
    } else if (key === "inbox") {
      draftScope = "inbox"
      draftDay = todayIso
      draftEndDay = ""
      draftDueTime = ""
      draftRecurrence = ""
    }
    _scheduleManuallyChosen = true
  }

  function _isQuickActive(key) {
    var todayIso = Theme.toIsoDay(new Date())
    if (key === "today") return draftScope === "day" && (draftDay === "" || draftDay === todayIso)
    if (key === "tomorrow") return draftScope === "day" && draftDay === Theme.addDaysIso(todayIso, 1)
    if (key === "week") return draftScope === "week" && draftDay === Theme.weekBoundsIso(todayIso).start
    if (key === "month") return draftScope === "month" && draftDay === Theme.monthBoundsIso(todayIso).start
    if (key === "inbox") return draftScope === "inbox"
    return false
  }

  readonly property bool hasCustomScheduleChip: {
    if (draftDueTime !== "" || draftRecurrence !== "") return true
    if (draftScope === "range") return true
    if (_isQuickActive("today") || _isQuickActive("tomorrow") || _isQuickActive("week") || _isQuickActive("month") || _isQuickActive("inbox")) {
      return false
    }
    return true
  }

  readonly property string customScheduleText: {
    var parts = []
    if (!_isQuickActive("today") && !_isQuickActive("tomorrow") && !_isQuickActive("week") && !_isQuickActive("month") && !_isQuickActive("inbox")) {
      if (draftScope === "range") {
        parts.push(Theme.formatShortDay(draftDay, root.lang) + "–" + Theme.formatShortDay(draftEndDay || draftDay, root.lang))
      } else if (draftScope === "week") {
        parts.push(Theme.t(root.lang, "Hf. ", "Wk ") + Theme.formatShortDay(draftDay, root.lang))
      } else if (draftScope === "month") {
        var dm = Theme.parseIsoDay(draftDay)
        parts.push(Theme.monthShort(dm.getMonth() + 1, root.lang) + " " + dm.getFullYear())
      } else if (draftDay) {
        parts.push(Theme.formatShortDay(draftDay, root.lang))
      }
    }
    if (draftDueTime !== "") parts.push(draftDueTime)
    if (draftRecurrence !== "") {
      if (draftRecurrence === "daily") parts.push(Theme.t(root.lang, "Her gün", "Daily"))
      else if (draftRecurrence === "weekday") parts.push(Theme.t(root.lang, "H.içi", "Wkday"))
      else if (draftRecurrence === "weekly") parts.push(Theme.t(root.lang, "Haftalık", "Weekly"))
      else if (draftRecurrence === "monthly") parts.push(Theme.t(root.lang, "Aylık", "Monthly"))
    }
    return parts.length > 0 ? ("🗓 " + parts.join(" · ")) : Theme.t(root.lang, "🗓 Saat / Aralık", "🗓 Time / Dates")
  }

  readonly property var selectedCategory: {
    if (draftCategoryId <= 0) return null
    var list = root.categories || []
    for (var i = 0; i < list.length; i++) {
      if (Number(list[i].id) === draftCategoryId) return list[i]
    }
    return null
  }

  readonly property var selectedProject: {
    if (!draftProjectId) return null
    var list = root.projects || []
    for (var i = 0; i < list.length; i++) {
      if (String(list[i].id) === draftProjectId) return list[i]
    }
    return null
  }

  function _cycleBucket() {
    if (root.mode === "todoist" && (root.projects || []).length > 0) {
      var plist = root.projects
      if (!draftProjectId) {
        draftProjectId = String(plist[0].id)
        return
      }
      for (var i = 0; i < plist.length; i++) {
        if (String(plist[i].id) === draftProjectId) {
          draftProjectId = (i + 1 < plist.length) ? String(plist[i + 1].id) : ""
          return
        }
      }
      draftProjectId = ""
      return
    }
    var clist = root.categories || []
    if (clist.length === 0) return
    if (draftCategoryId <= 0) {
      draftCategoryId = Number(clist[0].id)
      return
    }
    for (var c = 0; c < clist.length; c++) {
      if (Number(clist[c].id) === draftCategoryId) {
        draftCategoryId = (c + 1 < clist.length) ? Number(clist[c + 1].id) : 0
        return
      }
    }
    draftCategoryId = 0
  }

  function submitNow() {
    if (root.busy) return
    var t = titleInput.text.trim()
    if (!t) return
    var d = detailInput.text.trim()
    var todayIso = Theme.toIsoDay(new Date())
    root.submitted({
      title: t,
      detail: d,
      scope: draftScope || "day",
      day: draftDay || todayIso,
      endDay: draftEndDay || "",
      dueTime: draftScope === "inbox" ? "" : draftDueTime,
      recurrence: draftScope === "inbox" ? "" : draftRecurrence,
      priority: draftPriority,
      categoryId: draftCategoryId,
      projectId: draftProjectId
    })
    titleInput.text = ""
    detailInput.text = ""
    draftPriority = 1
    _resetToHorizon(root.defaultHorizon)
  }

  // Row 1: Title + Detail + Add button
  Row {
    width: parent.width
    spacing: 6

    Rectangle {
      width: Math.max(150, parent.width - 172)
      height: 32
      radius: 7
      color: root.tokens.card2 || "#1e1e24"
      border.width: (root.kbFocused && !root.isEditingText) ? 2 : 1
      border.color: (titleInput.activeFocus || root.kbFocused)
        ? (root.tokens.accent || root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.30))
        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

      TextInput {
        id: titleInput
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.fontFamily
        font.pixelSize: 12
        color: root.tokens.ink || "#ffffff"
        selectByMouse: true
        clip: true
        onAccepted: root.submitNow()
        Keys.onTabPressed: detailInput.forceActiveFocus()
      }

      Text {
        textFormat: Text.PlainText
        visible: titleInput.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.right: parent.right
        anchors.rightMargin: 10
        text: root.mode === "todoist"
          ? Theme.t(root.lang, "Todoist'e görev ekle… (p1..p4, 14:30)", "Add task to Todoist… (p1..p4, 14:30)")
          : Theme.t(root.lang, "Görev ekle… (p1..p4, 14:30)", "Add task… (p1..p4, 14:30)")
        font.family: root.fontFamily
        font.pixelSize: 12
        color: root.tokens.muted || "#8a8d96"
        elide: Text.ElideRight
      }
    }

    Rectangle {
      width: 126
      height: 32
      radius: 7
      color: root.tokens.card2 || "#1e1e24"
      border.width: 1
      border.color: detailInput.activeFocus
        ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

      TextInput {
        id: detailInput
        anchors.fill: parent
        anchors.leftMargin: 9
        anchors.rightMargin: 9
        verticalAlignment: TextInput.AlignVCenter
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.secondary || "#b4b4bc"
        selectByMouse: true
        clip: true
        onAccepted: root.submitNow()
        Keys.onBacktabPressed: titleInput.forceActiveFocus()
      }

      Text {
        textFormat: Text.PlainText
        visible: detailInput.text.length === 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 9
        text: Theme.t(root.lang, "Detay / not", "Detail / note")
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#8a8d96"
      }
    }

    Rectangle {
      width: 34
      height: 32
      radius: 7
      color: addBtnMa.containsMouse ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.raised || "#282830")
      opacity: root.busy ? 0.5 : 1.0

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: root.busy ? "…" : "+"
        font.family: root.fontFamily
        font.pixelSize: 15
        font.weight: Font.Medium
        color: addBtnMa.containsMouse ? (root.tokens.primaryInk || "#0a0a0c") : (root.tokens.ink || "#ffffff")
      }

      MouseArea {
        id: addBtnMa
        anchors.fill: parent
        hoverEnabled: true
        enabled: !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.submitNow()
      }
    }
  }

  // Row 2: Compact Todoist horizon + date/time + P1..P4 + category/project pills
  Flow {
    width: parent.width
    spacing: 5

    Repeater {
      model: [
        { key: "today", tr: "Bugün", en: "Today" },
        { key: "tomorrow", tr: "Yarın", en: "Tomorrow" },
        { key: "week", tr: "Hafta", en: "Week" },
        { key: "month", tr: "Ay", en: "Month" },
        { key: "inbox", tr: "Tarihsiz", en: "Undated" }
      ]

      delegate: Rectangle {
        required property var modelData
        readonly property bool active: root._isQuickActive(modelData.key)
        width: hzChipTxt.implicitWidth + 13
        height: 22
        radius: 6
        color: active
          ? (root.tokens.raised || "#282830")
          : (hzChipMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent")
        border.width: 1
        border.color: active
          ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
          : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

        Text {
          textFormat: Text.PlainText
          id: hzChipTxt
          anchors.centerIn: parent
          text: Theme.t(root.lang, modelData.tr, modelData.en)
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: active ? Font.DemiBold : Font.Normal
          color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#8a8d96")
        }

        MouseArea {
          id: hzChipMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root._selectQuickHorizon(modelData.key)
        }
      }
    }

    // Calendar / Time / Range / Recurrence popover trigger
    Rectangle {
      id: calTriggerPill
      width: calTrigTxt.implicitWidth + 14
      height: 22
      radius: 6
      color: root.hasCustomScheduleChip
        ? Theme.withAlpha(root.tokens.accent || "#ffffff", 0.16)
        : (calTrigMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent")
      border.width: 1
      border.color: root.hasCustomScheduleChip
        ? (root.tokens.accent || root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.28))
        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

      Text {
        textFormat: Text.PlainText
        id: calTrigTxt
        anchors.centerIn: parent
        text: root.customScheduleText
        font.family: root.fontFamily
        font.pixelSize: 10
        font.weight: root.hasCustomScheduleChip ? Font.DemiBold : Font.Normal
        color: root.hasCustomScheduleChip ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#b4b4bc")
      }

      MouseArea {
        id: calTrigMa
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          root.requestSchedulePicker({
            scope: root.draftScope,
            day: root.draftDay || Theme.toIsoDay(new Date()),
            endDay: root.draftEndDay,
            dueTime: root.draftDueTime,
            recurrence: root.draftRecurrence,
            priority: root.draftPriority,
            isTodoist: root.mode === "todoist",
            titleText: root.mode === "todoist"
              ? Theme.t(root.lang, "Todoist görevi planla", "Schedule Todoist task")
              : Theme.t(root.lang, "Görev zamanı & önemi", "Task schedule & priority")
          }, calTriggerPill.x, calTriggerPill.y + calTriggerPill.height + 6)
        }
      }
    }

    // Priority P1..P4 pills
    Repeater {
      model: [4, 3, 2, 1]
      delegate: Rectangle {
        required property int modelData
        readonly property bool active: root.draftPriority === modelData
        readonly property color pCol: Theme.priorityColor(modelData, root.tokens.muted || "#8a8d96")
        width: 28
        height: 22
        radius: 6
        color: active
          ? Theme.withAlpha(pCol, 0.22)
          : (pChipMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent")
        border.width: 1
        border.color: active ? pCol : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: Theme.priorityLabel(modelData)
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: active ? Font.Bold : Font.Medium
          color: (active || modelData > 1) ? pCol : (root.tokens.muted || "#8a8d96")
        }

        MouseArea {
          id: pChipMa
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.draftPriority = (root.draftPriority === modelData && modelData !== 1) ? 1 : modelData
        }
      }
    }

    // Category (local) or #Project (todoist) selector pill
    Rectangle {
      visible: (root.mode === "todoist" && (root.projects || []).length > 0) || (root.categories || []).length > 0
      width: bucketRow.implicitWidth + 14
      height: 22
      radius: 6
      color: (root.selectedCategory || root.selectedProject)
        ? (root.tokens.card2 || "#1e1e24")
        : (bucketMa.containsMouse ? (root.tokens.card2 || "#1e1e24") : "transparent")
      border.width: 1
      border.color: (root.selectedCategory || root.selectedProject)
        ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.22))
        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

      Row {
        id: bucketRow
        anchors.centerIn: parent
        spacing: 4

        Rectangle {
          visible: root.selectedCategory !== null && root.mode !== "todoist"
          anchors.verticalCenter: parent.verticalCenter
          width: 6
          height: 6
          radius: 3
          color: root.selectedCategory ? root.selectedCategory.color : "#8a8d96"
        }

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (root.mode === "todoist" && (root.projects || []).length > 0) {
              return root.selectedProject
                ? ("#" + root.selectedProject.name)
                : Theme.t(root.lang, "#Inbox", "#Inbox")
            }
            return root.selectedCategory
              ? root.selectedCategory.name
              : Theme.t(root.lang, "#Kategori", "#Category")
          }
          font.family: root.fontFamily
          font.pixelSize: 10
          color: (root.selectedCategory || root.selectedProject)
            ? (root.tokens.ink || "#ffffff")
            : (root.tokens.muted || "#8a8d96")
        }
      }

      MouseArea {
        id: bucketMa
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: function(mouse) {
          if (mouse.button === Qt.RightButton) {
            root.draftCategoryId = 0
            root.draftProjectId = ""
          } else {
            root._cycleBucket()
          }
        }
      }
    }
  }
}
