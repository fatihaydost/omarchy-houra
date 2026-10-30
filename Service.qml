import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import "Bridge.js" as Bridge
import "Theme.js" as Theme
import "windows"

// Singleton background service for Houra inside omarchy-shell.
// Owns the session timer state machine, SQLite/settings RPC queue, audio chime,
// optional Omarchy DND sync, IPC handler (`omarchy-shell houra ...`), and all
// Wayland layer-shell / floating windows.
Item {
  id: svcRoot

  property var shell: null
  property var manifest: null

  // --- Session Engine State ---
  property string phase: "idle" // "idle" | "focus" | "paused" | "rest"
  property int sessionId: 0
  property int sessionCategoryId: 0
  property string sessionGoal: ""
  property int workMinutes: 50
  property int restMinutes: 10
  property real sessionStart: 0
  property int elapsedSeconds: 0
  property int restRemaining: 0
  property string sessionNote: ""
  property var sessionTodos: []
  property bool breakOverlayVisible: false
  property bool breakNudgeActive: false
  property bool nativeDialogOpen: false
  readonly property bool newSessionOpen: newSessionWin.open

  property real _focusAnchorMs: 0
  property int _accumFocusSec: 0
  property real _pauseAnchorMs: 0
  property int _accumPausedSec: 0
  property int livePausedSeconds: 0
  property real _restEndMs: 0
  property int _lastNudgeBucket: 0
  property int _lastCheckpointBucket: 0

  // --- Omarchy DND integration state ---
  property bool _managedDnd: false
  property bool _priorDnd: false

  // --- Hydrated Backend Snapshot ---
  property var settings: ({
    language: "system",
    widgetStyle: "tag",
    widgetLeft: false,
    tagY: -1,
    positions: { capsule: [-1, -1], card: [-1, -1], ring: [-1, -1] },
    lastTopic: 0,
    rhythmMode: "50",
    rhythmWork: 50,
    customWork: 45,
    customRest: 10,
    weeklyOn: true,
    weeklyTemplate: "",
    todoistOn: false,
    todoistFilter: "today | overdue",
    themeMode: "omarchy",
    focusDnd: false,
    widgetScreen: ""
  })
  property string lang: "en"
  readonly property string widgetStyle: settings && settings.widgetStyle ? String(settings.widgetStyle) : "tag"
  readonly property string resolvedWidgetScreenName: onScreenWidgetWin.resolvedScreenName
  property string dbPath: "~/.local/share/houra/houra.sqlite"
  property string chimePath: ""
  property string lastCsvStatus: ""
  property bool todoistSyncing: false

  property var categories: []
  property var todayData: ({})
  property var weeklyData: ({})
  property var todoistData: ({})
  readonly property bool todoistConnected: !!(todoistData && todoistData.enabled && todoistData.hasToken)
  property var statsData: ({})
  property var historyData: []

  // Query filter state
  property string statsRangeStart: ""
  property string statsRangeEnd: ""
  property int statsTopicId: 0
  property bool historyNotesOnly: false
  property int historyTopicId: 0
  property string historyDayFilter: ""

  // Live theme tokens reactive to Omarchy's active theme OR Houra Classic mode
  readonly property var tokens: Theme.resolveTokens(
    settings && settings.themeMode ? String(settings.themeMode) : "omarchy",
    Commons.Color.background,
    Commons.Color.foreground,
    Commons.Color.accent,
    Commons.Color.urgent
  )

  readonly property var activeCategory: {
    for (var i = 0; i < categories.length; i++) {
      if (Number(categories[i].id) === sessionCategoryId) return categories[i]
    }
    return categories.length > 0 ? categories[0] : { id: 0, name: "General", color: "#4c8df0", emoji: "", icon: "", iconColor: "" }
  }

  readonly property string activeTodoTitle: {
    for (var i = 0; i < sessionTodos.length; i++) {
      if (Number(sessionTodos[i].state) === 1) return String(sessionTodos[i].title || "")
    }
    return ""
  }

  readonly property string clockText: {
    if (phase === "focus" || phase === "paused") {
      if (workMinutes > 0) {
        return Theme.formatClock(Math.max(0, workMinutes * 60 - elapsedSeconds))
      }
      return Theme.formatClock(elapsedSeconds)
    }
    if (phase === "rest") return Theme.formatClock(restRemaining)
    return "00:00"
  }

  readonly property string restClockText: Theme.formatClock(restRemaining)

  readonly property real plannedEndEpoch: {
    if ((phase !== "focus" && phase !== "paused") || workMinutes <= 0 || sessionStart <= 0) return 0
    return sessionStart + workMinutes * 60 + livePausedSeconds
  }

  readonly property real progress: {
    if (phase !== "focus" && phase !== "paused") return 0.0
    if (workMinutes > 0) {
      return Math.max(0.0, Math.min(1.0, elapsedSeconds / Math.max(1, workMinutes * 60)))
    }
    // Free mode fills to 1.0 over 50 minutes (3000s) matching Focus.swift:53
    return Math.max(0.0, Math.min(1.0, elapsedSeconds / 3000.0))
  }

  readonly property string backendScriptPath: {
    var u = String(Qt.resolvedUrl("backend/houra_cli.py"))
    return u.indexOf("file://") === 0 ? decodeURIComponent(u.slice(7)) : u
  }

  // --- Lifecycle ---
  Component.onCompleted: {
    Bridge.registerService(svcRoot)
    enqueueRpc("snapshot", _withQueryFilters({ resumeIfLive: true }), function(res) {
      var s = res && res.resumedSession ? res.resumedSession : null
      if (s && svcRoot.phase === "idle") {
        var el = Math.max(0, Number(s.elapsedSec) || 0)
        svcRoot.sessionId = Number(s.id)
        svcRoot.sessionCategoryId = Number(s.categoryId)
        svcRoot.sessionGoal = String(s.goal || "")
        svcRoot.workMinutes = Number(s.workMin)
        svcRoot.restMinutes = Number(s.restMin)
        svcRoot.sessionStart = Number(s.start)
        svcRoot.sessionNote = String(s.note || "")
        svcRoot.sessionTodos = s.todos || []
        svcRoot.elapsedSeconds = el
        svcRoot._accumFocusSec = el
        svcRoot._accumPausedSec = 0
        svcRoot.livePausedSeconds = 0
        svcRoot._focusAnchorMs = Date.now()
        svcRoot._lastNudgeBucket = Math.floor(el / 3000)
        svcRoot._lastCheckpointBucket = Math.floor(el / 60)
        svcRoot.breakNudgeActive = false
        svcRoot.breakOverlayVisible = false
        svcRoot.phase = "focus"
        svcRoot._applyFocusDndIfEnabled()
      }
    })
  }

  Component.onDestruction: {
    _restoreDndIfManaged()
    Bridge.unregisterService(svcRoot)
  }

  // --- Omarchy DND Sync ---
  function _notifService() {
    if (shell && typeof shell.serviceFor === "function") {
      return shell.serviceFor("omarchy.notifications")
    }
    return null
  }

  function _applyFocusDndIfEnabled() {
    if (!settings || !settings.focusDnd) {
      _restoreDndIfManaged()
      return
    }
    if (_managedDnd) return
    var ns = _notifService()
    if (!ns || typeof ns.setDoNotDisturb !== "function") return
    _priorDnd = !!ns.doNotDisturb
    _managedDnd = true
    if (!_priorDnd) ns.setDoNotDisturb(true)
  }

  function _restoreDndIfManaged() {
    if (!_managedDnd) return
    var ns = _notifService()
    if (ns && typeof ns.setDoNotDisturb === "function") {
      ns.setDoNotDisturb(_priorDnd)
    }
    _managedDnd = false
  }

  // --- Audio Chime ---
  function playChime() {
    if (!chimePath) return
    Quickshell.execDetached(["pw-play", "--volume=0.6", chimePath])
  }

  // --- Sequential RPC Queue to Python SQLite Backend ---
  property var _rpcQueue: []
  property bool _rpcBusy: false
  property var _currentRpc: null

  function _withQueryFilters(extra) {
    var p = ({
      activeSessionId: svcRoot.sessionId > 0 ? svcRoot.sessionId : null,
      rangeStart: svcRoot.statsRangeStart || null,
      rangeEnd: svcRoot.statsRangeEnd || null,
      statsTopicId: svcRoot.statsTopicId,
      historyNotesOnly: svcRoot.historyNotesOnly,
      historyTopicId: svcRoot.historyTopicId,
      historyDay: svcRoot.historyDayFilter
    })
    if (extra) {
      for (var k in extra) p[k] = extra[k]
    }
    return p
  }

  function enqueueRpc(cmd, payload, onDone) {
    _rpcQueue.push({ cmd: cmd, payload: payload || ({}), onDone: onDone || null })
    _pumpRpc()
  }

  function _pumpRpc() {
    if (_rpcBusy || _rpcQueue.length === 0) return
    _rpcBusy = true
    _currentRpc = _rpcQueue.shift()
    rpcProcess.stdinEnabled = true
    rpcProcess.command = [
      "python3",
      svcRoot.backendScriptPath,
      _currentRpc.cmd,
      "-"
    ]
    rpcProcess.running = true
    rpcProcess.write(JSON.stringify(_currentRpc.payload) + "\n")
    rpcProcess.stdinEnabled = false
  }

  function _applySnapshot(res) {
    if (!res || !res.ok) return
    if (res.settings) svcRoot.settings = res.settings
    if (res.resolvedLang) svcRoot.lang = res.resolvedLang
    if (res.dbPath) svcRoot.dbPath = res.dbPath
    if (res.chimePath) svcRoot.chimePath = res.chimePath
    if (res.categories) svcRoot.categories = res.categories
    if (res.today) svcRoot.todayData = res.today
    if (res.weekly) svcRoot.weeklyData = res.weekly
    if (res.todoist) svcRoot.todoistData = res.todoist
    if (res.stats) {
      svcRoot.statsData = res.stats
      if (!svcRoot.statsRangeStart && res.stats.rangeStart) svcRoot.statsRangeStart = res.stats.rangeStart
      if (!svcRoot.statsRangeEnd && res.stats.rangeEnd) svcRoot.statsRangeEnd = res.stats.rangeEnd
    }
    if (res.history) svcRoot.historyData = res.history
  }

  Process {
    id: rpcProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var finishedJob = svcRoot._currentRpc
        svcRoot._currentRpc = null
        svcRoot._rpcBusy = false

        var parsed = null
        var raw = String(text || "").trim()
        if (raw.length > 0) {
          try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
        }
        if (parsed && parsed.ok) {
          svcRoot._applySnapshot(parsed)
          if (finishedJob && finishedJob.onDone) {
            try { finishedJob.onDone(parsed) } catch (e2) {}
          }
        } else {
          svcRoot.todoistSyncing = false
        }
        svcRoot._pumpRpc()
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 && svcRoot._rpcBusy) {
        svcRoot._currentRpc = null
        svcRoot._rpcBusy = false
        svcRoot.todoistSyncing = false
        svcRoot._pumpRpc()
      }
    }
  }

  // Debounced live session note writer
  Timer {
    id: noteSaveTimer
    interval: 450
    onTriggered: {
      if (svcRoot.sessionId > 0) {
        svcRoot.enqueueRpc("set-session-note", {
          sessionId: svcRoot.sessionId,
          note: svcRoot.sessionNote
        }, null)
      }
    }
  }

  // --- 500ms Wall-Clock Session & Break Engine ---
  Timer {
    id: engineTimer
    interval: 500
    repeat: true
    running: svcRoot.phase === "focus" || svcRoot.phase === "paused" || svcRoot.phase === "rest"

    onTriggered: {
      var nowMs = Date.now()

      if (svcRoot.phase === "focus") {
        var deltaSec = Math.max(0, Math.floor((nowMs - svcRoot._focusAnchorMs) / 1000))
        svcRoot.elapsedSeconds = svcRoot._accumFocusSec + deltaSec
        svcRoot.livePausedSeconds = svcRoot._accumPausedSec

        if (svcRoot.workMinutes > 0) {
          if (svcRoot.elapsedSeconds >= svcRoot.workMinutes * 60) {
            svcRoot.elapsedSeconds = svcRoot.workMinutes * 60
            svcRoot.finishSession()
          }
        } else {
          // Free mode: checkpoint to SQLite every 60s & nudge every 50m (3000s)
          var cpBucket = Math.floor(svcRoot.elapsedSeconds / 60)
          if (cpBucket > svcRoot._lastCheckpointBucket) {
            svcRoot._lastCheckpointBucket = cpBucket
            if (svcRoot.sessionId > 0) {
              svcRoot.enqueueRpc("checkpoint-session", {
                sessionId: svcRoot.sessionId,
                focusSec: svcRoot.elapsedSeconds
              }, null)
            }
          }

          var nudgeBucket = Math.floor(svcRoot.elapsedSeconds / 3000)
          if (nudgeBucket > svcRoot._lastNudgeBucket) {
            svcRoot._lastNudgeBucket = nudgeBucket
            svcRoot.breakNudgeActive = true
            svcRoot.playChime()
            screenPulse.flash()
          }
        }
      } else if (svcRoot.phase === "paused") {
        var pDelta = Math.max(0, Math.floor((nowMs - svcRoot._pauseAnchorMs) / 1000))
        svcRoot.livePausedSeconds = svcRoot._accumPausedSec + pDelta
      } else if (svcRoot.phase === "rest") {
        var rem = Math.max(0, Math.ceil((svcRoot._restEndMs - nowMs) / 1000))
        svcRoot.restRemaining = rem
        if (rem <= 0) {
          svcRoot.phase = "idle"
          svcRoot._clearActiveSessionState()
          svcRoot.openNewSession(0, "")
        }
      }
    }
  }

  // --- Non-blocking Native Folder / CSV Picker Processes (Zenity with fallback) ---
  property string _pickerMode: "" // "weekly-folder" | "weekly-file" | "csv-save"

  Process {
    id: dialogProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var chosen = String(text || "").trim()
        var mode = svcRoot._pickerMode
        svcRoot._pickerMode = ""
        svcRoot.nativeDialogOpen = false
        if (!chosen) return
        var homeDir = Quickshell.env("HOME") || ""
        var pretty = (homeDir && chosen.indexOf(homeDir) === 0)
          ? ("~" + chosen.slice(homeDir.length))
          : chosen
        if (mode === "weekly-folder") {
          var cleanDir = pretty.replace(/\/+$/, "")
          svcRoot.patchSettings({ weeklyOn: true, weeklyTemplate: cleanDir + "/*{WW}*.md" })
        } else if (mode === "weekly-file") {
          svcRoot.patchSettings({ weeklyOn: true, weeklyTemplate: pretty })
        } else if (mode === "csv-save") {
          svcRoot.exportCsv(chosen)
        }
      }
    }
    onExited: function(exitCode) {
      var mode = svcRoot._pickerMode
      if (svcRoot.nativeDialogOpen) {
        svcRoot._pickerMode = ""
        svcRoot.nativeDialogOpen = false
      }
      // Exit code 127 means zenity is not installed -> fallback for CSV export
      if (exitCode === 127 && mode === "csv-save") {
        svcRoot.exportCsv("")
      }
    }
  }

  function chooseWeeklyFolder() {
    if (dialogProcess.running) return
    _pickerMode = "weekly-folder"
    nativeDialogOpen = true
    dialogProcess.command = [
      "zenity",
      "--file-selection",
      "--directory",
      "--title=" + Theme.t(lang, "Haftalık görev klasörünü seç", "Choose weekly tasks folder")
    ]
    dialogProcess.running = true
  }

  function chooseWeeklyFile() {
    if (dialogProcess.running) return
    _pickerMode = "weekly-file"
    nativeDialogOpen = true
    dialogProcess.command = [
      "zenity",
      "--file-selection",
      "--file-filter=Markdown (*.md) | *.md",
      "--title=" + Theme.t(lang, "Haftalık Markdown dosyasını seç", "Choose weekly Markdown file")
    ]
    dialogProcess.running = true
  }

  function exportCsvInteractive() {
    if (dialogProcess.running) return
    _pickerMode = "csv-save"
    nativeDialogOpen = true
    var dl = (Quickshell.env("HOME") || "") + "/Downloads/houra.csv"
    dialogProcess.command = [
      "zenity",
      "--file-selection",
      "--save",
      "--confirm-overwrite",
      "--filename=" + dl,
      "--title=" + Theme.t(lang, "CSV olarak dışa aktar", "Export as CSV")
    ]
    dialogProcess.running = true
  }

  // --- Public Actions ---

  function refreshSnapshot() {
    enqueueRpc("snapshot", _withQueryFilters({}), null)
  }

  function openNewSession(prefillCatId, prefillGoal, prefillWeeklyKey, prefillTodoistKey, prefillTodoId) {
    if (phase === "rest") {
      phase = "idle"
      _clearActiveSessionState()
    }
    refreshSnapshot()
    newSessionWin.showModal(
      Number(prefillCatId) || 0,
      String(prefillGoal || ""),
      String(prefillWeeklyKey || ""),
      String(prefillTodoistKey || ""),
      Number(prefillTodoId) || 0
    )
  }

  function openNewSessionForTodo(todoObj) {
    if (!todoObj) return
    openNewSession(
      Number(todoObj.categoryId) || 0,
      "",
      "",
      "",
      Number(todoObj.id) || 0
    )
  }

  function openNewSessionForWeekly(wt) {
    if (!wt) return
    openNewSession(Number(wt.categoryId) || 0, "", String(wt.key || ""), "", 0)
  }

  function openNewSessionForTodoist(td) {
    if (!td) return
    openNewSession(Number(td.categoryId) || 0, "", "", String(td.key || ""), 0)
  }

  function importTodoistTaskToToday(td) {
    if (!td) return
    enqueueRpc("add-todo", _withQueryFilters({
      title: String(td.title || ""),
      detail: String(td.detail || td.dueLabel || ""),
      todoistId: String(td.id || ""),
      priority: Number(td.priority) || 1,
      dueTime: String(td.dueTime || ""),
      categoryId: Number(td.categoryId) || 0
    }), null)
  }

  property var _clipboardCb: null

  Process {
    id: clipboardReadProcess
    command: ["wl-paste", "--no-newline"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cb = svcRoot._clipboardCb
        svcRoot._clipboardCb = null
        if (cb) {
          try { cb(String(text || "").trim()) } catch (e) {}
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) svcRoot._clipboardCb = null
    }
  }

  function readClipboardText(onText) {
    if (clipboardReadProcess.running) return
    _clipboardCb = onText || null
    clipboardReadProcess.running = true
  }

  function openTodoistDeveloperSettings() {
    Quickshell.execDetached(["xdg-open", "https://app.todoist.com/app/settings/integrations/developer"])
  }

  function saveTodoistToken(tok) {
    var clean = String(tok || "").trim()
    if (!clean) return
    todoistSyncing = true
    enqueueRpc("save-todoist-token", _withQueryFilters({ token: clean }), function() {
      svcRoot.todoistSyncing = false
    })
  }

  function clearTodoistToken() {
    enqueueRpc("clear-todoist-token", _withQueryFilters({}), null)
  }

  function syncTodoistNow(filterOpt, onFlag) {
    var extra = ({})
    if (filterOpt !== undefined && filterOpt !== null && String(filterOpt).trim() !== "") {
      extra.todoistFilter = String(filterOpt).trim()
    }
    if (onFlag !== undefined && onFlag !== null) {
      extra.todoistOn = !!onFlag
    }
    todoistSyncing = true
    enqueueRpc("sync-todoist", _withQueryFilters(extra), function() {
      svcRoot.todoistSyncing = false
    })
  }

  function setTodoistTaskCompleted(todoistId, completed, localTodoId) {
    var tdId = String(todoistId || "").trim()
    var lTid = Number(localTodoId) || 0
    if (!tdId && lTid <= 0) return
    todoistSyncing = true
    enqueueRpc("set-todoist-completed", _withQueryFilters({
      todoistId: tdId,
      completed: !!completed,
      todoId: lTid
    }), function(res) {
      svcRoot.todoistSyncing = false
      if (svcRoot.sessionId > 0 && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
    })
  }

  function createTodoistTask(taskObj, onDone) {
    var src = taskObj || ({})
    var title = String(src.title || "").trim()
    if (!title) return
    todoistSyncing = true
    var p = {
      title: title,
      detail: String(src.detail || ""),
      priority: Number(src.priority) || 1,
      scope: String(src.scope || "day"),
      day: String(src.day || ""),
      endDay: String(src.endDay || ""),
      dueTime: String(src.dueTime || ""),
      recurrence: String(src.recurrence || ""),
      categoryId: Number(src.categoryId) || 0,
      projectId: String(src.projectId || "")
    }
    enqueueRpc("create-todoist-task", _withQueryFilters(p), function(res) {
      svcRoot.todoistSyncing = false
      if (onDone) {
        try { onDone(res) } catch (e) {}
      }
    })
  }

  function updateTodoistTask(todoistId, patchObj, onDone) {
    var tdId = String(todoistId || "").trim()
    if (!tdId) return
    var src = patchObj || ({})
    var p = { todoistId: tdId }
    var keys = ["title", "detail", "description", "priority", "projectId", "scope", "day", "endDay", "dueTime", "recurrence", "clearDue"]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (src[k] !== undefined) p[k] = src[k]
    }
    todoistSyncing = true
    enqueueRpc("update-todoist-task", _withQueryFilters(p), function(res) {
      svcRoot.todoistSyncing = false
      if (svcRoot.sessionId > 0 && res && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
      if (onDone) {
        try { onDone(res) } catch (e) {}
      }
    })
  }

  function deleteTodoistTask(todoistId) {
    var tdId = String(todoistId || "").trim()
    if (!tdId) return
    todoistSyncing = true
    enqueueRpc("delete-todoist-task", _withQueryFilters({ todoistId: tdId }), function() {
      svcRoot.todoistSyncing = false
    })
  }

  function openMainPanel(tabName) {
    refreshSnapshot()
    mainPanelWin.showTab(tabName || "")
  }

  function toggleMainPanel() {
    if (mainPanelWin.open && mainPanelWin.isOnCurrentWorkspace()) {
      mainPanelWin.hideWindow()
    } else {
      refreshSnapshot()
      mainPanelWin.showTab("")
    }
  }

  function _focusedScreenName() {
    var mon = Hyprland.focusedMonitor
    if (mon && mon.name) return String(mon.name)
    return Quickshell.screens.length > 0 ? String(Quickshell.screens[0].name) : ""
  }

  function startNewSession(catId, goal, workMin, restMin, todoIds, extraTasks, rhythmMode, customWork, customRest) {
    var startEpoch = Date.now() / 1000.0
    var prevSid = 0
    var prevFocusSec = 0
    if ((phase === "focus" || phase === "paused") && sessionId > 0) {
      prevSid = sessionId
      if (phase === "focus") {
        var dSec = Math.max(0, Math.floor((Date.now() - _focusAnchorMs) / 1000))
        prevFocusSec = _accumFocusSec + dSec
      } else {
        prevFocusSec = _accumFocusSec
      }
      if (noteSaveTimer.running) {
        noteSaveTimer.stop()
        enqueueRpc("set-session-note", { sessionId: prevSid, note: sessionNote }, null)
      }
    }

    var rpcPayload = {
      categoryId: Number(catId),
      goal: String(goal || ""),
      workMin: Number(workMin),
      restMin: Number(restMin),
      start: startEpoch,
      todoIds: todoIds || [],
      extraTasks: extraTasks || [],
      closeSessionId: prevSid,
      closeFocusSec: prevFocusSec
    }
    if (rhythmMode) rpcPayload.rhythmMode = String(rhythmMode)
    if (customWork !== undefined && customWork !== null) rpcPayload.customWork = Number(customWork)
    if (customRest !== undefined && customRest !== null) rpcPayload.customRest = Number(customRest)

    enqueueRpc(
      "start-session",
      _withQueryFilters(rpcPayload),
      function(res) {
        var s = res.startedSession
        if (!s) return
        svcRoot.sessionId = Number(s.id)
        svcRoot.sessionCategoryId = Number(s.categoryId)
        svcRoot.sessionGoal = String(s.goal || "")
        svcRoot.workMinutes = Number(s.workMin)
        svcRoot.restMinutes = Number(s.restMin)
        svcRoot.sessionStart = Number(s.start)
        svcRoot.sessionNote = ""
        svcRoot.sessionTodos = s.todos || []
        svcRoot.elapsedSeconds = 0
        svcRoot._accumFocusSec = 0
        svcRoot._accumPausedSec = 0
        svcRoot.livePausedSeconds = 0
        svcRoot._focusAnchorMs = Date.now()
        svcRoot._lastNudgeBucket = 0
        svcRoot._lastCheckpointBucket = 0
        svcRoot.breakNudgeActive = false
        svcRoot.breakOverlayVisible = false
        svcRoot.phase = "focus"
        mainPanelWin.hideWindow()
        svcRoot._applyFocusDndIfEnabled()
      }
    )
  }

  function quickStartSession(catId, goal, workMin, restMin) {
    var rMin = restMin !== undefined ? Number(restMin) : (Number(workMin) === 25 ? 5 : 10)
    var rMode = Number(workMin) === 25 ? "25" : (Number(workMin) === 50 ? "50" : (Number(workMin) <= 0 ? "free" : "custom"))
    startNewSession(catId, goal, workMin, rMin, [], [], rMode, null, null)
  }

  function togglePause() {
    if (phase === "focus") {
      var delta = Math.max(0, Math.floor((Date.now() - _focusAnchorMs) / 1000))
      _accumFocusSec += delta
      elapsedSeconds = _accumFocusSec
      _pauseAnchorMs = Date.now()
      phase = "paused"
      _restoreDndIfManaged()
    } else if (phase === "paused") {
      var pDelta = Math.max(0, Math.floor((Date.now() - _pauseAnchorMs) / 1000))
      _accumPausedSec += pDelta
      livePausedSeconds = _accumPausedSec
      _focusAnchorMs = Date.now()
      phase = "focus"
      _applyFocusDndIfEnabled()
    }
  }

  function dismissBreakNudge() {
    breakNudgeActive = false
  }

  function _clearActiveSessionState() {
    breakNudgeActive = false
    breakOverlayVisible = false
    sessionId = 0
    sessionGoal = ""
    sessionNote = ""
    sessionTodos = []
    elapsedSeconds = 0
    _accumFocusSec = 0
    _accumPausedSec = 0
    livePausedSeconds = 0
    restRemaining = 0
  }

  function finishSession() {
    if (phase !== "focus" && phase !== "paused") return
    if (phase === "focus") {
      var delta = Math.max(0, Math.floor((Date.now() - _focusAnchorMs) / 1000))
      _accumFocusSec += delta
      elapsedSeconds = _accumFocusSec
    }
    var finishedId = sessionId
    var finalFocusSec = Math.max(0, elapsedSeconds)
    var rMin = Math.max(1, restMinutes || 5)
    breakNudgeActive = false
    _restoreDndIfManaged()

    if (noteSaveTimer.running && finishedId > 0) {
      noteSaveTimer.stop()
      enqueueRpc("set-session-note", { sessionId: finishedId, note: sessionNote }, null)
    }

    if (finishedId > 0) {
      enqueueRpc("finish-session", _withQueryFilters({
        sessionId: finishedId,
        focusSec: finalFocusSec,
        end: Date.now() / 1000.0
      }), null)
    }

    restRemaining = rMin * 60
    _restEndMs = Date.now() + restRemaining * 1000
    phase = "rest"
    breakOverlayVisible = true
  }

  function closeSessionWithoutBreak() {
    if (phase !== "focus" && phase !== "paused") return
    if (phase === "focus") {
      var delta = Math.max(0, Math.floor((Date.now() - _focusAnchorMs) / 1000))
      _accumFocusSec += delta
      elapsedSeconds = _accumFocusSec
    }
    var finishedId = sessionId
    var finalFocusSec = Math.max(0, elapsedSeconds)
    var pendingNote = sessionNote
    var hadPendingNote = noteSaveTimer.running
    if (hadPendingNote) noteSaveTimer.stop()
    _restoreDndIfManaged()

    phase = "idle"
    _clearActiveSessionState()

    if (hadPendingNote && finishedId > 0) {
      enqueueRpc("set-session-note", { sessionId: finishedId, note: pendingNote }, null)
    }

    if (finishedId > 0) {
      enqueueRpc("finish-session", _withQueryFilters({
        sessionId: finishedId,
        focusSec: finalFocusSec,
        end: Date.now() / 1000.0,
        skipBreak: true
      }), null)
    } else {
      refreshSnapshot()
    }
  }

  function cancelSession() {
    if (phase !== "focus" && phase !== "paused") return
    var cancelledId = sessionId
    if (noteSaveTimer.running) noteSaveTimer.stop()
    _restoreDndIfManaged()

    phase = "idle"
    _clearActiveSessionState()

    if (cancelledId > 0) {
      enqueueRpc("cancel-session", _withQueryFilters({ sessionId: cancelledId }), null)
    } else {
      refreshSnapshot()
    }
  }

  function deleteSession(targetSid) {
    var sid = Number(targetSid) || 0
    if (sid <= 0) return
    if (sid === sessionId && (phase === "focus" || phase === "paused")) {
      cancelSession()
      return
    }
    if (sid === sessionId && phase === "rest") {
      phase = "idle"
      _clearActiveSessionState()
    }
    enqueueRpc("delete-session", _withQueryFilters({ sessionId: sid }), null)
  }

  function emergencyExit() {
    if (phase !== "rest") return
    breakOverlayVisible = false
    if (sessionId > 0) {
      enqueueRpc("mark-emergency", _withQueryFilters({ sessionId: sessionId }), null)
    }
  }

  function returnToBreak() {
    if (phase === "rest") {
      breakOverlayVisible = true
    }
  }

  function endBreakAndStartNew() {
    phase = "idle"
    _clearActiveSessionState()
    openNewSession(0, "")
  }

  function updateSessionNote(nextNote) {
    sessionNote = String(nextNote || "")
    if (sessionId > 0) noteSaveTimer.restart()
  }

  function addTodo(title, detail, opts) {
    var extra = opts || ({})
    var p = {
      title: String(title || ""),
      detail: String(detail || "")
    }
    if (extra.priority !== undefined) p.priority = Number(extra.priority) || 1
    if (extra.scope !== undefined) p.scope = String(extra.scope || "day")
    if (extra.day !== undefined) p.day = String(extra.day || "")
    if (extra.endDay !== undefined) p.endDay = String(extra.endDay || "")
    if (extra.dueTime !== undefined) p.dueTime = String(extra.dueTime || "")
    if (extra.recurrence !== undefined) p.recurrence = String(extra.recurrence || "")
    if (extra.categoryId !== undefined) p.categoryId = Number(extra.categoryId) || 0
    if (extra.todoistId !== undefined) p.todoistId = String(extra.todoistId || "")
    enqueueRpc("add-todo", _withQueryFilters(p), null)
  }

  function updateTodo(todoId, patchObj) {
    var tid = Number(todoId) || 0
    if (tid <= 0) return
    var src = patchObj || ({})
    var p = { todoId: tid }
    var keys = ["title", "detail", "priority", "scope", "day", "endDay", "dueTime", "recurrence", "categoryId"]
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (src[k] !== undefined) p[k] = src[k]
    }
    enqueueRpc("update-todo", _withQueryFilters(p), function(res) {
      if (svcRoot.sessionId > 0 && res && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
    })
  }

  function cycleTodoState(todoId) {
    enqueueRpc("set-todo-state", _withQueryFilters({
      todoId: Number(todoId)
    }), function(res) {
      if (svcRoot.sessionId > 0 && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
    })
  }

  function setTodoStateExplicit(todoId, nextState) {
    enqueueRpc("set-todo-state", _withQueryFilters({
      todoId: Number(todoId),
      state: Number(nextState)
    }), function(res) {
      if (svcRoot.sessionId > 0 && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
    })
  }

  function deleteTodo(todoId) {
    enqueueRpc("delete-todo", _withQueryFilters({ todoId: Number(todoId) }), function(res) {
      if (svcRoot.sessionId > 0 && Array.isArray(res.activeSessionTodos)) {
        svcRoot.sessionTodos = res.activeSessionTodos
      }
    })
  }

  function addCategory(name, color, emoji, iconName, iconColor) {
    enqueueRpc("add-category", _withQueryFilters({
      name: name,
      color: color,
      emoji: emoji,
      icon: iconName,
      iconColor: iconColor
    }), null)
  }

  function updateCategory(catId, name, color, emoji, iconName, iconColor) {
    enqueueRpc("update-category", _withQueryFilters({
      id: Number(catId),
      name: name,
      color: color,
      emoji: emoji,
      icon: iconName,
      iconColor: iconColor
    }), null)
  }

  function deleteCategory(catId) {
    enqueueRpc("delete-category", _withQueryFilters({ id: Number(catId) }), null)
  }

  function patchSettings(patchObj) {
    enqueueRpc("save-settings", _withQueryFilters({ settings: patchObj }), function() {
      if (svcRoot.phase === "focus") {
        svcRoot._applyFocusDndIfEnabled()
      }
    })
  }

  function setWidgetStyle(styleKey) {
    var allowed = ["tag", "strip", "capsule", "card", "ring", "none"]
    if (allowed.indexOf(styleKey) === -1) return
    patchSettings({ widgetStyle: styleKey })
  }

  function saveWidgetPlacement(onLeftVal, tagYVal, floatKey, fx, fy, nextScreenName) {
    var patch = { widgetLeft: !!onLeftVal, tagY: Number(tagYVal) }
    if (nextScreenName) patch.widgetScreen = String(nextScreenName)
    if (floatKey && fx >= 0 && fy >= 0) {
      var posMap = ({})
      posMap[floatKey] = [Math.round(fx), Math.round(fy)]
      patch.positions = posMap
    }
    patchSettings(patch)
  }

  function setStatsRange(startIso, endIso, topicId) {
    statsRangeStart = String(startIso || "")
    statsRangeEnd = String(endIso || "")
    statsTopicId = Number(topicId) || 0
    refreshSnapshot()
  }

  function setHistoryFilter(notesOnly, topicId, dayIso) {
    historyNotesOnly = !!notesOnly
    historyTopicId = Number(topicId) || 0
    historyDayFilter = String(dayIso || "")
    refreshSnapshot()
  }

  function openDataFolder() {
    var folder = dbPath
    var slash = folder.lastIndexOf("/")
    if (slash > 0) folder = folder.slice(0, slash)
    Quickshell.execDetached(["xdg-open", folder])
  }

  function exportCsv(customPath) {
    var p = customPath ? { path: String(customPath) } : {}
    enqueueRpc("export-csv", p, function(res) {
      if (res && res.csvPath) {
        svcRoot.lastCsvStatus = Theme.t(svcRoot.lang, "Dışa aktarıldı: ", "Exported: ") + res.csvPath + " (" + (res.count || 0) + ")"
      }
    })
  }

  // --- Global IPC Handler (`omarchy-shell houra <command>`) ---
  IpcHandler {
    target: "houra"

    function newSession(): string {
      if (newSessionWin.open && newSessionWin.isOnCurrentWorkspace()) newSessionWin.closeModal()
      else svcRoot.openNewSession(0, "")
      return "ok"
    }

    function panel(): string {
      svcRoot.toggleMainPanel()
      return "ok"
    }

    function stats(): string {
      svcRoot.openMainPanel("stats")
      return "ok"
    }

    function tab(name: string): string {
      svcRoot.openMainPanel(String(name || "today").trim().toLowerCase())
      return "ok"
    }

    function close(): string {
      newSessionWin.closeModal()
      mainPanelWin.hideWindow()
      return "ok"
    }

    function toggle(): string {
      var mon = Hyprland.focusedMonitor
      var sname = mon && mon.name ? String(mon.name) : ""
      var bw = Bridge.barWidgetForScreen(sname)
      if (bw && typeof bw.togglePanel === "function") {
        bw.togglePanel()
        return "popout"
      }
      svcRoot.toggleMainPanel()
      return "panel"
    }

    function pause(): string {
      svcRoot.togglePause()
      return svcRoot.phase
    }

    function finish(): string {
      svcRoot.finishSession()
      return svcRoot.phase
    }

    function closeSession(): string {
      svcRoot.closeSessionWithoutBreak()
      return svcRoot.phase
    }

    function cancel(): string {
      svcRoot.cancelSession()
      return svcRoot.phase
    }

    function syncTodoist(): string {
      svcRoot.syncTodoistNow("", null)
      return "ok"
    }

    function style(name: string): string {
      svcRoot.setWidgetStyle(String(name || "").trim().toLowerCase())
      return svcRoot.widgetStyle
    }

    function status(): string {
      return JSON.stringify({
        phase: svcRoot.phase,
        clock: svcRoot.clockText,
        category: svcRoot.activeCategory ? svcRoot.activeCategory.name : "",
        goal: svcRoot.sessionGoal,
        activeTodo: svcRoot.activeTodoTitle,
        widgetStyle: svcRoot.widgetStyle,
        widgetScreen: svcRoot.settings && svcRoot.settings.widgetScreen ? String(svcRoot.settings.widgetScreen) : "",
        activeScreen: onScreenWidgetWin.resolvedScreenName
      })
    }
  }

  // --- Mounted Wayland & Floating Windows ---

  NewSessionWindow {
    id: newSessionWin
    service: svcRoot
    fontFamily: Style.font.family
  }

  OnScreenWidgetWindow {
    id: onScreenWidgetWin
    service: svcRoot
    fontFamily: Style.font.family
  }

  ScreenPulseOverlay {
    id: screenPulse
  }

  RestOverlayWindow {
    id: restOverlayWin
    service: svcRoot
    active: svcRoot.phase === "rest" && svcRoot.breakOverlayVisible
    fontFamily: Style.font.family
  }

  MainPanelWindow {
    id: mainPanelWin
    service: svcRoot
  }
}
