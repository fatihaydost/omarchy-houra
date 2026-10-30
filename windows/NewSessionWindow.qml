import QtQuick
import Quickshell
import Quickshell.Hyprland
import "../Theme.js" as Theme
import "../components"

// Native Wayland FloatingWindow modal for starting a new focus session (NewSession.swift parity + custom rhythm):
// - Fixed min/max size hints (`minimumSize === maximumSize`) make Hyprland automatically float & center it
//   and natively close it on the user's Hyprland window-close shortcut (e.g. SUPER+W / killactive).
// - Horizontal category pills, large underline goal input, Today / Todoist / This week task tabs,
//   inline New task creator, Rhythm selector (25+5, 50+10, Custom, Free).
// - SUPER+W, Ctrl+W, Ctrl+Q, Esc, or × cancels; Enter starts.
Item {
  id: root

  property var service: null
  property bool open: false
  property bool closingFromHost: false
  property string lang: service ? service.lang : "en"
  property var tokens: service ? service.tokens : ({})
  property string fontFamily: "Sans Serif"

  property int selectedCategoryId: 0
  property string rhythmMode: "50" // "25" | "50" | "custom" | "free"
  property int customWorkMin: 45
  property int customRestMin: 10
  property string taskTab: "today" // "today" | "planned" | "todoist" | "week"
  property string focusSection: "goal" // "goal" | "tasks" | "newTaskTitle" | "newTaskDetail" | "rhythm" | "categories"
  property int pickerIndex: 0
  property bool pickerActive: false
  property var pickedTodoIds: []
  property var pickedTodoistKeys: []
  property var pickedWeeklyKeys: []
  property var extraTasks: []
  property int inlineTaskPriority: 1
  property bool inlineCreateOnTodoist: false

  readonly property int selectedWorkMin: {
    if (rhythmMode === "25") return 25
    if (rhythmMode === "50") return 50
    if (rhythmMode === "custom") return customWorkMin
    return 0
  }

  readonly property int selectedRestMin: {
    if (rhythmMode === "25") return 5
    if (rhythmMode === "50") return 10
    if (rhythmMode === "custom") return customRestMin
    return 10
  }

  readonly property var categories: service ? service.categories : []
  readonly property var unattachedTodos: service && service.todayData ? (service.todayData.unattachedTodos || []) : []
  readonly property var plannedTodosRaw: (service && service.todayData && service.todayData.horizons && service.todayData.horizons.openPlanned)
    ? service.todayData.horizons.openPlanned
    : []
  readonly property bool hasPlanned: plannedTodosRaw.length > 0
  readonly property bool todoistConnected: !!(service && service.todoistData && service.todoistData.enabled && service.todoistData.hasToken)
  readonly property var todoistTasksRaw: service && service.todoistData ? (service.todoistData.tasks || []) : []
  readonly property bool hasTodoist: todoistTasksRaw.length > 0
  readonly property var weeklyTasksRaw: service && service.weeklyData ? (service.weeklyData.tasks || []) : []
  readonly property bool hasWeekly: weeklyTasksRaw.length > 0

  readonly property var sortedPlannedTodos: {
    var list = plannedTodosRaw.slice()
    var selCid = root.selectedCategoryId
    var indexed = []
    for (var i = 0; i < list.length; i++) {
      indexed.push({ item: list[i], idx: i })
    }
    indexed.sort(function(a, b) {
      var aMatch = (Number(a.item.categoryId) === selCid && selCid > 0) ? 0 : 1
      var bMatch = (Number(b.item.categoryId) === selCid && selCid > 0) ? 0 : 1
      if (aMatch !== bMatch) return aMatch - bMatch
      return a.idx - b.idx
    })
    var out = []
    for (var j = 0; j < indexed.length; j++) out.push(indexed[j].item)
    return out
  }

  readonly property var sortedTodoistTasks: {
    var list = todoistTasksRaw.slice()
    var selCid = root.selectedCategoryId
    var indexed = []
    for (var i = 0; i < list.length; i++) {
      indexed.push({ item: list[i], idx: i })
    }
    indexed.sort(function(a, b) {
      var aMatch = (Number(a.item.categoryId) === selCid && selCid > 0) ? 0 : 1
      var bMatch = (Number(b.item.categoryId) === selCid && selCid > 0) ? 0 : 1
      if (aMatch !== bMatch) return aMatch - bMatch
      return a.idx - b.idx
    })
    var out = []
    for (var j = 0; j < indexed.length; j++) out.push(indexed[j].item)
    return out
  }

  // Sort weekly tasks so the currently selected category's tasks appear first
  readonly property var sortedWeeklyTasks: {
    var list = weeklyTasksRaw.slice()
    var selCid = root.selectedCategoryId
    list.sort(function(a, b) {
      var aMatch = (Number(a.categoryId) === selCid && selCid > 0) ? 0 : 1
      var bMatch = (Number(b.categoryId) === selCid && selCid > 0) ? 0 : 1
      if (aMatch !== bMatch) return aMatch - bMatch
      return Number(a.line) - Number(b.line)
    })
    return list
  }

  readonly property var taskTabChoices: {
    if (!hasPlanned && !hasTodoist && !hasWeekly) return []
    var tabs = [{ key: "today", label: Theme.t(lang, "Bugün", "Today") }]
    if (hasPlanned) tabs.push({ key: "planned", label: Theme.t(lang, "Planlı / Kutu", "Planned / Inbox") })
    if (hasTodoist) tabs.push({ key: "todoist", label: "Todoist" })
    if (hasWeekly) tabs.push({ key: "week", label: Theme.t(lang, "Haftalık MD", "Weekly MD") })
    return tabs
  }

  readonly property int totalSelectedTasks: pickedTodoIds.length + pickedTodoistKeys.length + pickedWeeklyKeys.length + extraTasks.length
  readonly property var currentPickerList: {
    if (taskTab === "planned") return sortedPlannedTodos
    if (taskTab === "todoist") return sortedTodoistTasks
    if (taskTab === "week") return sortedWeeklyTasks
    return unattachedTodos
  }
  readonly property bool hasPickerItems: currentPickerList && currentPickerList.length > 0
  readonly property bool secondaryInputFocused: newTaskTitle.activeFocus || newTaskDetail.activeFocus || customWorkInput.activeFocus || customRestInput.activeFocus

  onCurrentPickerListChanged: {
    var cnt = currentPickerList ? currentPickerList.length : 0
    if (cnt === 0) pickerIndex = 0
    else if (pickerIndex >= cnt) pickerIndex = cnt - 1
  }

  property var openedScreen: null
  property int openedWorkspaceId: -1
  property string openedMonitorName: ""

  readonly property string windowTitle: "Houra — " + Theme.t(lang, "Yeni oturum", "New session")
  readonly property int availW: openedScreen && openedScreen.width > 0 ? openedScreen.width : 1280
  readonly property int availH: openedScreen && openedScreen.height > 0 ? openedScreen.height : 800
  readonly property int targetWidth: Math.max(420, Math.min(548, availW - 40))
  readonly property int targetHeight: Math.max(320, Math.min(availH - 56, Math.ceil(formCol.implicitHeight) + 46))

  function _resolveFocusedScreen() {
    var m = Hyprland.focusedMonitor
    var fname = m && m.name ? String(m.name) : ""
    for (var i = 0; i < Quickshell.screens.length; i++) {
      if (fname && String(Quickshell.screens[i].name) === fname) return Quickshell.screens[i]
    }
    return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null
  }

  function _currentWorkspaceId() {
    return (Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id !== undefined)
      ? Number(Hyprland.focusedWorkspace.id)
      : -1
  }

  function isOnCurrentWorkspace() {
    if (!open || !win.visible) return false
    var curWs = _currentWorkspaceId()
    if (curWs !== -1 && openedWorkspaceId !== -1 && curWs !== openedWorkspaceId) return false
    return true
  }

  function _clampWork(v) {
    var n = parseInt(v, 10)
    if (isNaN(n)) return customWorkMin
    return Math.max(1, Math.min(240, n))
  }

  function _clampRest(v) {
    var n = parseInt(v, 10)
    if (isNaN(n)) return customRestMin
    return Math.max(1, Math.min(90, n))
  }

  function _commitCustomInputs() {
    customWorkMin = _clampWork(customWorkInput.text)
    customRestMin = _clampRest(customRestInput.text)
    customWorkInput.text = String(customWorkMin)
    customRestInput.text = String(customRestMin)
  }

  function stepCustomWork(delta) {
    _commitCustomInputs()
    rhythmMode = "custom"
    var next = customWorkMin + delta
    if (delta < 0 && customWorkMin <= 5) next = customWorkMin - 1
    if (delta > 0 && customWorkMin < 5) next = 5
    customWorkMin = Math.max(1, Math.min(240, next))
    customWorkInput.text = String(customWorkMin)
  }

  function stepCustomRest(delta) {
    _commitCustomInputs()
    rhythmMode = "custom"
    customRestMin = Math.max(1, Math.min(90, customRestMin + delta))
    customRestInput.text = String(customRestMin)
  }

  function stepCategory(delta) {
    if (!categories || categories.length === 0) return
    var cur = 0
    for (var i = 0; i < categories.length; i++) {
      if (Number(categories[i].id) === selectedCategoryId) { cur = i; break }
    }
    var next = (cur + delta + categories.length) % categories.length
    selectedCategoryId = Number(categories[next].id)
  }

  function stepTaskTab(delta) {
    if (!taskTabChoices || taskTabChoices.length <= 1) return
    var cur = 0
    for (var i = 0; i < taskTabChoices.length; i++) {
      if (taskTabChoices[i].key === taskTab) { cur = i; break }
    }
    var next = (cur + delta + taskTabChoices.length) % taskTabChoices.length
    taskTab = taskTabChoices[next].key
    pickerIndex = 0
  }

  function stepRhythm(delta) {
    var modes = ["25", "50", "custom", "free"]
    var cur = modes.indexOf(rhythmMode)
    if (cur < 0) cur = 1
    var next = (cur + delta + modes.length) % modes.length
    rhythmMode = modes[next]
  }

  function togglePickerAtCursor() {
    if (!hasPickerItems) return
    var idx = Math.max(0, Math.min(currentPickerList.length - 1, pickerIndex))
    var item = currentPickerList[idx]
    if (!item) return
    if (taskTab === "todoist") toggleTodoistTask(item)
    else if (taskTab === "week") toggleWeeklyTask(item)
    else toggleTodoId(item.id)
  }

  function ensurePickerRowVisible(rowItem) {
    if (!rowItem) return
    var pt = rowItem.mapToItem(pickerFlick.contentItem, 0, 0)
    var top = pt.y - 4
    var bot = pt.y + rowItem.height + 4
    if (top < pickerFlick.contentY) {
      pickerFlick.contentY = Math.max(0, top)
    } else if (bot > pickerFlick.contentY + pickerFlick.height) {
      var maxY = Math.max(0, pickerFlick.contentHeight - pickerFlick.height)
      pickerFlick.contentY = Math.min(maxY, bot - pickerFlick.height)
    }
  }

  function ensureCategoryPillVisible(pillItem) {
    if (!pillItem) return
    var pt = pillItem.mapToItem(catFlick.contentItem, 0, 0)
    var left = pt.x - 8
    var right = pt.x + pillItem.width + 8
    if (left < catFlick.contentX) {
      catFlick.contentX = Math.max(0, left)
    } else if (right > catFlick.contentX + catFlick.width) {
      var maxX = Math.max(0, catFlick.contentWidth - catFlick.width)
      catFlick.contentX = Math.min(maxX, right - catFlick.width)
    }
  }

  function focusZoneStep(delta) {
    var stops = []
    if (categories && categories.length > 0) stops.push("categories")
    stops.push("goal")
    if (hasPickerItems) stops.push("tasks")
    stops.push("newTaskTitle")
    stops.push("newTaskDetail")
    stops.push("rhythm")
    if (rhythmMode === "custom") {
      stops.push("customWork")
      stops.push("customRest")
    }

    var curZone = focusSection
    if (goalField.activeFocus) curZone = "goal"
    else if (newTaskTitle.activeFocus) curZone = "newTaskTitle"
    else if (newTaskDetail.activeFocus) curZone = "newTaskDetail"
    else if (customWorkInput.activeFocus) curZone = "customWork"
    else if (customRestInput.activeFocus) curZone = "customRest"

    var curIdx = stops.indexOf(curZone)
    if (curIdx < 0) curIdx = 0
    var nextZone = stops[(curIdx + delta + stops.length) % stops.length]
    focusSection = (nextZone === "customWork" || nextZone === "customRest") ? "rhythm" : nextZone

    if (nextZone === "goal") {
      goalField.forceActiveFocus()
    } else if (nextZone === "newTaskTitle") {
      newTaskTitle.forceActiveFocus()
    } else if (nextZone === "newTaskDetail") {
      newTaskDetail.forceActiveFocus()
    } else if (nextZone === "customWork") {
      customWorkInput.forceActiveFocus()
      customWorkInput.selectAll()
    } else if (nextZone === "customRest") {
      customRestInput.forceActiveFocus()
      customRestInput.selectAll()
    } else {
      if (nextZone === "tasks") pickerActive = true
      modalKeySink.forceActiveFocus()
    }
  }

  function showModal(prefillCatId, prefillGoal, prefillWeeklyKey, prefillTodoistKey, prefillTodoId) {
    var nextScreen = _resolveFocusedScreen()
    var nextMonName = nextScreen && nextScreen.name ? String(nextScreen.name) : ""
    var nextWsId = _currentWorkspaceId()
    var isFocusedNow = !!(Hyprland.activeToplevel && Hyprland.activeToplevel.title === root.windowTitle)
    var needRemap = win.visible && (
      !isFocusedNow
      || (nextWsId !== -1 && openedWorkspaceId !== -1 && nextWsId !== openedWorkspaceId)
      || (nextMonName !== "" && openedMonitorName !== "" && nextMonName !== openedMonitorName)
    )
    if (nextScreen) openedScreen = nextScreen
    openedMonitorName = nextMonName
    openedWorkspaceId = nextWsId

    var cats = service ? service.categories : []
    var defCat = prefillCatId && prefillCatId > 0
      ? prefillCatId
      : (service && service.settings && service.settings.lastTopic > 0 ? Number(service.settings.lastTopic) : 0)
    var found = false
    for (var i = 0; i < cats.length; i++) {
      if (Number(cats[i].id) === defCat) { found = true; break }
    }
    if (!found && cats.length > 0) defCat = Number(cats[0].id)

    selectedCategoryId = defCat

    var st = service && service.settings ? service.settings : ({})
    customWorkMin = Math.max(1, Math.min(240, Number(st.customWork) || 45))
    customRestMin = Math.max(1, Math.min(90, Number(st.customRest) || 10))
    var savedMode = st.rhythmMode ? String(st.rhythmMode) : ""
    if (savedMode === "25" || savedMode === "50" || savedMode === "custom" || savedMode === "free") {
      rhythmMode = savedMode
    } else {
      var rw = st.rhythmWork !== undefined ? Number(st.rhythmWork) : 50
      if (rw === 25) rhythmMode = "25"
      else if (rw === 0) rhythmMode = "free"
      else if (rw === 50) rhythmMode = "50"
      else {
        customWorkMin = Math.max(1, Math.min(240, rw))
        rhythmMode = "custom"
      }
    }
    customWorkInput.text = String(customWorkMin)
    customRestInput.text = String(customRestMin)

    pickedTodoIds = []
    pickedTodoistKeys = []
    pickedWeeklyKeys = []
    extraTasks = []
    inlineTaskPriority = 1
    inlineCreateOnTodoist = false
    var preTodoId = Number(prefillTodoId) || 0
    var tdKey = String(prefillTodoistKey || "")
    var wkKey = String(prefillWeeklyKey || "")
    if (preTodoId > 0) {
      pickedTodoIds = [preTodoId]
      var inPlanned = false
      for (var p = 0; p < plannedTodosRaw.length; p++) {
        if (Number(plannedTodosRaw[p].id) === preTodoId) { inPlanned = true; break }
      }
      taskTab = inPlanned ? "planned" : "today"
    } else if (tdKey.length > 0) {
      pickedTodoistKeys = [tdKey]
      taskTab = "todoist"
    } else if (wkKey.length > 0) {
      pickedWeeklyKeys = [wkKey]
      taskTab = "week"
    } else {
      taskTab = unattachedTodos.length > 0
        ? "today"
        : (hasPlanned ? "planned" : (hasTodoist ? "todoist" : (hasWeekly ? "week" : "today")))
    }

    goalField.text = prefillGoal || ""
    newTaskTitle.text = ""
    newTaskDetail.text = ""
    focusSection = "goal"
    pickerIndex = 0
    pickerActive = (preTodoId > 0 || tdKey.length > 0 || wkKey.length > 0)
    open = true

    if (needRemap) {
      closingFromHost = true
      win.visible = false
      closingFromHost = false
      Qt.callLater(function() {
        if (!root.open) return
        root.closingFromHost = false
        win.visible = true
        Qt.callLater(function() {
          if (root.open) goalField.forceActiveFocus()
        })
      })
    } else {
      closingFromHost = false
      win.visible = true
      Qt.callLater(function() {
        if (root.open) goalField.forceActiveFocus()
      })
    }
  }

  function closeModal() {
    closingFromHost = true
    open = false
    win.visible = false
    closingFromHost = false
  }

  function toggleTodoId(tid) {
    var copy = pickedTodoIds.slice()
    var idx = copy.indexOf(tid)
    if (idx === -1) copy.push(tid)
    else copy.splice(idx, 1)
    pickedTodoIds = copy
  }

  function toggleWeeklyTask(wt) {
    var copy = pickedWeeklyKeys.slice()
    var idx = copy.indexOf(wt.key)
    if (idx === -1) copy.push(wt.key)
    else copy.splice(idx, 1)
    pickedWeeklyKeys = copy
  }

  function toggleTodoistTask(td) {
    var copy = pickedTodoistKeys.slice()
    var idx = copy.indexOf(td.key)
    if (idx === -1) copy.push(td.key)
    else copy.splice(idx, 1)
    pickedTodoistKeys = copy
  }

  function addInlineTask() {
    var title = newTaskTitle.text.trim()
    if (!title) return
    var detail = newTaskDetail.text.trim()
    var copy = extraTasks.slice()
    copy.push({
      title: title,
      detail: detail,
      priority: inlineTaskPriority,
      categoryId: selectedCategoryId,
      createOnTodoist: !!(todoistConnected && inlineCreateOnTodoist)
    })
    extraTasks = copy
    newTaskTitle.text = ""
    newTaskDetail.text = ""
    inlineTaskPriority = 1
    newTaskTitle.forceActiveFocus()
  }

  function removeInlineTask(idx) {
    var copy = extraTasks.slice()
    copy.splice(idx, 1)
    extraTasks = copy
  }

  function submitStart() {
    if (!service) return
    _commitCustomInputs()
    if (newTaskTitle.text.trim().length > 0) {
      addInlineTask()
    }
    var combinedExtra = []
    for (var t = 0; t < todoistTasksRaw.length; t++) {
      var tdItem = todoistTasksRaw[t]
      if (pickedTodoistKeys.indexOf(tdItem.key) !== -1) {
        combinedExtra.push({
          title: tdItem.title,
          detail: tdItem.detail || tdItem.dueLabel || tdItem.projectName || "",
          todoistId: tdItem.id,
          priority: Number(tdItem.priority) || 1,
          dueTime: tdItem.dueTime || "",
          categoryId: Number(tdItem.categoryId) || selectedCategoryId
        })
      }
    }
    for (var i = 0; i < weeklyTasksRaw.length; i++) {
      var wt = weeklyTasksRaw[i]
      if (pickedWeeklyKeys.indexOf(wt.key) !== -1) {
        var det = wt.subgroup ? wt.subgroup : (wt.group || "")
        combinedExtra.push({ title: wt.title, detail: det })
      }
    }
    for (var j = 0; j < extraTasks.length; j++) {
      combinedExtra.push(extraTasks[j])
    }
    var goal = goalField.text.trim()
    closeModal()
    service.startNewSession(
      selectedCategoryId,
      goal,
      selectedWorkMin,
      selectedRestMin,
      pickedTodoIds,
      combinedExtra,
      rhythmMode,
      customWorkMin,
      customRestMin
    )
  }

  FloatingWindow {
    id: win
    visible: false
    screen: root.openedScreen
    title: root.windowTitle
    implicitWidth: root.targetWidth
    implicitHeight: root.targetHeight
    minimumSize: Qt.size(root.targetWidth, root.targetHeight)
    maximumSize: Qt.size(root.targetWidth, root.targetHeight)
    color: root.tokens.win || "#101013"

    onClosed: {
      if (!root.closingFromHost) root.closeModal()
    }

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) root.closeModal()
    }

    Rectangle {
      id: modalCard
      anchors.fill: parent
      color: root.tokens.win || "#101013"
      clip: true

      FocusScope {
        id: modalKeyScope
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem

        Item {
          id: modalKeySink
        }

        Keys.onPressed: function(event) {
          var k = event.key
          var mods = event.modifiers

          if ((mods & Qt.ControlModifier) && (k === Qt.Key_W || k === Qt.Key_Q)) {
            event.accepted = true
            root.closeModal()
            return
          }

          if (k === Qt.Key_Escape) {
            event.accepted = true
            if (root.secondaryInputFocused) {
              root._commitCustomInputs()
              root.focusSection = "goal"
              goalField.forceActiveFocus()
              return
            }
            root.closeModal()
            return
          }

          if ((mods & Qt.ControlModifier) && !(mods & Qt.AltModifier) && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
            var backTab = (k === Qt.Key_Backtab || (mods & Qt.ShiftModifier))
            root.stepTaskTab(backTab ? -1 : 1)
            event.accepted = true
            return
          }

          if (!(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
            var rev = (k === Qt.Key_Backtab || (mods & Qt.ShiftModifier))
            root.focusZoneStep(rev ? -1 : 1)
            event.accepted = true
            return
          }

          // Goal input focused: allow Up/Down to browse task picker without hijacking typing
          if (goalField.activeFocus) {
            if (!(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
              if (k === Qt.Key_Down && root.hasPickerItems) {
                if (!root.pickerActive) root.pickerIndex = Math.max(0, Math.min(root.currentPickerList.length - 1, root.pickerIndex))
                else root.pickerIndex = Math.min(root.currentPickerList.length - 1, root.pickerIndex + 1)
                root.pickerActive = true
                event.accepted = true
                return
              }
              if (k === Qt.Key_Up && root.hasPickerItems) {
                if (!root.pickerActive) root.pickerIndex = Math.max(0, Math.min(root.currentPickerList.length - 1, root.pickerIndex))
                else root.pickerIndex = Math.max(0, root.pickerIndex - 1)
                root.pickerActive = true
                event.accepted = true
                return
              }
              if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                event.accepted = true
                root.submitStart()
                return
              }
            }
            return
          }

          // Secondary text inputs (inline task title/detail, custom work/rest minutes)
          if (root.secondaryInputFocused) {
            if (customWorkInput.activeFocus && (k === Qt.Key_Up || k === Qt.Key_Down)) {
              root.stepCustomWork(k === Qt.Key_Up ? 5 : -5)
              event.accepted = true
              return
            }
            if (customRestInput.activeFocus && (k === Qt.Key_Up || k === Qt.Key_Down)) {
              root.stepCustomRest(k === Qt.Key_Up ? 1 : -1)
              event.accepted = true
              return
            }
            if (k === Qt.Key_Return || k === Qt.Key_Enter) {
              event.accepted = true
              if (newTaskTitle.activeFocus || newTaskDetail.activeFocus) {
                if (newTaskTitle.text.trim().length > 0) root.addInlineTask()
                else root.submitStart()
              } else {
                root._commitCustomInputs()
                root.submitStart()
              }
            }
            return
          }

          if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return

          if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            event.accepted = true
            root.submitStart()
            return
          }

          if (root.focusSection === "tasks") {
            if (k === Qt.Key_Down) {
              if (root.hasPickerItems) {
                root.pickerActive = true
                root.pickerIndex = Math.min(root.currentPickerList.length - 1, root.pickerIndex + 1)
              }
              event.accepted = true
              return
            }
            if (k === Qt.Key_Up) {
              if (root.hasPickerItems) {
                root.pickerActive = true
                root.pickerIndex = Math.max(0, root.pickerIndex - 1)
              }
              event.accepted = true
              return
            }
            if (k === Qt.Key_Left) { root.stepTaskTab(-1); event.accepted = true; return }
            if (k === Qt.Key_Right) { root.stepTaskTab(1); event.accepted = true; return }
            if (k === Qt.Key_Space) {
              root.pickerActive = true
              root.togglePickerAtCursor()
              event.accepted = true
              return
            }
          } else if (root.focusSection === "rhythm") {
            if (k === Qt.Key_Left || k === Qt.Key_Up) { root.stepRhythm(-1); event.accepted = true; return }
            if (k === Qt.Key_Right || k === Qt.Key_Down) { root.stepRhythm(1); event.accepted = true; return }
          } else if (root.focusSection === "categories") {
            if (k === Qt.Key_Left || k === Qt.Key_Up) { root.stepCategory(-1); event.accepted = true; return }
            if (k === Qt.Key_Right || k === Qt.Key_Down) { root.stepCategory(1); event.accepted = true; return }
          }
        }

        Flickable {
          anchors.fill: parent
          anchors.margins: 22
          contentWidth: width
          contentHeight: formCol.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Column {
            id: formCol
            width: parent.width
            spacing: 16

            // Header
            Item {
              width: parent.width
              height: 24

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.t(root.lang, "YENİ OTURUM", "NEW SESSION")
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.Bold
                font.letterSpacing: 1.3
                color: root.tokens.muted || "#888888"
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Esc"
                  font.family: "Monospace"
                  font.pixelSize: 10
                  color: root.tokens.faint || "#555555"
                }

                Rectangle {
                  anchors.verticalCenter: parent.verticalCenter
                  width: 24
                  height: 24
                  radius: 7
                  color: modalCloseHov.containsMouse
                    ? (root.tokens.raised || "#282830")
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    color: modalCloseHov.containsMouse
                      ? (root.tokens.ink || "#ffffff")
                      : (root.tokens.muted || "#888888")
                  }

                  MouseArea {
                    id: modalCloseHov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeModal()
                  }
                }
              }
            }

            // Horizontal Category Pills
            Flickable {
              id: catFlick
              width: parent.width
              height: 36
              contentWidth: catRow.implicitWidth
              contentHeight: 36
              clip: true

              Row {
                id: catRow
                spacing: 8

                Repeater {
                  model: root.categories ? root.categories.length : 0
                  delegate: Rectangle {
                    id: catChoicePill
                    readonly property var cat: root.categories[index]
                    readonly property bool picked: Number(cat.id) === root.selectedCategoryId
                    readonly property bool kbRing: picked && root.focusSection === "categories" && !goalField.activeFocus && !root.secondaryInputFocused
                    onPickedChanged: if (picked) root.ensureCategoryPillVisible(catChoicePill)
                    width: catPillRow.implicitWidth + 20
                    height: 34
                    radius: 17
                    color: picked
                      ? Theme.withAlpha(cat.color || "#4c8df0", 0.22)
                      : (catArea.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card || "#17171c"))
                    border.width: kbRing ? 2 : (picked ? 1.5 : 1)
                    border.color: kbRing
                      ? (root.tokens.ink || "#ffffff")
                      : (picked ? (cat.color || "#4c8df0") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.09)))

                    Row {
                      id: catPillRow
                      anchors.centerIn: parent
                      spacing: 7

                      CategorySwatch {
                        anchors.verticalCenter: parent.verticalCenter
                        swatchSize: 18
                        swatchColor: cat.color || "#4c8df0"
                        emoji: cat.emoji || ""
                        iconName: cat.icon || ""
                        iconColor: cat.iconColor || ""
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: cat.name || ""
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        font.weight: catChoicePill.picked ? Font.DemiBold : Font.Normal
                        color: root.tokens.ink || "#ffffff"
                      }
                    }

                    MouseArea {
                      id: catArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.selectedCategoryId = Number(cat.id)
                    }
                  }
                }
              }
            }

            // Large underline Goal input
            Column {
              width: parent.width
              spacing: 6

              Item {
                width: parent.width
                height: 34

                Text {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  visible: goalField.text.length === 0
                  text: Theme.t(root.lang, "Neye odaklanıyorsun?", "What are you focusing on?")
                  font.family: root.fontFamily
                  font.pixelSize: 18
                  font.weight: Font.Light
                  color: root.tokens.muted || "#777777"
                }

                TextInput {
                  id: goalField
                  anchors.fill: parent
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: root.fontFamily
                  font.pixelSize: 18
                  font.weight: Font.Normal
                  color: root.tokens.ink || "#ffffff"
                  selectByMouse: true
                  onActiveFocusChanged: if (activeFocus) root.focusSection = "goal"
                }
              }

              Rectangle {
                width: parent.width
                height: goalField.activeFocus ? 1.5 : 1
                color: goalField.activeFocus
                  ? (root.tokens.ink || "#ffffff")
                  : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.14))
              }
            }

            // Tasks section (Today / Planned & Inbox / Todoist / Weekly MD + inline creator)
            Column {
              width: parent.width
              spacing: 8

              Item {
                width: parent.width
                height: 26

                Rectangle {
                  id: selBadge
                  visible: root.totalSelectedTasks > 0
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: selCntTxt.implicitWidth + 14
                  height: 20
                  radius: 10
                  color: root.tokens.raised || "#2a2a32"

                  Text {
                    id: selCntTxt
                    anchors.centerIn: parent
                    text: root.totalSelectedTasks + " " + Theme.t(root.lang, "seçili", "selected")
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    color: root.tokens.ink || "#ffffff"
                  }
                }

                Flickable {
                  anchors.left: parent.left
                  anchors.right: selBadge.visible ? selBadge.left : parent.right
                  anchors.rightMargin: selBadge.visible ? 8 : 0
                  height: 26
                  contentWidth: tabsRow.implicitWidth
                  contentHeight: 26
                  clip: true

                  Row {
                    id: tabsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Text {
                      visible: root.taskTabChoices.length === 0
                      anchors.verticalCenter: parent.verticalCenter
                      text: Theme.t(root.lang, "GÖREVLER", "TASKS")
                      font.family: root.fontFamily
                      font.pixelSize: 10
                      font.weight: Font.DemiBold
                      font.letterSpacing: 1.0
                      color: root.tokens.muted || "#888888"
                    }

                    Repeater {
                      model: root.taskTabChoices
                      delegate: Rectangle {
                        readonly property bool active: root.taskTab === modelData.key
                        width: segLbl.implicitWidth + 16
                        height: 24
                        radius: 6
                        color: active ? (root.tokens.raised || "#2b2b33") : (root.tokens.card || "#17171c")
                        border.width: 1
                        border.color: active ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.2)) : "transparent"

                        Text {
                          id: segLbl
                          anchors.centerIn: parent
                          text: modelData.label
                          font.family: root.fontFamily
                          font.pixelSize: 11
                          font.weight: parent.active ? Font.DemiBold : Font.Normal
                          color: parent.active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#aaaaaa")
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.taskTab = modelData.key
                        }
                      }
                    }
                  }
                }
              }

              // Scrollable existing tasks picker
              Rectangle {
                visible: (root.taskTab === "today" && root.unattachedTodos.length > 0)
                  || (root.taskTab === "planned" && root.sortedPlannedTodos.length > 0)
                  || (root.taskTab === "todoist" && root.sortedTodoistTasks.length > 0)
                  || (root.taskTab === "week" && root.sortedWeeklyTasks.length > 0)
                width: parent.width
                height: Math.min(138, pickerListCol.implicitHeight + 12)
                radius: 10
                color: root.tokens.card || "#17171c"
                border.width: (root.focusSection === "tasks" && !goalField.activeFocus && !root.secondaryInputFocused) ? 1.5 : 1
                border.color: (root.focusSection === "tasks" && !goalField.activeFocus && !root.secondaryInputFocused)
                  ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.28))
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                Flickable {
                  id: pickerFlick
                  anchors.fill: parent
                  anchors.margins: 6
                  contentWidth: width
                  contentHeight: pickerListCol.implicitHeight
                  clip: true

                  Column {
                    id: pickerListCol
                    width: parent.width
                    spacing: 3

                    // Today's unattached todos
                    Repeater {
                      model: root.taskTab === "today" ? root.unattachedTodos.length : 0
                      delegate: Rectangle {
                        id: tdChoiceRow
                        readonly property var td: root.unattachedTodos[index]
                        readonly property bool chosen: root.pickedTodoIds.indexOf(td.id) !== -1
                        readonly property bool kbCur: root.pickerActive && root.taskTab === "today" && root.pickerIndex === index
                        readonly property int prio: Number(td.priority) || 1
                        readonly property string rightMeta: td.dueTime
                          ? String(td.dueTime)
                          : (td.isPastDue && td.dueLabel ? String(td.dueLabel) : "")
                        onKbCurChanged: if (kbCur) root.ensurePickerRowVisible(tdChoiceRow)
                        width: pickerListCol.width
                        height: 28
                        radius: 6
                        color: (chosen || kbCur) ? (root.tokens.raised || "#2b2b33") : (tdHov.containsMouse ? (root.tokens.card2 || "#202026") : "transparent")
                        border.width: kbCur ? 1 : 0
                        border.color: root.tokens.ink || "#ffffff"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: 8
                          anchors.rightMargin: 8
                          spacing: 7

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tdChoiceRow.chosen ? "✓" : "○"
                            font.pixelSize: 12
                            font.bold: tdChoiceRow.chosen
                            color: tdChoiceRow.chosen
                              ? (root.tokens.ink || "#ffffff")
                              : Theme.priorityColor(tdChoiceRow.prio, root.tokens.muted || "#777777")
                          }

                          Text {
                            visible: tdChoiceRow.prio > 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.priorityLabel(tdChoiceRow.prio)
                            font.family: "Monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.priorityColor(tdChoiceRow.prio, "#888888")
                          }

                          Text {
                            width: Math.max(80, parent.width - (tdChoiceRow.prio > 1 ? 48 : 24) - (tdChoiceRow.rightMeta !== "" ? 76 : 0))
                            anchors.verticalCenter: parent.verticalCenter
                            text: td.detail ? (td.title + " — " + td.detail) : td.title
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.tokens.ink || "#ffffff"
                          }

                          Text {
                            visible: tdChoiceRow.rightMeta !== ""
                            width: 68
                            horizontalAlignment: Text.AlignRight
                            anchors.verticalCenter: parent.verticalCenter
                            text: tdChoiceRow.rightMeta
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            color: (td.isOverdue || td.isPastDue)
                              ? (root.tokens.danger || "#e06458")
                              : (root.tokens.muted || "#777777")
                          }
                        }

                        MouseArea {
                          id: tdHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleTodoId(td.id)
                        }
                      }
                    }

                    // Planned (Week / Month / Range / Upcoming / Inbox) local tasks
                    Repeater {
                      model: root.taskTab === "planned" ? root.sortedPlannedTodos.length : 0
                      delegate: Rectangle {
                        id: plChoiceRow
                        readonly property var pl: root.sortedPlannedTodos[index]
                        readonly property bool chosen: root.pickedTodoIds.indexOf(pl.id) !== -1
                        readonly property bool kbCur: root.pickerActive && root.taskTab === "planned" && root.pickerIndex === index
                        readonly property int prio: Number(pl.priority) || 1
                        readonly property string metaLbl: pl.dueLabel
                          ? String(pl.dueLabel)
                          : Theme.scopeShortLabel(pl.scope || "inbox", root.lang)
                        onKbCurChanged: if (kbCur) root.ensurePickerRowVisible(plChoiceRow)
                        width: pickerListCol.width
                        height: 28
                        radius: 6
                        color: (chosen || kbCur) ? (root.tokens.raised || "#2b2b33") : (plHov.containsMouse ? (root.tokens.card2 || "#202026") : "transparent")
                        border.width: kbCur ? 1 : 0
                        border.color: root.tokens.ink || "#ffffff"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: 8
                          anchors.rightMargin: 8
                          spacing: 7

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: plChoiceRow.chosen ? "✓" : "○"
                            font.pixelSize: 12
                            font.bold: plChoiceRow.chosen
                            color: plChoiceRow.chosen
                              ? (root.tokens.ink || "#ffffff")
                              : Theme.priorityColor(plChoiceRow.prio, root.tokens.muted || "#777777")
                          }

                          Text {
                            visible: plChoiceRow.prio > 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.priorityLabel(plChoiceRow.prio)
                            font.family: "Monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.priorityColor(plChoiceRow.prio, "#888888")
                          }

                          Rectangle {
                            visible: (pl.categoryColor || "") !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: pl.categoryColor || "#4c8df0"
                          }

                          Text {
                            width: Math.max(80, parent.width - 134 - (plChoiceRow.prio > 1 ? 22 : 0))
                            anchors.verticalCenter: parent.verticalCenter
                            text: pl.detail ? (pl.title + " — " + pl.detail) : (pl.title || "")
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.tokens.ink || "#ffffff"
                          }

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: plChoiceRow.metaLbl
                            elide: Text.ElideRight
                            width: 96
                            horizontalAlignment: Text.AlignRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            color: root.tokens.muted || "#777777"
                          }
                        }

                        MouseArea {
                          id: plHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleTodoId(pl.id)
                        }
                      }
                    }

                    // Todoist tasks
                    Repeater {
                      model: root.taskTab === "todoist" ? root.sortedTodoistTasks.length : 0
                      delegate: Rectangle {
                        id: tdistChoiceRow
                        readonly property var tdist: root.sortedTodoistTasks[index]
                        readonly property bool chosen: root.pickedTodoistKeys.indexOf(tdist.key) !== -1
                        readonly property bool kbCur: root.pickerActive && root.taskTab === "todoist" && root.pickerIndex === index
                        onKbCurChanged: if (kbCur) root.ensurePickerRowVisible(tdistChoiceRow)
                        readonly property int prio: Number(tdist.priority) || 1
                        width: pickerListCol.width
                        height: 28
                        radius: 6
                        color: (chosen || kbCur) ? (root.tokens.raised || "#2b2b33") : (tdistHov.containsMouse ? (root.tokens.card2 || "#202026") : "transparent")
                        border.width: kbCur ? 1 : 0
                        border.color: root.tokens.ink || "#ffffff"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: 8
                          anchors.rightMargin: 8
                          spacing: 7

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tdistChoiceRow.chosen ? "✓" : "○"
                            font.pixelSize: 12
                            font.bold: tdistChoiceRow.chosen
                            color: tdistChoiceRow.chosen ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#777777")
                          }

                          Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: tdistChoiceRow.prio === 4
                              ? "#e44332"
                              : (tdistChoiceRow.prio === 3
                                ? "#eb8909"
                                : ((tdist.categoryColor || "") !== "" ? tdist.categoryColor : "#4c8df0"))
                          }

                          Text {
                            visible: tdistChoiceRow.prio > 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: Theme.priorityLabel(tdistChoiceRow.prio)
                            font.family: "Monospace"
                            font.pixelSize: 10
                            font.weight: Font.Bold
                            color: Theme.priorityColor(tdistChoiceRow.prio, "#888888")
                          }

                          Text {
                            width: Math.max(80, parent.width - 134 - (tdistChoiceRow.prio > 1 ? 22 : 0))
                            anchors.verticalCenter: parent.verticalCenter
                            text: tdist.title || ""
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.tokens.ink || "#ffffff"
                          }

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: tdist.dueLabel
                              ? ("#" + (tdist.projectName || "Inbox") + " · " + tdist.dueLabel)
                              : ("#" + (tdist.projectName || "Inbox"))
                            elide: Text.ElideRight
                            width: 98
                            horizontalAlignment: Text.AlignRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            color: tdist.isOverdue
                              ? (root.tokens.danger || "#e06458")
                              : (root.tokens.muted || "#777777")
                          }
                        }

                        MouseArea {
                          id: tdistHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleTodoistTask(tdist)
                        }
                      }
                    }

                    // Weekly Markdown tasks
                    Repeater {
                      model: root.taskTab === "week" ? root.sortedWeeklyTasks.length : 0
                      delegate: Rectangle {
                        id: wtChoiceRow
                        readonly property var wt: root.sortedWeeklyTasks[index]
                        readonly property bool chosen: root.pickedWeeklyKeys.indexOf(wt.key) !== -1
                        readonly property bool kbCur: root.pickerActive && root.taskTab === "week" && root.pickerIndex === index
                        onKbCurChanged: if (kbCur) root.ensurePickerRowVisible(wtChoiceRow)
                        readonly property int indentPx: Math.min(2, Number(wt.depth) || 0) * 14
                        width: pickerListCol.width
                        height: 28
                        radius: 6
                        color: (chosen || kbCur) ? (root.tokens.raised || "#2b2b33") : (wtHov.containsMouse ? (root.tokens.card2 || "#202026") : "transparent")
                        border.width: kbCur ? 1 : 0
                        border.color: root.tokens.ink || "#ffffff"

                        Row {
                          anchors.fill: parent
                          anchors.leftMargin: 8 + wtChoiceRow.indentPx
                          anchors.rightMargin: 8
                          spacing: 7

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wtChoiceRow.chosen ? "✓" : (wt.waiting ? "◌" : "○")
                            font.pixelSize: 12
                            color: wtChoiceRow.chosen ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#777777")
                          }

                          Rectangle {
                            visible: (wt.categoryColor || "") !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7
                            height: 7
                            radius: 3.5
                            color: wt.categoryColor || "#4c8df0"
                          }

                          Text {
                            width: Math.max(80, parent.width - 96)
                            anchors.verticalCenter: parent.verticalCenter
                            text: (wt.subgroup && (Number(wt.depth) || 0) === 0) ? (wt.subgroup + " › " + wt.title) : wt.title
                            elide: Text.ElideRight
                            font.family: root.fontFamily
                            font.pixelSize: 12
                            color: root.tokens.ink || "#ffffff"
                          }

                          Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: wt.waiting ? Theme.t(root.lang, "bekliyor", "waiting") : (wt.group || "")
                            elide: Text.ElideRight
                            width: 62
                            horizontalAlignment: Text.AlignRight
                            font.family: root.fontFamily
                            font.pixelSize: 10
                            color: root.tokens.muted || "#777777"
                          }
                        }

                        MouseArea {
                          id: wtHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleWeeklyTask(wt)
                        }
                      }
                    }
                  }
                }
              }

              // Newly added inline tasks chips
              Flow {
                visible: root.extraTasks.length > 0
                width: parent.width
                spacing: 6

                Repeater {
                  model: root.extraTasks.length
                  delegate: Rectangle {
                    readonly property var et: root.extraTasks[index]
                    readonly property int etPrio: Number(et.priority) || 1
                    width: Math.min(formCol.width, etChipRow.implicitWidth + 18)
                    height: 24
                    radius: 6
                    color: root.tokens.card2 || "#1f1f25"
                    border.width: 1
                    border.color: etPrio > 1
                      ? Theme.withAlpha(Theme.priorityColor(etPrio, "#888888"), 0.50)
                      : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.14))

                    Row {
                      id: etChipRow
                      anchors.centerIn: parent
                      spacing: 5

                      Text {
                        visible: etPrio > 1
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.priorityLabel(etPrio)
                        font.family: "Monospace"
                        font.pixelSize: 10
                        font.weight: Font.Bold
                        color: Theme.priorityColor(etPrio, "#888888")
                      }

                      Text {
                        id: etTxt
                        anchors.verticalCenter: parent.verticalCenter
                        text: "✓ " + et.title + (et.createOnTodoist ? " · Todoist" : "")
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        color: root.tokens.ink || "#ffffff"
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "×"
                        font.pixelSize: 13
                        color: root.tokens.muted || "#888888"
                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.removeInlineTask(index)
                        }
                      }
                    }
                  }
                }
              }

              // Inline "New task" inputs
              Row {
                width: parent.width
                spacing: 6

                Rectangle {
                  width: (parent.width - 42) * 0.54
                  height: 32
                  radius: 8
                  color: root.tokens.card || "#17171c"
                  border.width: 1
                  border.color: newTaskTitle.activeFocus
                    ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
                    : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: newTaskTitle.text.length === 0
                    text: Theme.t(root.lang, "Yeni görev başlığı… (p1..p4 · @SS:DD)", "New task title… (p1..p4 · @HH:MM)")
                    elide: Text.ElideRight
                    width: parent.width - 20
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.tokens.muted || "#777777"
                  }

                  TextInput {
                    id: newTaskTitle
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.tokens.ink || "#ffffff"
                    selectByMouse: true
                    onActiveFocusChanged: if (activeFocus) root.focusSection = "newTaskTitle"
                  }
                }

                Rectangle {
                  width: (parent.width - 42) * 0.46
                  height: 32
                  radius: 8
                  color: root.tokens.card || "#17171c"
                  border.width: 1
                  border.color: newTaskDetail.activeFocus
                    ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
                    : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    visible: newTaskDetail.text.length === 0
                    text: Theme.t(root.lang, "Detay (isteğe bağlı)", "Details (optional)")
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    color: root.tokens.muted || "#777777"
                  }

                  TextInput {
                    id: newTaskDetail
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    verticalAlignment: TextInput.AlignVCenter
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    color: root.tokens.ink || "#ffffff"
                    selectByMouse: true
                    onActiveFocusChanged: if (activeFocus) root.focusSection = "newTaskDetail"
                  }
                }

                Rectangle {
                  width: 30
                  height: 32
                  radius: 8
                  color: addTaskArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
                  border.width: 1
                  border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

                  Text {
                    anchors.centerIn: parent
                    text: "+"
                    font.pixelSize: 15
                    color: root.tokens.ink || "#ffffff"
                  }

                  MouseArea {
                    id: addTaskArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.addInlineTask()
                  }
                }
              }

              // Inline task Priority (P1..P4) + optional "+ Todoist" sync pill
              Row {
                width: parent.width
                spacing: 5

                Repeater {
                  model: [4, 3, 2, 1]
                  delegate: Rectangle {
                    readonly property int pVal: Number(modelData)
                    readonly property bool pSel: root.inlineTaskPriority === pVal
                    readonly property string pCol: Theme.priorityColor(pVal, root.tokens.muted || "#777777")
                    width: 28
                    height: 20
                    radius: 5
                    color: pSel
                      ? Theme.withAlpha(pCol, pVal > 1 ? 0.22 : 0.14)
                      : (inlPrioArea.containsMouse ? (root.tokens.raised || "#282830") : "transparent")
                    border.width: 1
                    border.color: pSel
                      ? (pVal > 1 ? pCol : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24)))
                      : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                    Text {
                      anchors.centerIn: parent
                      text: Theme.priorityLabel(parent.pVal)
                      font.family: "Monospace"
                      font.pixelSize: 10
                      font.weight: parent.pSel ? Font.Bold : Font.Normal
                      color: parent.pVal > 1
                        ? parent.pCol
                        : (parent.pSel ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#777777"))
                    }

                    MouseArea {
                      id: inlPrioArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.inlineTaskPriority = parent.pVal
                    }
                  }
                }

                Rectangle {
                  visible: root.todoistConnected
                  width: inlTdTxt.implicitWidth + 14
                  height: 20
                  radius: 5
                  color: root.inlineCreateOnTodoist
                    ? Theme.withAlpha("#e44332", 0.20)
                    : (inlTdArea.containsMouse ? (root.tokens.raised || "#282830") : "transparent")
                  border.width: 1
                  border.color: root.inlineCreateOnTodoist
                    ? "#e44332"
                    : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                  Text {
                    id: inlTdTxt
                    anchors.centerIn: parent
                    text: root.inlineCreateOnTodoist
                      ? Theme.t(root.lang, "✓ Todoist'e de ekle", "✓ Also add to Todoist")
                      : Theme.t(root.lang, "+ Todoist'e de ekle", "+ Also add to Todoist")
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: root.inlineCreateOnTodoist ? Font.DemiBold : Font.Normal
                    color: root.inlineCreateOnTodoist ? "#e44332" : (root.tokens.muted || "#888888")
                  }

                  MouseArea {
                    id: inlTdArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.inlineCreateOnTodoist = !root.inlineCreateOnTodoist
                  }
                }
              }
            }

            // Rhythm cards: Row 1 (25+5, 50+10), Row 2 (Custom focus + break), Row 3 (Free, untruncated)
            Column {
              width: parent.width
              spacing: 8

              Text {
                text: Theme.t(root.lang, "RİTİM", "RHYTHM")
                font.family: root.fontFamily
                font.pixelSize: 10
                font.weight: Font.DemiBold
                font.letterSpacing: 1.0
                color: root.tokens.muted || "#888888"
              }

              // Row 1: Preset 25 + 5 and 50 + 10
              Row {
                width: parent.width
                spacing: 8

                Repeater {
                  model: [
                    {
                      mode: "25",
                      num: "25",
                      unit: Theme.t(root.lang, "dk odak", "min focus"),
                      sub: Theme.t(root.lang, "+ 5 dk mola", "+ 5 min break")
                    },
                    {
                      mode: "50",
                      num: "50",
                      unit: Theme.t(root.lang, "dk odak", "min focus"),
                      sub: Theme.t(root.lang, "+ 10 dk mola", "+ 10 min break")
                    }
                  ]
                  delegate: Rectangle {
                    readonly property bool picked: root.rhythmMode === modelData.mode
                    readonly property bool rhythmFocused: picked && root.focusSection === "rhythm" && !goalField.activeFocus && !root.secondaryInputFocused
                    width: (formCol.width - 8) / 2
                    height: 66
                    radius: 10
                    color: picked
                      ? (root.tokens.raised || "#282830")
                      : (presetArea.containsMouse ? (root.tokens.card2 || "#1f1f25") : (root.tokens.card || "#16161b"))
                    border.width: rhythmFocused ? 2 : (picked ? 1.5 : 1)
                    border.color: picked
                      ? (root.tokens.ink || "#ffffff")
                      : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                    Column {
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.verticalCenter: parent.verticalCenter
                      anchors.leftMargin: 14
                      anchors.rightMargin: 14
                      spacing: 2

                      Row {
                        spacing: 6
                        Text {
                          text: modelData.num
                          font.family: root.fontFamily
                          font.pixelSize: 24
                          font.weight: Font.Light
                          color: root.tokens.ink || "#ffffff"
                        }
                        Text {
                          anchors.bottom: parent.bottom
                          anchors.bottomMargin: 3
                          text: modelData.unit
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          color: root.tokens.secondary || "#bbbbbb"
                        }
                      }

                      Text {
                        text: modelData.sub
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        color: root.tokens.muted || "#888888"
                      }
                    }

                    MouseArea {
                      id: presetArea
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.rhythmMode = modelData.mode
                    }
                  }
                }
              }

              // Row 2: Custom Rhythm (editable Focus + Break durations)
              Rectangle {
                id: customRhythmCard
                readonly property bool picked: root.rhythmMode === "custom"
                readonly property bool rhythmFocused: picked && root.focusSection === "rhythm" && !goalField.activeFocus && !root.secondaryInputFocused
                width: parent.width
                height: 62
                radius: 10
                color: picked
                  ? (root.tokens.raised || "#282830")
                  : (customCardArea.containsMouse ? (root.tokens.card2 || "#1f1f25") : (root.tokens.card || "#16161b"))
                border.width: rhythmFocused ? 2 : (picked ? 1.5 : 1)
                border.color: picked
                  ? (root.tokens.ink || "#ffffff")
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                MouseArea {
                  id: customCardArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.rhythmMode = "custom"
                }

                Item {
                  anchors.fill: parent
                  anchors.leftMargin: 14
                  anchors.rightMargin: 12

                  Column {
                    anchors.left: parent.left
                    anchors.right: customControlsRow.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                      text: Theme.t(root.lang, "Özel süre", "Custom duration")
                      font.family: root.fontFamily
                      font.pixelSize: 14
                      font.weight: Font.DemiBold
                      color: root.tokens.ink || "#ffffff"
                    }

                    Text {
                      width: parent.width
                      elide: Text.ElideRight
                      text: root.customWorkMin + " " + Theme.t(root.lang, "dk odak", "min focus") +
                            "  ·  + " + root.customRestMin + " " + Theme.t(root.lang, "dk mola", "min break")
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      color: root.tokens.secondary || "#aaaaaa"
                    }
                  }

                  Row {
                    id: customControlsRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    // Custom Focus stepper + input
                    Row {
                      spacing: 4
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t(root.lang, "Odak", "Focus")
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        color: root.tokens.muted || "#888888"
                      }

                      Rectangle {
                        width: 24
                        height: 28
                        radius: 6
                        color: wMinusHov.containsMouse ? (root.tokens.raised || "#32323c") : (root.tokens.card2 || "#1f1f26")
                        border.width: 1
                        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)
                        Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 13; color: root.tokens.ink || "#ffffff" }
                        MouseArea {
                          id: wMinusHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.stepCustomWork(-5)
                        }
                      }

                      Rectangle {
                        width: 44
                        height: 28
                        radius: 6
                        color: root.tokens.win || "#101013"
                        border.width: 1
                        border.color: customWorkInput.activeFocus
                          ? (root.tokens.ink || "#ffffff")
                          : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16))

                        TextInput {
                          id: customWorkInput
                          anchors.fill: parent
                          horizontalAlignment: TextInput.AlignHCenter
                          verticalAlignment: TextInput.AlignVCenter
                          font.family: "Monospace"
                          font.pixelSize: 12
                          font.weight: Font.DemiBold
                          color: root.tokens.ink || "#ffffff"
                          selectByMouse: true
                          validator: IntValidator { bottom: 1; top: 240 }
                          onActiveFocusChanged: {
                            if (activeFocus) root.rhythmMode = "custom"
                            else root._commitCustomInputs()
                          }
                          onTextEdited: {
                            root.rhythmMode = "custom"
                            var n = parseInt(text, 10)
                            if (!isNaN(n) && n >= 1 && n <= 240) root.customWorkMin = n
                          }
                        }
                      }

                      Rectangle {
                        width: 24
                        height: 28
                        radius: 6
                        color: wPlusHov.containsMouse ? (root.tokens.raised || "#32323c") : (root.tokens.card2 || "#1f1f26")
                        border.width: 1
                        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)
                        Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 13; color: root.tokens.ink || "#ffffff" }
                        MouseArea {
                          id: wPlusHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.stepCustomWork(5)
                        }
                      }
                    }

                    // Custom Break stepper + input
                    Row {
                      spacing: 4
                      anchors.verticalCenter: parent.verticalCenter

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Theme.t(root.lang, "Mola", "Break")
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        color: root.tokens.muted || "#888888"
                      }

                      Rectangle {
                        width: 24
                        height: 28
                        radius: 6
                        color: rMinusHov.containsMouse ? (root.tokens.raised || "#32323c") : (root.tokens.card2 || "#1f1f26")
                        border.width: 1
                        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)
                        Text { anchors.centerIn: parent; text: "−"; font.pixelSize: 13; color: root.tokens.ink || "#ffffff" }
                        MouseArea {
                          id: rMinusHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.stepCustomRest(-1)
                        }
                      }

                      Rectangle {
                        width: 40
                        height: 28
                        radius: 6
                        color: root.tokens.win || "#101013"
                        border.width: 1
                        border.color: customRestInput.activeFocus
                          ? (root.tokens.ink || "#ffffff")
                          : (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16))

                        TextInput {
                          id: customRestInput
                          anchors.fill: parent
                          horizontalAlignment: TextInput.AlignHCenter
                          verticalAlignment: TextInput.AlignVCenter
                          font.family: "Monospace"
                          font.pixelSize: 12
                          font.weight: Font.DemiBold
                          color: root.tokens.ink || "#ffffff"
                          selectByMouse: true
                          validator: IntValidator { bottom: 1; top: 90 }
                          onActiveFocusChanged: {
                            if (activeFocus) root.rhythmMode = "custom"
                            else root._commitCustomInputs()
                          }
                          onTextEdited: {
                            root.rhythmMode = "custom"
                            var n = parseInt(text, 10)
                            if (!isNaN(n) && n >= 1 && n <= 90) root.customRestMin = n
                          }
                        }
                      }

                      Rectangle {
                        width: 24
                        height: 28
                        radius: 6
                        color: rPlusHov.containsMouse ? (root.tokens.raised || "#32323c") : (root.tokens.card2 || "#1f1f26")
                        border.width: 1
                        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)
                        Text { anchors.centerIn: parent; text: "+"; font.pixelSize: 13; color: root.tokens.ink || "#ffffff" }
                        MouseArea {
                          id: rPlusHov
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.stepCustomRest(1)
                        }
                      }
                    }
                  }
                }
              }

              // Row 3: Free Mode (full width, ∞ glyph + full untruncated description)
              Rectangle {
                readonly property bool picked: root.rhythmMode === "free"
                readonly property bool rhythmFocused: picked && root.focusSection === "rhythm" && !goalField.activeFocus && !root.secondaryInputFocused
                width: parent.width
                height: Math.max(54, freeTextCol.implicitHeight + 20)
                radius: 10
                color: picked
                  ? (root.tokens.raised || "#282830")
                  : (freeArea.containsMouse ? (root.tokens.card2 || "#1f1f25") : (root.tokens.card || "#16161b"))
                border.width: rhythmFocused ? 2 : (picked ? 1.5 : 1)
                border.color: picked
                  ? (root.tokens.ink || "#ffffff")
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                Row {
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: 14
                  anchors.rightMargin: 14
                  spacing: 12

                  Text {
                    width: 26
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignHCenter
                    text: "∞"
                    font.family: root.fontFamily
                    font.pixelSize: 24
                    font.weight: Font.Light
                    color: root.tokens.ink || "#ffffff"
                  }

                  Column {
                    id: freeTextCol
                    width: parent.width - 38
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                      text: Theme.t(root.lang, "Serbest", "Free")
                      font.family: root.fontFamily
                      font.pixelSize: 14
                      font.weight: Font.DemiBold
                      color: root.tokens.ink || "#ffffff"
                    }

                    Text {
                      width: parent.width
                      wrapMode: Text.WordWrap
                      text: Theme.t(
                        root.lang,
                        "İleri sayar, 50. dakikada mola önerir",
                        "Counts up, suggests a break at 50 min"
                      )
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      color: root.tokens.secondary || "#aaaaaa"
                    }
                  }
                }

                MouseArea {
                  id: freeArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.rhythmMode = "free"
                }
              }
            }

            // Footer: Cancel + Start
            Item {
              width: parent.width
              height: 38

              Text {
                anchors.left: parent.left
                anchors.right: footerBtnsRow.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: Theme.t(
                  root.lang,
                  "↵ başlatır · Tab ve ok tuşları dolaşır",
                  "↵ starts · Tab & arrows navigate"
                )
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.faint || "#555555"
              }

              Row {
                id: footerBtnsRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Rectangle {
                  width: 82
                  height: 36
                  radius: 9
                  color: cancelArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card || "#17171c")
                  border.width: 1
                  border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

                  Text {
                    anchors.centerIn: parent
                    text: Theme.t(root.lang, "İptal", "Cancel")
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    color: root.tokens.secondary || "#bbbbbb"
                  }

                  MouseArea {
                    id: cancelArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeModal()
                  }
                }

                Rectangle {
                  width: startBtnLbl.implicitWidth + 32
                  height: 36
                  radius: 9
                  color: startBtnArea.containsMouse
                    ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.88)
                    : (root.tokens.primaryBg || "#ffffff")

                  Text {
                    id: startBtnLbl
                    anchors.centerIn: parent
                    text: {
                      if (root.rhythmMode === "free") {
                        return Theme.t(root.lang, "Başlat · serbest", "Start · free")
                      }
                      if (root.rhythmMode === "custom") {
                        return Theme.t(root.lang, "Başlat · ", "Start · ") + root.customWorkMin + " + " + root.customRestMin + " " + Theme.t(root.lang, "dk", "min")
                      }
                      return Theme.t(root.lang, "Başlat · ", "Start · ") + root.selectedWorkMin + " " + Theme.t(root.lang, "dk", "min")
                    }
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.tokens.primaryInk || "#0a0a0c"
                  }

                  MouseArea {
                    id: startBtnArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.submitStart()
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
