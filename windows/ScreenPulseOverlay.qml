import QtQuick
import Quickshell
import Quickshell.Wayland

// Multi-monitor click-through screen pulse matching Widgets.swift:256-277:
// 3 equal 0.3s autoreversing pulses (1.8s total) with 22% white fill + 90% 8px border.
Item {
  id: root

  property bool active: false
  property real pulseAlpha: 0.0

  function flash() {
    pulseAnim.stop()
    active = true
    pulseAnim.start()
  }

  SequentialAnimation {
    id: pulseAnim
    loops: 1
    NumberAnimation { target: root; property: "pulseAlpha"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseAlpha"; from: 1.0; to: 0.0; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseAlpha"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseAlpha"; from: 1.0; to: 0.0; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseAlpha"; from: 0.0; to: 1.0; duration: 300; easing.type: Easing.InOutSine }
    NumberAnimation { target: root; property: "pulseAlpha"; from: 1.0; to: 0.0; duration: 300; easing.type: Easing.InOutSine }
    ScriptAction { script: root.active = false }
  }

  Variants {
    model: root.active ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData
        screen: modelData
        visible: root.active
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "houra-screen-pulse"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        mask: Region {}

        Rectangle {
          anchors.fill: parent
          color: Qt.rgba(1, 1, 1, 0.22 * root.pulseAlpha)
          border.width: 8
          border.color: Qt.rgba(1, 1, 1, 0.90 * root.pulseAlpha)
        }
      }
    }
  }
}
