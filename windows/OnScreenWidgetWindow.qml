import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import "../Theme.js" as Theme
import "../components"

// Ambient Wayland layer-shell host for all 5 Houra on-screen views
// (Tag, Thin strip, Capsule, Card, Ring), Free-mode 50m Break Nudge,
// and the 300ms hover slide-out DetailCard.
// Uses multi-region Wayland input masks so every pixel outside the
// active widget chrome (and open detail card) is 100% click-through.
Item {
  id: root

  property var service: null
  readonly property string styleName: service ? service.widgetStyle : "tag"
  readonly property bool active: !!service
    && (service.phase === "focus" || service.phase === "paused")
    && styleName !== "none"
    && !service.breakOverlayVisible

  readonly property string lang: service ? service.lang : "en"
  readonly property var tokens: service ? service.tokens : ({})
  property string fontFamily: Style.font.family

  readonly property var activeCat: service ? service.activeCategory : null
  readonly property string catColor: activeCat && activeCat.color ? activeCat.color : "#4c8df0"
  readonly property string accentInk: tokens.primaryBg || "#ffffff"
  readonly property string headline: {
    if (!service) return ""
    if (service.activeTodoTitle && service.activeTodoTitle.length > 0) return service.activeTodoTitle
    if (service.sessionGoal && service.sessionGoal.length > 0) return service.sessionGoal
    return activeCat ? activeCat.name : "Focus"
  }
  readonly property string capsuleSubtitle: {
    var cname = activeCat ? String(activeCat.name || "") : ""
    if (!service) return cname
    var goal = String(service.sessionGoal || "")
    if (service.activeTodoTitle && service.activeTodoTitle.length > 0 && goal.length > 0 && goal !== cname) {
      return cname + " · " + goal
    }
    return cname
  }

  property bool onLeft: service && service.settings ? !!service.settings.widgetLeft : false
  property real tagYRatio: service && service.settings && Number(service.settings.tagY) >= 0
    ? Number(service.settings.tagY)
    : 0.42
  property real floatX: -1
  property real floatY: -1
  property real dragLiveX: -1
  property real dragLiveY: -1
  property bool dragging: false
  property bool detailOpen: false

  readonly property bool nudgeShown: !!service && service.breakNudgeActive

  onNudgeShownChanged: {
    if (nudgeShown) {
      detailOpen = false
      dragging = false
    }
  }

  Connections {
    target: root.service
    function onSettingsChanged() {
      if (root.dragging || !root.service || !root.service.settings) return
      root.onLeft = !!root.service.settings.widgetLeft
      if (Number(root.service.settings.tagY) >= 0) root.tagYRatio = Number(root.service.settings.tagY)
      root.syncFloatingPos()
    }
    function onWidgetStyleChanged() {
      root.detailOpen = false
      root.dragging = false
      root.syncFloatingPos()
    }
    function onPhaseChanged() {
      if (!root.active) {
        root.detailOpen = false
        root.dragging = false
      }
    }
  }

  function syncFloatingPos() {
    if (!service || !service.settings || !service.settings.positions) return
    var key = styleName
    if (key !== "capsule" && key !== "card" && key !== "ring") return
    var pair = service.settings.positions[key]
    if (pair && pair.length === 2 && Number(pair[0]) >= 0 && Number(pair[1]) >= 0) {
      floatX = Number(pair[0])
      floatY = Number(pair[1])
    } else {
      floatX = -1
      floatY = -1
    }
  }

  Component.onCompleted: syncFloatingPos()

  // Never bind to Hyprland.focusedMonitor so switching monitors/workspaces
  // keeps the widget anchored where the user placed it.
  readonly property var targetScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var pinned = service && service.settings && service.settings.widgetScreen
      ? String(service.settings.widgetScreen)
      : ""
    if (pinned) {
      for (var i = 0; i < screens.length; i++) {
        if (String(screens[i].name) === pinned) return screens[i]
      }
    }
    return screens[0]
  }

  readonly property string resolvedScreenName: targetScreen && targetScreen.name ? String(targetScreen.name) : ""

  // Find adjacent monitor horizontally (-1 = left neighbor, +1 = right neighbor)
  function _findAdjacentScreen(dir) {
    var screens = Quickshell.screens
    if (!screens || screens.length <= 1 || !overlayWin.screen) return null
    var curMon = Hyprland.monitorFor(overlayWin.screen)
    if (!curMon) return null
    var curScale = curMon.scale > 0 ? curMon.scale : 1.0
    var curLeft = curMon.x
    var curRight = curMon.x + Math.round(curMon.width / curScale)

    var bestScreen = null
    var bestDist = 999999
    for (var i = 0; i < screens.length; i++) {
      var cand = screens[i]
      if (cand === overlayWin.screen) continue
      var m = Hyprland.monitorFor(cand)
      if (!m) continue
      var mScale = m.scale > 0 ? m.scale : 1.0
      var mLeft = m.x
      var mRight = m.x + Math.round(m.width / mScale)
      if (dir < 0 && mRight <= curLeft + 24) {
        var dLeft = Math.abs(curLeft - mRight)
        if (dLeft < bestDist) {
          bestDist = dLeft
          bestScreen = cand
        }
      } else if (dir > 0 && mLeft >= curRight - 24) {
        var dRight = Math.abs(mLeft - curRight)
        if (dRight < bestDist) {
          bestDist = dRight
          bestScreen = cand
        }
      }
    }
    return bestScreen
  }

  // Click opens the DetailCard; leaving widget + card closes it after 280ms
  Timer {
    id: closeHoverTimer
    interval: 280
    onTriggered: {
      if (detailCard.editingNote) return
      if (!compactHover.hovered && !detailCard.pointerInside) {
        root.detailOpen = false
      }
    }
  }

  PanelWindow {
    id: overlayWin
    screen: root.targetScreen
    visible: root.active
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "houra-onscreen-widget"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: (root.detailOpen && detailCard.editingNote)
      ? WlrKeyboardFocus.OnDemand
      : WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    readonly property real sw: width > 0 ? width : (screen ? screen.width : 1920)
    readonly property real sh: height > 0 ? height : (screen ? screen.height : 1080)
    readonly property real topSafe: 36
    readonly property bool isEdgeStyle: root.styleName === "tag" || root.styleName === "strip"

    // Compact geometry computation per style
    readonly property real compactW: {
      if (root.nudgeShown) return 256
      if (root.styleName === "tag") return 216
      if (root.styleName === "strip") return 172
      if (root.styleName === "capsule") return 340
      if (root.styleName === "card") return 210
      if (root.styleName === "ring") return 80
      return 216
    }

    readonly property real compactH: {
      if (root.nudgeShown) return Math.max(124, nudgeCol.implicitHeight + 28)
      if (root.styleName === "tag") return 66
      if (root.styleName === "strip") return Math.max(200, sh - topSafe - 8)
      if (root.styleName === "capsule") return 62
      if (root.styleName === "card") return 208
      if (root.styleName === "ring") return 80
      return 66
    }

    readonly property real compactX: {
      if (root.dragging && root.styleName === "tag" && root.dragLiveX >= 0) {
        return Math.max(0, Math.min(sw - compactW, root.dragLiveX))
      }
      if (root.styleName === "tag" || root.styleName === "strip") {
        return root.onLeft ? 0 : (sw - compactW)
      }
      var defX = sw - compactW - 24
      var rawX = root.floatX >= 0 ? root.floatX : defX
      return Math.max(12, Math.min(sw - compactW - 12, rawX))
    }

    readonly property real compactY: {
      if (root.nudgeShown && root.styleName === "strip") {
        return Math.max(topSafe + 8, Math.round((sh - compactH) * 0.5))
      }
      if (root.styleName === "strip") return topSafe
      if (root.styleName === "tag") {
        if (root.dragging && root.dragLiveY >= 0) {
          return Math.max(topSafe + 8, Math.min(sh - compactH - 16, root.dragLiveY))
        }
        var ty = root.tagYRatio * sh
        return Math.max(topSafe + 8, Math.min(sh - compactH - 16, ty))
      }
      var defY = sh - compactH - 28
      var rawY = root.floatY >= 0 ? root.floatY : defY
      return Math.max(topSafe + 8, Math.min(sh - compactH - 12, rawY))
    }

    // Detail card placement next to compact widget; on narrow screens it goes above/below instead of covering it
    readonly property bool detailBeside: {
      if (root.styleName === "strip") return true
      var w = detailCard.width
      if (root.styleName === "tag") return sw - compactW - 20 >= w
      return compactX - 20 >= w || sw - compactX - compactW - 20 >= w
    }

    readonly property real detailX: {
      var w = detailCard.width
      if (root.styleName === "strip") {
        return root.onLeft ? 0 : (sw - w)
      }
      if (!detailBeside) {
        return Math.max(12, Math.min(sw - w - 12, compactX + compactW / 2 - w / 2))
      }
      if (root.styleName === "tag") {
        return root.onLeft ? (compactW + 8) : (sw - compactW - w - 8)
      }
      // Floating views: open inward toward screen center, or the other side when that one is too tight
      var leftX = compactX - w - 8
      var rightX = compactX + compactW + 8
      if ((compactX + compactW / 2) > (sw / 2)) return leftX >= 12 ? leftX : rightX
      return rightX + w <= sw - 12 ? rightX : leftX
    }

    readonly property real detailY: {
      if (root.styleName === "strip") return topSafe
      if (!detailBeside) {
        var above = compactY - detailCard.height - 8
        if (above >= topSafe + 8) return above
        return Math.max(topSafe + 8, Math.min(compactY + compactH + 8, sh - detailCard.height - 12))
      }
      var cand = compactY
      if (cand + detailCard.height > sh - 12) {
        cand = Math.max(topSafe + 8, sh - detailCard.height - 12)
      }
      return cand
    }

    // Primary mask rect: for Thin Strip, ONLY mask the 10px edge strip bar (rider pill gets its own Region below!)
    readonly property real primaryMaskX: {
      if (!root.nudgeShown && root.styleName === "strip") {
        return root.onLeft ? 0 : (sw - 10)
      }
      return compactBox.x
    }
    readonly property real primaryMaskY: compactBox.y
    readonly property real primaryMaskW: {
      if (!root.nudgeShown && root.styleName === "strip") return 10
      return compactBox.width
    }
    readonly property real primaryMaskH: compactBox.height

    mask: Region {
      Region {
        x: root.dragging ? 0 : Math.floor(overlayWin.primaryMaskX)
        y: root.dragging ? 0 : Math.floor(overlayWin.primaryMaskY)
        width: root.dragging ? Math.ceil(overlayWin.sw) : Math.ceil(overlayWin.primaryMaskW)
        height: root.dragging ? Math.ceil(overlayWin.sh) : Math.ceil(overlayWin.primaryMaskH)
      }
      Region {
        x: (!root.dragging && !root.nudgeShown && root.styleName === "strip" && !root.detailOpen)
          ? Math.floor(compactBox.x + stripRiderPill.x)
          : 0
        y: (!root.dragging && !root.nudgeShown && root.styleName === "strip" && !root.detailOpen)
          ? Math.floor(compactBox.y + stripRiderPill.y)
          : 0
        width: (!root.dragging && !root.nudgeShown && root.styleName === "strip" && !root.detailOpen)
          ? Math.ceil(stripRiderPill.width)
          : 0
        height: (!root.dragging && !root.nudgeShown && root.styleName === "strip" && !root.detailOpen)
          ? Math.ceil(stripRiderPill.height)
          : 0
      }
      Region {
        x: (!root.dragging && root.detailOpen && !root.nudgeShown) ? Math.floor(detailCard.x) : 0
        y: (!root.dragging && root.detailOpen && !root.nudgeShown) ? Math.floor(detailCard.y) : 0
        width: (!root.dragging && root.detailOpen && !root.nudgeShown) ? Math.ceil(detailCard.width) : 0
        height: (!root.dragging && root.detailOpen && !root.nudgeShown) ? Math.ceil(detailCard.height) : 0
      }
    }

    // --- COMPACT WIDGET CONTAINER ---
    Item {
      id: compactBox
      x: overlayWin.compactX
      y: overlayWin.compactY
      width: overlayWin.compactW
      height: overlayWin.compactH
      HoverHandler {
        id: compactHover
        onHoveredChanged: {
          if (hovered) closeHoverTimer.stop()
          else closeHoverTimer.restart()
        }
      }

      // Shared drag/click MouseArea (disabled during break nudge)
      MouseArea {
        id: dragArea
        anchors.fill: parent
        enabled: !root.nudgeShown
        cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor

        property real pressScreenX: 0
        property real pressScreenY: 0
        property real lastScreenX: 0
        property real lastScreenY: 0
        property real startFloatX: 0
        property real startFloatY: 0
        property bool movedEnough: false

        onPressed: function(mouse) {
          var gp = compactBox.mapToItem(overlayWin.contentItem, mouse.x, mouse.y)
          pressScreenX = gp.x
          pressScreenY = gp.y
          lastScreenX = gp.x
          lastScreenY = gp.y
          startFloatX = compactBox.x
          startFloatY = compactBox.y
          root.dragLiveX = compactBox.x
          root.dragLiveY = compactBox.y
          movedEnough = false
        }

        onPositionChanged: function(mouse) {
          if (!pressed) return
          var gp = compactBox.mapToItem(overlayWin.contentItem, mouse.x, mouse.y)
          lastScreenX = gp.x
          lastScreenY = gp.y
          var dx = gp.x - pressScreenX
          var dy = gp.y - pressScreenY
          if (!movedEnough && (Math.abs(dx) > 5 || Math.abs(dy) > 5)) {
            movedEnough = true
            root.dragging = true
            root.detailOpen = false
          }
          if (!movedEnough) return

          if (root.styleName === "tag") {
            root.dragLiveX = Math.max(0, Math.min(overlayWin.sw - compactBox.width, startFloatX + dx))
            var ny = Math.max(overlayWin.topSafe + 8, Math.min(overlayWin.sh - compactBox.height - 16, startFloatY + dy))
            root.dragLiveY = ny
            root.onLeft = gp.x < (overlayWin.sw * 0.5)
            root.tagYRatio = ny / Math.max(1, overlayWin.sh)
          } else if (root.styleName === "strip") {
            root.onLeft = gp.x < (overlayWin.sw * 0.5)
          } else {
            root.floatX = Math.max(0, Math.min(overlayWin.sw - compactBox.width, startFloatX + dx))
            root.floatY = Math.max(overlayWin.topSafe + 8, Math.min(overlayWin.sh - compactBox.height - 12, startFloatY + dy))
          }
        }

        onReleased: {
          if (root.dragging) {
            root.dragging = false
            root.dragLiveX = -1
            root.dragLiveY = -1

            // Cross-monitor edge transfer when dragged right up to a shared display border
            var nextScreenName = ""
            var edgeCrossDir = 0
            if (lastScreenX <= 10 || (root.floatX >= 0 && root.floatX <= 4 && !overlayWin.isEdgeStyle)) {
              edgeCrossDir = -1
            } else if (lastScreenX >= overlayWin.sw - 10 || (root.floatX >= 0 && root.floatX >= overlayWin.sw - compactBox.width - 4 && !overlayWin.isEdgeStyle)) {
              edgeCrossDir = 1
            }

            if (edgeCrossDir !== 0) {
              var adj = root._findAdjacentScreen(edgeCrossDir)
              if (adj && adj.name) {
                nextScreenName = String(adj.name)
                var adjW = adj.width > 0 ? adj.width : overlayWin.sw
                var adjH = adj.height > 0 ? adj.height : overlayWin.sh
                var yRatio = Math.max(0.06, Math.min(0.88, lastScreenY / Math.max(1, overlayWin.sh)))
                if (overlayWin.isEdgeStyle) {
                  // Entering left monitor from right -> snap to its right edge; entering right monitor -> snap to its left edge
                  root.onLeft = (edgeCrossDir > 0)
                  root.tagYRatio = yRatio
                } else {
                  root.floatX = edgeCrossDir < 0
                    ? Math.max(16, adjW - compactBox.width - 24)
                    : 24
                  root.floatY = Math.max(overlayWin.topSafe + 8, Math.min(adjH - compactBox.height - 16, Math.round(yRatio * adjH)))
                }
              }
            }

            if (!nextScreenName && !overlayWin.isEdgeStyle) {
              root.floatX = Math.max(12, Math.min(overlayWin.sw - compactBox.width - 12, root.floatX))
            }

            if (root.service) {
              if (overlayWin.isEdgeStyle) {
                root.service.saveWidgetPlacement(root.onLeft, root.tagYRatio, "", -1, -1, nextScreenName)
              } else {
                root.service.saveWidgetPlacement(root.onLeft, root.tagYRatio, root.styleName, root.floatX, root.floatY, nextScreenName)
              }
            }
          } else if (!movedEnough && !root.nudgeShown) {
            root.detailOpen = !root.detailOpen
          }
        }

        onCanceled: {
          root.dragging = false
          root.dragLiveX = -1
          root.dragLiveY = -1
        }
      }

      // =====================================================================
      // 0. FREE-MODE 50-MINUTE BREAK NUDGE CARD (Widgets.swift:415-483)
      // =====================================================================
      Item {
        visible: root.nudgeShown
        anchors.fill: parent
        clip: true

        Rectangle {
          x: overlayWin.isEdgeStyle ? (root.onLeft ? -16 : 0) : 0
          y: 0
          width: overlayWin.isEdgeStyle ? (parent.width + 16) : parent.width
          height: parent.height
          radius: 16
          color: root.tokens.popup || "#141418"
          border.width: 1
          border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.22)
        }

        Column {
          id: nudgeCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: 14
          anchors.rightMargin: 14
          spacing: 8

          Item {
            width: parent.width
            height: 18

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6

              CategorySwatch {
                anchors.verticalCenter: parent.verticalCenter
                swatchSize: 10
                swatchColor: root.catColor
                emoji: root.activeCat ? (root.activeCat.emoji || "") : ""
                iconName: root.activeCat ? (root.activeCat.icon || "") : ""
                iconColor: root.activeCat ? (root.activeCat.iconColor || "") : ""
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: (root.activeCat ? root.activeCat.name : "").toUpperCase()
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 1.0
                color: root.tokens.muted || "#888888"
              }
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.service ? root.service.clockText : "50:00"
              font.family: "Monospace"
              font.pixelSize: 13
              font.weight: Font.Light
              color: root.tokens.secondary || "#bbbbbb"
            }
          }

          Column {
            width: parent.width
            spacing: 2

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: {
                var mins = root.service ? Math.max(50, Math.floor(root.service.elapsedSeconds / 60)) : 50
                return Theme.t(root.lang, mins + " dakikadır çalışıyorsun", mins + " minutes in")
              }
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: Theme.t(root.lang, "Mola isteğe bağlı.", "The break is optional.")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }
          }

          Row {
            width: parent.width
            spacing: 8

            Rectangle {
              width: (parent.width - 8) / 2
              height: 30
              radius: 8
              color: keepArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.12)

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Devam et", "Keep going")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: keepArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.dismissBreakNudge()
              }
            }

            Rectangle {
              width: (parent.width - 8) / 2
              height: 30
              radius: 8
              color: takeArea.containsMouse
                ? Theme.withAlpha(root.accentInk, 0.88)
                : root.accentInk

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Mola ver", "Take a break")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.tokens.primaryInk || "#000000"
              }

              MouseArea {
                id: takeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.finishSession()
              }
            }
          }
        }
      }

      // =====================================================================
      // 1. TAG VIEW (3-column edge tab, rounded inner corners, flat screen edge)
      // =====================================================================
      Item {
        visible: !root.nudgeShown && root.styleName === "tag"
        anchors.fill: parent
        clip: true

        Rectangle {
          x: root.dragging ? 0 : (root.onLeft ? -18 : 0)
          y: 0
          width: root.dragging ? parent.width : (parent.width + 18)
          height: parent.height
          radius: 18
          color: root.tokens.popup || "#131317"
          border.width: 1
          border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)
        }

        // Inner-edge grip pill (Widgets.swift:380: 3x26)
        Rectangle {
          x: root.onLeft ? (parent.width - 10) : 7
          anchors.verticalCenter: parent.verticalCenter
          width: 3
          height: 26
          radius: 1.5
          color: Qt.rgba(1, 1, 1, 0.16)
        }

        // Middle column (category eyebrow + headline) + Right hero clock
        Item {
          anchors.left: parent.left
          anchors.leftMargin: root.onLeft ? 12 : 18
          anchors.right: parent.right
          anchors.rightMargin: root.onLeft ? 18 : 12
          anchors.top: parent.top
          anchors.bottom: parent.bottom

          Column {
            anchors.left: parent.left
            anchors.right: tagClockTxt.left
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Row {
              spacing: 5

              CategorySwatch {
                anchors.verticalCenter: parent.verticalCenter
                swatchSize: 10
                swatchColor: root.catColor
                emoji: root.activeCat ? (root.activeCat.emoji || "") : ""
                iconName: root.activeCat ? (root.activeCat.icon || "") : ""
                iconColor: root.activeCat ? (root.activeCat.iconColor || "") : ""
              }

              Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                text: (root.activeCat ? root.activeCat.name : "").toUpperCase()
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.DemiBold
                font.letterSpacing: 1.0
                color: root.tokens.muted || "#888888"
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.headline
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }
          }

          Text {
            textFormat: Text.PlainText
            id: tagClockTxt
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.service ? root.service.clockText : "00:00"
            font.family: "Monospace"
            font.pixelSize: 22
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }
        }

        // Bottom 2px progress line (inset past 18px rounded inner corner so pixels never spill)
        Rectangle {
          anchors.left: parent.left
          anchors.leftMargin: root.onLeft ? 0 : 18
          anchors.right: parent.right
          anchors.rightMargin: root.onLeft ? 18 : 0
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 1.5
          height: 2
          radius: 1
          color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.08)

          Rectangle {
            visible: (root.service ? root.service.progress : 0) > 0.003
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.max(3, Math.min(parent.width, parent.width * (root.service ? root.service.progress : 0)))
            radius: 1
            color: root.accentInk
          }
        }
      }

      // =====================================================================
      // 2. THIN STRIP VIEW (Full-height 5px edge bar + 2-line rider pill)
      // =====================================================================
      Item {
        id: stripView
        visible: !root.nudgeShown && root.styleName === "strip"
        anchors.fill: parent

        readonly property real prog: root.service ? root.service.progress : 0.0
        readonly property real fillH: Math.max(4, height * prog)

        Rectangle {
          x: root.onLeft ? 0 : (parent.width - 5)
          y: 0
          width: 5
          height: parent.height
          radius: 2.5
          color: Theme.withAlpha(root.tokens.ink || "#ffffff", 0.08)

          Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: stripView.fillH
            radius: 2.5
            color: root.accentInk
          }
        }

        // Floating 2-line rider pill tracking the top of the progress fill (Widgets.swift:566-592)
        Rectangle {
          id: stripRiderPill
          opacity: root.detailOpen ? 0.0 : 1.0
          x: root.onLeft ? 14 : (parent.width - width - 14)
          y: Math.max(10, Math.min(parent.height - height - 10, parent.height - stripView.fillH - height * 0.5))
          width: Math.min(148, Math.max(stripClockTxt.implicitWidth, stripHeadTxt.implicitWidth) + 20)
          height: stripPillCol.implicitHeight + 12
          radius: 10
          color: root.tokens.popup || "#131317"
          border.width: 1
          border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

          Behavior on opacity { NumberAnimation { duration: 140 } }

          Column {
            id: stripPillCol
            anchors.centerIn: parent
            width: parent.width - 18
            spacing: 1

            Text {
              textFormat: Text.PlainText
              id: stripClockTxt
              width: parent.width
              horizontalAlignment: root.onLeft ? Text.AlignLeft : Text.AlignRight
              text: root.service ? root.service.clockText : "00:00"
              font.family: "Monospace"
              font.pixelSize: 14
              font.weight: Font.Normal
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              id: stripHeadTxt
              width: parent.width
              horizontalAlignment: root.onLeft ? Text.AlignLeft : Text.AlignRight
              text: root.headline
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.muted || "#888888"
            }
          }
        }
      }

      // =====================================================================
      // 3. CAPSULE VIEW (Floating 340x62 pill with circular progress pause/play button)
      // =====================================================================
      Rectangle {
        visible: !root.nudgeShown && root.styleName === "capsule"
        anchors.fill: parent
        radius: 31
        color: root.tokens.popup || "#131317"
        border.width: 1
        border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

        Row {
          anchors.fill: parent
          anchors.leftMargin: 18
          anchors.rightMargin: 10
          spacing: 10

          Column {
            width: parent.width - 144
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: root.headline
              elide: Text.ElideRight
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }

            Row {
              width: parent.width
              spacing: 6

              CategorySwatch {
                anchors.verticalCenter: parent.verticalCenter
                swatchSize: 10
                swatchColor: root.catColor
                emoji: root.activeCat ? (root.activeCat.emoji || "") : ""
                iconName: root.activeCat ? (root.activeCat.icon || "") : ""
                iconColor: root.activeCat ? (root.activeCat.iconColor || "") : ""
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width - 16
                anchors.verticalCenter: parent.verticalCenter
                text: root.capsuleSubtitle
                elide: Text.ElideRight
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.tokens.muted || "#888888"
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: 68
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
            text: root.service ? root.service.clockText : "00:00"
            font.family: "Monospace"
            font.pixelSize: 21
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }

          // Circular progress-ring Pause/Play button (46x46, Widgets.swift:525-549)
          Item {
            width: 46
            height: 46
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              anchors.centerIn: parent
              width: 38
              height: 38
              radius: 19
              color: capPauseArea.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.07)
            }

            Canvas {
              id: capRingCanvas
              anchors.fill: parent
              property real prog: root.service ? root.service.progress : 0
              property string ringCol: root.accentInk
              property bool isPaused: !!root.service && root.service.phase === "paused"
              property string iconCol: String(root.tokens.ink || "#ffffff")
              onProgChanged: requestPaint()
              onRingColChanged: requestPaint()
              onIsPausedChanged: requestPaint()
              onIconColChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2
                var cy = height / 2
                var r = 20
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.strokeStyle = "rgba(255,255,255,0.12)"
                ctx.lineWidth = 2
                ctx.stroke()

                if (prog > 0.002) {
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * prog)
                  ctx.strokeStyle = ringCol
                  ctx.lineWidth = 2
                  ctx.lineCap = "round"
                  ctx.stroke()
                }

                // Vector Play triangle or Pause bars
                ctx.fillStyle = iconCol
                if (isPaused) {
                  ctx.beginPath()
                  ctx.moveTo(cx - 3.5, cy - 5.5)
                  ctx.lineTo(cx + 5.5, cy)
                  ctx.lineTo(cx - 3.5, cy + 5.5)
                  ctx.closePath()
                  ctx.fill()
                } else {
                  ctx.fillRect(cx - 4.5, cy - 5, 2.8, 10)
                  ctx.fillRect(cx + 1.7, cy - 5, 2.8, 10)
                }
              }
            }

            MouseArea {
              id: capPauseArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.service) root.service.togglePause()
            }
          }
        }
      }

      // =====================================================================
      // 4. CARD VIEW (Floating 210x208 rounded card with 148px ring + headline)
      // =====================================================================
      Rectangle {
        visible: !root.nudgeShown && root.styleName === "card"
        anchors.fill: parent
        radius: 26
        color: root.tokens.popup || "#131317"
        border.width: 1
        border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

        Column {
          anchors.centerIn: parent
          width: parent.width - 24
          spacing: 10

          Item {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 148
            height: 148

            Canvas {
              anchors.fill: parent
              property real prog: root.service ? root.service.progress : 0
              property string ringCol: root.accentInk
              onProgChanged: requestPaint()
              onRingColChanged: requestPaint()

              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var cx = width / 2
                var cy = height / 2
                var r = 66
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, Math.PI * 2)
                ctx.strokeStyle = "rgba(255,255,255,0.09)"
                ctx.lineWidth = 5
                ctx.stroke()

                if (prog > 0.002) {
                  ctx.beginPath()
                  ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * prog)
                  ctx.strokeStyle = ringCol
                  ctx.lineWidth = 5
                  ctx.lineCap = "round"
                  ctx.stroke()
                }
              }
            }

            Column {
              anchors.centerIn: parent
              spacing: 2

              Text {
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.service ? root.service.clockText : "00:00"
                font.family: "Monospace"
                font.pixelSize: 32
                font.weight: Font.ExtraLight
                color: root.tokens.ink || "#ffffff"
              }

              Text {
                textFormat: Text.PlainText
                visible: !!root.service && root.service.phase === "paused"
                anchors.horizontalCenter: parent.horizontalCenter
                text: Theme.t(root.lang, "DURAKLATILDI", "PAUSED")
                font.family: root.fontFamily
                font.pixelSize: 9
                font.weight: Font.Bold
                font.letterSpacing: 0.9
                color: root.tokens.muted || "#888888"
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: root.headline
            elide: Text.ElideRight
            font.family: root.fontFamily
            font.pixelSize: 13
            font.weight: Font.Medium
            color: root.tokens.ink || "#ffffff"
          }
        }
      }

      // =====================================================================
      // 5. RING VIEW (Compact 80x80 floating circular progress badge)
      // =====================================================================
      Rectangle {
        visible: !root.nudgeShown && root.styleName === "ring"
        anchors.fill: parent
        radius: 40
        color: root.tokens.popup || "#131317"
        border.width: 1
        border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

        Canvas {
          anchors.fill: parent
          property real prog: root.service ? root.service.progress : 0
          property string ringCol: root.accentInk
          onProgChanged: requestPaint()
          onRingColChanged: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2
            var cy = height / 2
            var r = 33.5
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.strokeStyle = "rgba(255,255,255,0.10)"
            ctx.lineWidth = 3
            ctx.stroke()

            if (prog > 0.002) {
              ctx.beginPath()
              ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * prog)
              ctx.strokeStyle = ringCol
              ctx.lineWidth = 3
              ctx.lineCap = "round"
              ctx.stroke()
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.service ? root.service.clockText : "00:00"
          font.family: "Monospace"
          font.pixelSize: 14
          font.weight: Font.Medium
          color: root.tokens.ink || "#ffffff"
        }
      }
    }

    // --- SLIDE-OUT DETAIL PANEL ---
    DetailCard {
      id: detailCard
      visible: root.detailOpen && !root.nudgeShown
      x: overlayWin.detailX
      y: overlayWin.detailY
      maxCardHeight: Math.min(640, Math.max(360, overlayWin.sh - overlayWin.topSafe - 16))
      drawerMode: root.styleName === "strip"
      service: root.service
      tokens: root.tokens
      lang: root.lang
      fontFamily: root.fontFamily

      onPointerInsideChanged: {
        if (pointerInside) closeHoverTimer.stop()
        else closeHoverTimer.restart()
      }

      onEditingNoteChanged: {
        if (!editingNote && !compactHover.hovered && !pointerInside) {
          closeHoverTimer.restart()
        }
      }
    }
  }
}
