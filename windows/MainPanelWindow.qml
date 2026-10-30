import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import "../Theme.js" as Theme
import "../IconData.js" as IconData
import "../components"
import "../pages"

// Native Wayland FloatingWindow application panel (1120x740 max) matching Panel.swift:
// Fixed min/max size hints (`minimumSize === maximumSize`) make Hyprland automatically
// float and center the window without custom windowrules, while allowing the user's
// native Hyprland window-close shortcut (e.g. SUPER+W / killactive) as well as Ctrl+W,
// Ctrl+Q, Esc, the × button, and SUPER+ALT+H toggle to close it cleanly.
Item {
  id: root

  property var service: null
  property bool open: false
  property bool closingFromHost: false
  property string currentTab: "today" // "today" | "stats" | "sessions" | "categories" | "settings"
  property string focusZone: "page" // "page" | "sidebar"
  property bool sidebarOnCta: false
  property var openedScreen: null
  property int openedWorkspaceId: -1
  property string openedMonitorName: ""

  readonly property var tabOrder: ["today", "stats", "sessions", "categories", "settings"]
  readonly property var activePage: {
    if (currentTab === "stats") return statsPageItem
    if (currentTab === "sessions") return sessionsPageItem
    if (currentTab === "categories") return categoriesPageItem
    if (currentTab === "settings") return settingsPageItem
    return todayPageItem
  }
  readonly property bool activePageEditing: !!(activePage && activePage.isEditingText)

  onActivePageEditingChanged: {
    if (!activePageEditing && open && win.visible) {
      Qt.callLater(function() {
        if (root.open && !root.activePageEditing) keySink.forceActiveFocus()
      })
    }
  }

  function selectTabByIndex(idx, keepSidebarFocus) {
    if (idx < 0 || idx >= tabOrder.length) return
    if (activePage && activePage.releaseTextFocus) activePage.releaseTextFocus()
    sidebarOnCta = false
    currentTab = tabOrder[idx]
    focusZone = keepSidebarFocus ? "sidebar" : "page"
    keySink.forceActiveFocus()
  }

  function stepTab(delta, keepSidebarFocus) {
    var cur = tabOrder.indexOf(currentTab)
    if (cur < 0) cur = 0
    var next = (cur + delta + tabOrder.length) % tabOrder.length
    selectTabByIndex(next, !!keepSidebarFocus)
  }

  function stepSidebarItem(delta) {
    var total = tabOrder.length + 1 // 5 tabs + "+ New session" CTA
    var cur = sidebarOnCta ? tabOrder.length : Math.max(0, tabOrder.indexOf(currentTab))
    var next = (cur + delta + total) % total
    if (next === tabOrder.length) {
      sidebarOnCta = true
    } else {
      sidebarOnCta = false
      currentTab = tabOrder[next]
    }
  }

  readonly property string lang: service ? service.lang : "en"
  readonly property var tokens: service ? service.tokens : ({})
  property string fontFamily: Style.font.family

  readonly property int availW: openedScreen && openedScreen.width > 0 ? openedScreen.width : 1280
  readonly property int availH: openedScreen && openedScreen.height > 0 ? openedScreen.height : 800
  readonly property int targetWidth: Math.max(760, Math.min(Math.round(availW * 0.90), 1120))
  readonly property int targetHeight: Math.max(520, Math.min(Math.round(availH * 0.88), 740))

  function _resolveFocusedScreen() {
    var mon = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    if (mon && screens) {
      for (var i = 0; i < screens.length; i++) {
        if (screens[i].name === mon.name) return screens[i]
      }
    }
    return screens && screens.length > 0 ? screens[0] : null
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

  function showTab(tabKey) {
    if (tabKey) currentTab = tabKey
    var nextScreen = _resolveFocusedScreen()
    var nextMonName = nextScreen && nextScreen.name ? String(nextScreen.name) : ""
    var nextWsId = _currentWorkspaceId()
    var isFocusedNow = !!(Hyprland.activeToplevel && Hyprland.activeToplevel.title === "Houra")
    var needRemap = win.visible && (
      !isFocusedNow
      || (nextWsId !== -1 && openedWorkspaceId !== -1 && nextWsId !== openedWorkspaceId)
      || (nextMonName !== "" && openedMonitorName !== "" && nextMonName !== openedMonitorName)
    )

    if (nextScreen) openedScreen = nextScreen
    openedMonitorName = nextMonName
    openedWorkspaceId = nextWsId
    sidebarOnCta = false
    focusZone = "page"
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
          if (root.open) keySink.forceActiveFocus()
        })
      })
    } else {
      closingFromHost = false
      win.visible = true
      Qt.callLater(function() {
        if (root.open) keySink.forceActiveFocus()
      })
    }
  }

  function hideWindow() {
    if (activePage && activePage.releaseTextFocus) activePage.releaseTextFocus()
    sidebarOnCta = false
    closingFromHost = true
    open = false
    win.visible = false
    closingFromHost = false
  }

  FloatingWindow {
    id: win
    visible: false
    screen: root.openedScreen
    title: "Houra"
    implicitWidth: root.targetWidth
    implicitHeight: root.targetHeight
    minimumSize: Qt.size(root.targetWidth, root.targetHeight)
    maximumSize: Qt.size(root.targetWidth, root.targetHeight)
    color: root.tokens.win || "#0e0e10"

    onClosed: {
      if (!root.closingFromHost) root.hideWindow()
    }

    onVisibleChanged: {
      if (!visible && !root.closingFromHost) root.hideWindow()
    }

    Rectangle {
      id: panelCard
      anchors.fill: parent
      color: root.tokens.win || "#0e0e10"
      clip: true

      FocusScope {
        id: panelKeyScope
        anchors.fill: parent
        focus: true
        Keys.priority: Keys.BeforeItem

        Item {
          id: keySink
          focus: true
        }

        Keys.onPressed: function(event) {
          var k = event.key
          var mods = event.modifiers

          // 1. Always-active window close shortcuts
          if ((mods & Qt.ControlModifier) && (k === Qt.Key_W || k === Qt.Key_Q)) {
            event.accepted = true
            root.hideWindow()
            return
          }

          // 2. Layered Esc: focused TextInput -> page sub-overlay -> close window
          if (k === Qt.Key_Escape) {
            event.accepted = true
            if (root.activePage && root.activePage.releaseTextFocus && root.activePage.releaseTextFocus()) {
              keySink.forceActiveFocus()
              return
            }
            if (root.activePage && root.activePage.dismissOverlay && root.activePage.dismissOverlay()) {
              keySink.forceActiveFocus()
              return
            }
            root.hideWindow()
            return
          }

          // 3. Standard Ctrl+Tab / Ctrl+Shift+Tab tab switching
          if ((mods & Qt.ControlModifier) && !(mods & Qt.AltModifier)) {
            if (k === Qt.Key_Tab || k === Qt.Key_Backtab || k === Qt.Key_PageDown || k === Qt.Key_PageUp) {
              event.accepted = true
              var back = (k === Qt.Key_Backtab || k === Qt.Key_PageUp || (mods & Qt.ShiftModifier))
              root.stepTab(back ? -1 : 1, false)
              return
            }
          }

          // 4. Plain Tab / Shift+Tab cycles sidebar <-> page focus stops
          if (!(mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) && (k === Qt.Key_Tab || k === Qt.Key_Backtab)) {
            var rev = (k === Qt.Key_Backtab || (mods & Qt.ShiftModifier))
            var delta = rev ? -1 : 1
            if (root.focusZone === "page" && root.activePage && root.activePage.hasOpenOverlay && root.activePage.hasOpenOverlay()) {
              if (root.activePage.handleKey && root.activePage.handleKey(event)) {
                event.accepted = true
                return
              }
            }
            event.accepted = true
            if (root.focusZone === "sidebar") {
              root.sidebarOnCta = false
              root.focusZone = "page"
              if (root.activePage && root.activePage.enterFromTab) {
                root.activePage.enterFromTab(delta)
              }
            } else {
              if (root.activePage && root.activePage.stepFocus && root.activePage.stepFocus(delta)) {
                return
              }
              if (root.activePage && root.activePage.releaseTextFocus) root.activePage.releaseTextFocus()
              root.focusZone = "sidebar"
              root.sidebarOnCta = false
              keySink.forceActiveFocus()
            }
            return
          }

          // 5. Never intercept typing inside a focused TextInput
          if (root.activePageEditing) return
          if (mods & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return

          // 6. Sidebar arrow navigation
          if (root.focusZone === "sidebar") {
            if (k === Qt.Key_Down) { root.stepSidebarItem(1); event.accepted = true; return }
            if (k === Qt.Key_Up) { root.stepSidebarItem(-1); event.accepted = true; return }
            if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
              event.accepted = true
              if (root.sidebarOnCta) {
                if (root.service) root.service.openNewSession(0, "")
              } else {
                root.focusZone = "page"
              }
              return
            }
            if (k === Qt.Key_Right) {
              root.sidebarOnCta = false
              root.focusZone = "page"
              event.accepted = true
              return
            }
            return
          }

          // 7. Active page arrow / Enter / Delete delegation
          if (root.activePage && root.activePage.handleKey) {
            var res = root.activePage.handleKey(event)
            if (res === "sidebar") {
              root.focusZone = "sidebar"
              root.sidebarOnCta = false
              event.accepted = true
              return
            }
            if (res) {
              event.accepted = true
              return
            }
          }
        }

        Row {
          anchors.fill: parent

          // --- LEFT SIDEBAR (216px) ---
          Rectangle {
            width: 216
            height: parent.height
            color: root.tokens.sidebar || "#0a0a0c"

            Rectangle {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.bottom: parent.bottom
              width: 1
              color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
            }

            // Top Brand + Primary Nav
            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.margins: 16
              spacing: 18

              // Brand header + close button
              Item {
                width: parent.width
                height: 26

                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 10

                  HouraGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    glyphSize: 18
                    phase: root.service ? root.service.phase : "idle"
                    progress: root.service ? root.service.progress : 0
                    inkColor: root.tokens.ink || "#ffffff"
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Houra"
                    font.family: root.fontFamily
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    color: root.tokens.ink || "#ffffff"
                  }
                }

                Rectangle {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  width: 24
                  height: 24
                  radius: 7
                  color: closeHov.containsMouse
                    ? (root.tokens.raised || "#282830")
                    : "transparent"

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    color: closeHov.containsMouse
                      ? (root.tokens.ink || "#ffffff")
                      : (root.tokens.muted || "#888888")
                  }

                  MouseArea {
                    id: closeHov
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.hideWindow()
                  }
                }
              }

              // Primary Navigation items
              Column {
                width: parent.width
                spacing: 4

                Repeater {
                  model: [
                    { key: "today", icon: "clock", label: Theme.t(root.lang, "Bugün", "Today") },
                    { key: "stats", icon: "chart-bar", label: Theme.t(root.lang, "İstatistikler", "Statistics") },
                    { key: "sessions", icon: "list-bullets", label: Theme.t(root.lang, "Oturumlar", "Sessions") },
                    { key: "categories", icon: "squares-four", label: Theme.t(root.lang, "Kategoriler", "Categories") }
                  ]
                  delegate: Rectangle {
                    id: navPill
                    readonly property bool active: root.currentTab === modelData.key
                    readonly property bool sidebarFocused: active && root.focusZone === "sidebar" && !root.sidebarOnCta
                    readonly property string svgPath: IconData.pathFor(modelData.icon)
                    width: parent.width
                    height: 36
                    radius: 9
                    color: active
                      ? (root.tokens.raised || "#26262e")
                      : (navHov.containsMouse ? (root.tokens.card || "#16161b") : "transparent")
                    border.width: sidebarFocused ? 1.5 : 0
                    border.color: root.tokens.ink || "#ffffff"

                    Row {
                      anchors.left: parent.left
                      anchors.leftMargin: 12
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 10

                      Shape {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 15
                        height: 15
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                          strokeWidth: 0
                          strokeColor: "transparent"
                          fillColor: navPill.active ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#777777")
                          scale: Qt.size(15.0 / 256.0, 15.0 / 256.0)
                          PathSvg { path: navPill.svgPath }
                        }
                      }

                      Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.label
                        font.family: root.fontFamily
                        font.pixelSize: 13
                        font.weight: navPill.active ? Font.DemiBold : Font.Normal
                        color: navPill.active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#bbbbbb")
                      }
                    }

                    MouseArea {
                      id: navHov
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        root.sidebarOnCta = false
                        root.currentTab = modelData.key
                        root.focusZone = "page"
                        keySink.forceActiveFocus()
                      }
                    }
                  }
                }
              }
            }

            // Bottom Settings + "+ New session" CTA (Panel.swift:79-91)
            Column {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.margins: 16
              spacing: 10

              // Settings nav item
              Rectangle {
                id: settingsPill
                readonly property bool active: root.currentTab === "settings"
                readonly property bool sidebarFocused: active && root.focusZone === "sidebar" && !root.sidebarOnCta
                readonly property string gearPath: IconData.pathFor("gear")
                width: parent.width
                height: 34
                radius: 9
                color: active
                  ? (root.tokens.raised || "#26262e")
                  : (setHov.containsMouse ? (root.tokens.card || "#16161b") : "transparent")
                border.width: sidebarFocused ? 1.5 : 0
                border.color: root.tokens.ink || "#ffffff"

                Row {
                  anchors.left: parent.left
                  anchors.leftMargin: 12
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: 10

                  Shape {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 15
                    height: 15
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                      strokeWidth: 0
                      strokeColor: "transparent"
                      fillColor: settingsPill.active ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#777777")
                      scale: Qt.size(15.0 / 256.0, 15.0 / 256.0)
                      PathSvg { path: settingsPill.gearPath }
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.t(root.lang, "Ayarlar", "Settings")
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: settingsPill.active ? Font.DemiBold : Font.Normal
                    color: settingsPill.active ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#bbbbbb")
                  }
                }

                MouseArea {
                  id: setHov
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.sidebarOnCta = false
                    root.currentTab = "settings"
                    root.focusZone = "page"
                    keySink.forceActiveFocus()
                  }
                }
              }

              // Primary CTA: always "+ New session" (matching Panel.swift:79-91)
              Rectangle {
                readonly property bool ctaFocused: root.focusZone === "sidebar" && root.sidebarOnCta
                width: parent.width
                height: 38
                radius: 10
                color: (ctaHov.containsMouse || ctaFocused)
                  ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.86)
                  : (root.tokens.primaryBg || "#ffffff")
                border.width: ctaFocused ? 2 : 0
                border.color: root.tokens.accent || "#3d8cff"

                Text {
                  anchors.centerIn: parent
                  text: "+ " + Theme.t(root.lang, "Yeni oturum", "New session")
                  font.family: root.fontFamily
                  font.pixelSize: 13
                  font.weight: Font.DemiBold
                  color: root.tokens.primaryInk || "#0a0a0c"
                }

                MouseArea {
                  id: ctaHov
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (root.service) root.service.openNewSession(0, "")
                  }
                }
              }
            }
          }

          // --- ACTIVE PAGE CONTENT ---
          Item {
            width: parent.width - 216
            height: parent.height

            TodayPage {
              id: todayPageItem
              anchors.fill: parent
              visible: root.currentTab === "today"
              service: root.service
              fontFamily: root.fontFamily
              kbPageActive: root.currentTab === "today" && root.focusZone === "page"
            }

            StatsPage {
              id: statsPageItem
              anchors.fill: parent
              visible: root.currentTab === "stats"
              service: root.service
              fontFamily: root.fontFamily
              kbPageActive: root.currentTab === "stats" && root.focusZone === "page"
              onJumpToSessionsDay: function(dayIso) {
                if (root.service) root.service.setHistoryFilter(false, 0, dayIso)
                root.currentTab = "sessions"
                root.focusZone = "page"
                keySink.forceActiveFocus()
              }
            }

            SessionsPage {
              id: sessionsPageItem
              anchors.fill: parent
              visible: root.currentTab === "sessions"
              service: root.service
              fontFamily: root.fontFamily
              kbPageActive: root.currentTab === "sessions" && root.focusZone === "page"
            }

            CategoriesPage {
              id: categoriesPageItem
              anchors.fill: parent
              visible: root.currentTab === "categories"
              service: root.service
              fontFamily: root.fontFamily
              kbPageActive: root.currentTab === "categories" && root.focusZone === "page"
            }

            SettingsPage {
              id: settingsPageItem
              anchors.fill: parent
              visible: root.currentTab === "settings"
              service: root.service
              fontFamily: root.fontFamily
              kbPageActive: root.currentTab === "settings" && root.focusZone === "page"
            }
          }
        }
      }
    }
  }
}
