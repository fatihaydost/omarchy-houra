import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../Theme.js" as Theme

// Full-screen multi-monitor break overlay matching RestOverlay.swift:
// - Blanks ALL monitors in pure black with slow sinusoidal DriftingLights + radial vignette
// - Active monitor grabs exclusive keyboard focus and shows monumental BREAK copy, giant MM:SS,
//   and the 1.5-second continuous press-and-hold Emergency button with smooth drain on early release.
Item {
  id: root

  property var service: null
  property bool active: false
  property string lang: service ? service.lang : "en"
  property string fontFamily: "Sans Serif"

  property real animTime: 0.0
  property real holdProgress: 0.0
  property bool holding: false
  property bool showHoldHint: false
  property string lockedPrimaryName: ""
  property real revealOpacity: 0.0

  function _resolveBreakScreenName() {
    var m = Hyprland.focusedMonitor
    if (m && m.name) return String(m.name)
    if (service && service.resolvedWidgetScreenName) return String(service.resolvedWidgetScreenName)
    return Quickshell.screens.length > 0 ? String(Quickshell.screens[0].name) : ""
  }

  Timer {
    interval: 50
    running: root.active
    repeat: true
    onTriggered: root.animTime += 0.05
  }

  onActiveChanged: {
    if (active) {
      lockedPrimaryName = _resolveBreakScreenName()
      revealOpacity = 0.0
      revealAnim.restart()
    } else {
      revealAnim.stop()
      revealOpacity = 0.0
    }
    holdTimer.stop()
    drainAnim.stop()
    holding = false
    holdProgress = 0.0
    showHoldHint = false
  }

  NumberAnimation {
    id: revealAnim
    target: root
    property: "revealOpacity"
    from: 0.0
    to: 1.0
    duration: 520
    easing.type: Easing.OutCubic
  }

  NumberAnimation {
    id: drainAnim
    target: root
    property: "holdProgress"
    to: 0.0
    duration: 200
    easing.type: Easing.OutQuad
  }

  Timer {
    id: holdTimer
    interval: 25
    repeat: true
    onTriggered: {
      root.holdProgress = Math.min(1.0, root.holdProgress + (25.0 / 1500.0))
      if (root.holdProgress >= 1.0) {
        holdTimer.stop()
        root.holding = false
        root.holdProgress = 0.0
        if (root.service) root.service.emergencyExit()
      }
    }
  }

  Timer {
    id: hintHideTimer
    interval: 1800
    onTriggered: root.showHoldHint = false
  }

  Variants {
    model: root.active ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        id: breakWin
        required property var modelData
        readonly property bool isPrimary: String(modelData.name) === root.lockedPrimaryName || Quickshell.screens.length === 1

        screen: modelData
        visible: root.active
        color: "#000000"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "houra-break-overlay"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: isPrimary ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        // Drifting radial lights + outer radial vignette (RestOverlay.swift:126-163)
        Canvas {
          id: lightsCanvas
          anchors.fill: parent
          opacity: root.revealOpacity
          property real t: root.animTime
          onTChanged: requestPaint()

          onPaint: {
            var ctx = getContext("2d")
            var w = width
            var h = height
            if (w <= 0 || h <= 0) return

            ctx.fillStyle = "#000000"
            ctx.fillRect(0, 0, w, h)

            var tt = t
            var maxDim = Math.max(w, h)
            var blobs = [
              {
                x: w * (0.30 + 0.22 * Math.sin(tt * 0.13)),
                y: h * (0.36 + 0.18 * Math.cos(tt * 0.09)),
                r: maxDim * (0.48 + 0.04 * Math.sin(tt * 0.15)),
                a: 0.085
              },
              {
                x: w * (0.72 + 0.20 * Math.cos(tt * 0.08 + 1.1)),
                y: h * (0.62 + 0.20 * Math.sin(tt * 0.11 + 0.4)),
                r: maxDim * (0.52 + 0.05 * Math.cos(tt * 0.12)),
                a: 0.068
              },
              {
                x: w * (0.48 + 0.24 * Math.sin(tt * 0.06 + 2.2)),
                y: h * (0.78 + 0.15 * Math.cos(tt * 0.10 + 1.5)),
                r: maxDim * (0.44 + 0.04 * Math.sin(tt * 0.09 + 0.8)),
                a: 0.055
              }
            ]

            for (var i = 0; i < blobs.length; i++) {
              var b = blobs[i]
              var grad = ctx.createRadialGradient(b.x, b.y, 0, b.x, b.y, b.r)
              grad.addColorStop(0.0, "rgba(255, 255, 255, " + b.a + ")")
              grad.addColorStop(0.55, "rgba(255, 255, 255, " + (b.a * 0.30) + ")")
              grad.addColorStop(1.0, "rgba(0, 0, 0, 0)")
              ctx.fillStyle = grad
              ctx.fillRect(0, 0, w, h)
            }

            // Outer radial black vignette matching RestOverlay.swift:156-163
            var vig = ctx.createRadialGradient(w * 0.5, h * 0.5, maxDim * 0.18, w * 0.5, h * 0.5, maxDim * 0.72)
            vig.addColorStop(0.0, "rgba(0, 0, 0, 0)")
            vig.addColorStop(1.0, "rgba(0, 0, 0, 0.58)")
            ctx.fillStyle = vig
            ctx.fillRect(0, 0, w, h)
          }
        }

        // Static grain dithers the dim 8-bit lights above so they don't band
        Image {
          anchors.fill: parent
          source: "grain.png"
          fillMode: Image.Tile
          smooth: false
          opacity: 0.045 * root.revealOpacity
        }

        // Absorb keys so typing doesn't leak while resting
        FocusScope {
          anchors.fill: parent
          focus: breakWin.isPrimary
          Keys.onPressed: function(event) {
            event.accepted = true
          }
        }

        // Center monumental break typography on primary monitor
        Column {
          visible: breakWin.isPrimary
          opacity: root.revealOpacity
          anchors.centerIn: parent
          width: Math.min(1100, parent.width - 80)
          spacing: 18

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: Theme.t(root.lang, "MOLA", "BREAK")
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            font.letterSpacing: 3.4
            color: Qt.rgba(1, 1, 1, 0.42)
          }

          Text {
            textFormat: Text.PlainText
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            // One line; shrinks to fit on narrow screens
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 28
            text: Theme.t(root.lang, "Kalk, biraz uzaklaş.", "Stand up, step away.")
            font.family: root.fontFamily
            font.pixelSize: 64
            font.weight: Font.ExtraLight
            color: "#ffffff"
          }

          Text {
            textFormat: Text.PlainText
            width: Math.min(560, parent.width)
            anchors.horizontalCenter: parent.horizontalCenter
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: Theme.t(
              root.lang,
              "Su iç, pencereden dışarı bak, birkaç adım at. Ekran seni bekler.",
              "Drink some water, look out the window, take a few steps. The screen will wait."
            )
            font.family: root.fontFamily
            font.pixelSize: 17
            color: Qt.rgba(1, 1, 1, 0.52)
          }

          Item { width: 1; height: 12 }

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.service ? root.service.restClockText : "05:00"
            font.family: "Monospace"
            font.pixelSize: 108
            font.weight: Font.Thin
            color: "#ffffff"
          }
        }

        // Bottom 1.5s press-and-hold Emergency button (RestOverlay.swift:166-247)
        Column {
          visible: breakWin.isPrimary
          opacity: root.revealOpacity
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: 56
          spacing: 10

          Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            opacity: root.showHoldHint || root.holding ? 1.0 : 0.0
            text: Theme.t(root.lang, "Erken çıkmak için 1.5 sn basılı tut", "Hold for 1.5s to exit early")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: Qt.rgba(1, 1, 1, 0.45)

            Behavior on opacity { NumberAnimation { duration: 160 } }
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.max(154, emText.implicitWidth + 46)
            height: 40
            radius: 20
            color: emArea.containsMouse && !root.holding ? Qt.rgba(1, 1, 1, 0.05) : "transparent"
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, root.holding ? 0.40 : (emArea.containsMouse ? 0.24 : 0.14))
            clip: true

            Behavior on border.color { ColorAnimation { duration: 160 } }

            // Pill-clipped linear hold progress fill (never spills past radius: 20)
            Canvas {
              anchors.fill: parent
              property real prog: root.holdProgress
              onProgChanged: requestPaint()
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                if (prog <= 0.002) return
                var r = height / 2
                ctx.beginPath()
                ctx.arc(r, r, r, Math.PI / 2, Math.PI * 1.5)
                ctx.lineTo(width - r, 0)
                ctx.arc(width - r, r, r, -Math.PI / 2, Math.PI / 2)
                ctx.closePath()
                ctx.clip()
                ctx.fillStyle = "rgba(255, 255, 255, 0.20)"
                ctx.fillRect(0, 0, width * prog, height)
              }
            }

            Text {
              textFormat: Text.PlainText
              id: emText
              anchors.centerIn: parent
              text: Theme.t(root.lang, "Acil durum", "Emergency")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: Qt.rgba(1, 1, 1, root.holding ? 0.92 : (emArea.containsMouse ? 0.72 : 0.48))

              Behavior on color { ColorAnimation { duration: 160 } }
            }

            MouseArea {
              id: emArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPressed: {
                drainAnim.stop()
                root.holding = true
                root.holdProgress = 0.0
                holdTimer.start()
              }
              onReleased: {
                if (holdTimer.running || root.holding) {
                  holdTimer.stop()
                  root.holding = false
                  if (root.holdProgress < 1.0) {
                    root.showHoldHint = true
                    hintHideTimer.restart()
                    drainAnim.start()
                  } else {
                    root.holdProgress = 0.0
                  }
                }
              }
              onCanceled: {
                holdTimer.stop()
                root.holding = false
                drainAnim.start()
              }
            }
          }
        }
      }
    }
  }
}
