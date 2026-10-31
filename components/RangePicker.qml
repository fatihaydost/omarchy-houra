import QtQuick
import "../Theme.js" as Theme

// Custom date range picker popover for Statistics (Last 7 / 30 / 90 days + From / To calendars + span readout).
Rectangle {
  id: root

  property bool open: false
  property string rangeStart: ""
  property string rangeEnd: ""
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"

  signal applyRange(string startIso, string endIso)

  visible: open
  width: 332
  height: col.implicitHeight + 28
  radius: 12
  color: root.tokens.popup || "#141418"
  border.width: 1
  border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.18)
  z: 40

  property string draftStart: ""
  property string draftEnd: ""
  property string pickingSide: "start" // "start" | "end"
  property int calYear: 2026
  property int calMonth: 10 // 1..12

  readonly property int draftSpanDays: {
    if (!draftStart || !draftEnd) return 1
    var d1 = Theme.parseIsoDay(draftStart)
    var d2 = Theme.parseIsoDay(draftEnd)
    return Math.max(1, Math.round((d2.getTime() - d1.getTime()) / 86400000) + 1)
  }

  onOpenChanged: {
    if (open) {
      draftStart = rangeStart || Theme.toIsoDay(new Date())
      draftEnd = rangeEnd || draftStart
      var d = Theme.parseIsoDay(draftStart)
      calYear = d.getFullYear()
      calMonth = d.getMonth() + 1
      pickingSide = "start"
    }
  }

  readonly property var monthCells: {
    var first = new Date(calYear, calMonth - 1, 1)
    var isoDow = first.getDay() === 0 ? 7 : first.getDay() // 1=Mon..7=Sun
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

  function selectPreset(daysCount) {
    var endIso = Theme.toIsoDay(new Date())
    var startIso = Theme.addDaysIso(endIso, -(daysCount - 1))
    root.open = false
    root.applyRange(startIso, endIso)
  }

  function stepMonth(delta) {
    var m = calMonth + delta
    var y = calYear
    if (m < 1) { m = 12; y-- }
    if (m > 12) { m = 1; y++ }
    calYear = y
    calMonth = m
  }

  function applyCurrent() {
    if (!draftStart || !draftEnd) return
    root.open = false
    root.applyRange(draftStart, draftEnd)
  }

  function _nudgeSelectedDay(step) {
    if (pickingSide === "start") {
      draftStart = Theme.addDaysIso(draftStart, step)
      if (draftEnd < draftStart) draftEnd = draftStart
      var ds = Theme.parseIsoDay(draftStart)
      calYear = ds.getFullYear()
      calMonth = ds.getMonth() + 1
    } else {
      draftEnd = Theme.addDaysIso(draftEnd, step)
      if (draftEnd < draftStart) draftStart = draftEnd
      var de = Theme.parseIsoDay(draftEnd)
      calYear = de.getFullYear()
      calMonth = de.getMonth() + 1
    }
  }

  function handleKey(event) {
    if (!open) return false
    var k = event.key
    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      pickingSide = (pickingSide === "start") ? "end" : "start"
      var targetVal = (pickingSide === "start") ? draftStart : draftEnd
      if (targetVal) {
        var d = Theme.parseIsoDay(targetVal)
        calYear = d.getFullYear()
        calMonth = d.getMonth() + 1
      }
      return true
    }
    if (k === Qt.Key_Left) { _nudgeSelectedDay(-1); return true }
    if (k === Qt.Key_Right) { _nudgeSelectedDay(1); return true }
    if (k === Qt.Key_Up) { _nudgeSelectedDay(-7); return true }
    if (k === Qt.Key_Down) { _nudgeSelectedDay(7); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      applyCurrent()
      return true
    }
    return false
  }

  MouseArea {
    anchors.fill: parent
    onClicked: function(mouse) { mouse.accepted = true }
  }

  Column {
    id: col
    anchors.fill: parent
    anchors.margins: 14
    spacing: 10

    // Presets: Last 7 / 30 / 90 days
    Row {
      width: parent.width
      spacing: 6

      Repeater {
        model: [
          { days: 7, label: Theme.t(root.lang, "Son 7 gün", "Last 7 days") },
          { days: 30, label: Theme.t(root.lang, "Son 30 gün", "Last 30 days") },
          { days: 90, label: Theme.t(root.lang, "Son 90 gün", "Last 90 days") }
        ]
        delegate: Rectangle {
          width: (col.width - 12) / 3
          height: 26
          radius: 6
          color: presetArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: modelData.label
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.ink || "#ffffff"
          }

          MouseArea {
            id: presetArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectPreset(modelData.days)
          }
        }
      }
    }

    // From / To selector pills
    Row {
      width: parent.width
      spacing: 8

      Repeater {
        model: [
          { side: "start", title: Theme.t(root.lang, "Başlangıç", "From"), val: root.draftStart },
          { side: "end", title: Theme.t(root.lang, "Bitiş", "To"), val: root.draftEnd }
        ]
        delegate: Rectangle {
          readonly property bool active: root.pickingSide === modelData.side
          width: (col.width - 8) / 2
          height: 36
          radius: 7
          color: active ? (root.tokens.raised || "#2a2a32") : (root.tokens.card2 || "#1d1d22")
          border.width: 1
          border.color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.1))

          Column {
            anchors.centerIn: parent
            spacing: 1

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: modelData.title
              font.family: root.fontFamily
              font.pixelSize: 9
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              anchors.horizontalCenter: parent.horizontalCenter
              text: Theme.formatShortDay(modelData.val, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.pickingSide = modelData.side
              var d = Theme.parseIsoDay(modelData.val)
              root.calYear = d.getFullYear()
              root.calMonth = d.getMonth() + 1
            }
          }
        }
      }
    }

    // Calendar month nav
    Item {
      width: parent.width
      height: 24

      Rectangle {
        anchors.left: parent.left
        width: 24
        height: 24
        radius: 6
        color: root.tokens.card2 || "#1f1f25"
        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "‹"; font.pixelSize: 14; color: root.tokens.ink || "#ffffff" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepMonth(-1) }
      }

      Text {
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: Theme.monthFull(root.calMonth, root.lang) + " " + root.calYear
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.tokens.ink || "#ffffff"
      }

      Rectangle {
        anchors.right: parent.right
        width: 24
        height: 24
        radius: 6
        color: root.tokens.card2 || "#1f1f25"
        Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "›"; font.pixelSize: 14; color: root.tokens.ink || "#ffffff" }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepMonth(1) }
      }
    }

    // Weekday headers + day cells
    Grid {
      width: parent.width
      columns: 7
      spacing: 3

      Repeater {
        model: [1, 2, 3, 4, 5, 6, 7]
        delegate: Text {
          textFormat: Text.PlainText
          width: (col.width - 18) / 7
          horizontalAlignment: Text.AlignHCenter
          text: Theme.weekdayShort(modelData, root.lang)
          font.family: root.fontFamily
          font.pixelSize: 10
          color: root.tokens.muted || "#777777"
        }
      }

      Repeater {
        model: root.monthCells.length
        delegate: Rectangle {
          readonly property var cell: root.monthCells[index]
          readonly property bool isEndpoint: cell.iso !== "" && (cell.iso === root.draftStart || cell.iso === root.draftEnd)
          readonly property bool inSpan: cell.iso !== "" && cell.iso >= root.draftStart && cell.iso <= root.draftEnd
          width: (col.width - 18) / 7
          height: 26
          radius: 6
          color: cell.day === 0
            ? "transparent"
            : (isEndpoint
                ? (root.tokens.primaryBg || "#ffffff")
                : (inSpan ? (root.tokens.raised || "#2a2a32") : "transparent"))

          Text {
            textFormat: Text.PlainText
            visible: cell.day > 0
            anchors.centerIn: parent
            text: String(cell.day)
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: parent.isEndpoint ? Font.Bold : Font.Normal
            color: parent.isEndpoint ? (root.tokens.primaryInk || "#000000") : (root.tokens.ink || "#ffffff")
          }

          MouseArea {
            enabled: cell.day > 0
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              if (root.pickingSide === "start") {
                root.draftStart = cell.iso
                if (root.draftEnd < root.draftStart) root.draftEnd = root.draftStart
                root.pickingSide = "end"
              } else {
                root.draftEnd = cell.iso
                if (root.draftEnd < root.draftStart) root.draftStart = root.draftEnd
              }
            }
          }
        }
      }
    }

    // Span day count + Cancel / Apply
    Item {
      width: parent.width
      height: 28

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.draftSpanDays + " " + Theme.t(root.lang, "gün seçili", "days selected")
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.muted || "#888888"
      }

      Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
          width: 72
          height: 28
          radius: 7
          color: root.tokens.card2 || "#1f1f25"
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: Theme.t(root.lang, "İptal", "Cancel")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.secondary || "#aaaaaa"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open = false
          }
        }

        Rectangle {
          width: 82
          height: 28
          radius: 7
          color: root.tokens.primaryBg || "#ffffff"
          Text {
            textFormat: Text.PlainText
            anchors.centerIn: parent
            text: Theme.t(root.lang, "Uygula", "Apply")
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: Font.DemiBold
            color: root.tokens.primaryInk || "#000000"
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.open = false
              root.applyRange(root.draftStart, root.draftEnd)
            }
          }
        }
      }
    }
  }
}
