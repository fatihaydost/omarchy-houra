import QtQuick
import QtQuick.Shapes
import "../Theme.js" as Theme
import "../IconData.js" as IconData

// Category appearance modal: Colour (15 swatches + custom hex), Emoji (single-emoji input + 52 grid),
// and Icon (100 Phosphor SVG icons with TR/EN search + full Icon colour palette + MIT attribution).
Item {
  id: root

  property bool open: false
  property var category: null
  property var tokens: ({})
  property string lang: "en"
  property string fontFamily: "Sans Serif"

  signal saveCategory(int catId, string color, string emoji, string iconName, string iconColor)
  signal closed()

  anchors.fill: parent
  visible: open
  z: 50

  property string selColor: "#4c8df0"
  property string selEmoji: ""
  property string selIcon: ""
  property string selIconColor: ""
  property string iconQuery: ""
  property string tabMode: "icon" // "icon" | "emoji"
  property string pickerFocus: "grid" // "tabs" | "search" | "grid" | "colors"
  property int gridCursor: 0
  property bool kbGridActive: false

  readonly property var filteredIcons: IconData.search(iconQuery)
  readonly property var iconColorPalette: ["#ffffff", "#000000"].concat(Theme.palette)
  readonly property bool isEditingText: hexInput.activeFocus || searchField.activeFocus || iconHexInput.activeFocus || emojiInput.activeFocus

  onFilteredIconsChanged: {
    var cnt = filteredIcons ? filteredIcons.length : 0
    if (gridCursor >= cnt) gridCursor = Math.max(0, cnt - 1)
  }

  function releaseTextFocus() {
    if (!isEditingText) return false
    hexInput.focus = false
    searchField.focus = false
    iconHexInput.focus = false
    emojiInput.focus = false
    return true
  }

  function ensureCellVisible(flick, cell) {
    if (!flick || !cell) return
    var pt = cell.mapToItem(flick.contentItem, 0, 0)
    var top = pt.y - 8
    var bot = pt.y + cell.height + 8
    if (top < flick.contentY) {
      flick.contentY = Math.max(0, top)
    } else if (bot > flick.contentY + flick.height) {
      flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), bot - flick.height)
    }
  }

  function pickAtCursor() {
    if (tabMode === "icon") {
      if (filteredIcons && gridCursor >= 0 && gridCursor < filteredIcons.length) {
        selIcon = filteredIcons[gridCursor].name
        selEmoji = ""
        emojiInput.text = ""
        commitNow()
      }
    } else {
      if (gridCursor >= 0 && gridCursor < Theme.emojis.length) {
        selEmoji = Theme.emojis[gridCursor]
        selIcon = ""
        emojiInput.text = selEmoji
        commitNow()
      }
    }
  }

  function _stepColor(delta) {
    var curIdx = -1
    for (var i = 0; i < Theme.palette.length; i++) {
      if (Theme.palette[i].toLowerCase() === selColor.toLowerCase()) { curIdx = i; break }
    }
    if (curIdx < 0) curIdx = 0
    var nextHex = Theme.palette[(curIdx + delta + Theme.palette.length) % Theme.palette.length]
    selColor = nextHex
    hexInput.text = nextHex
    commitNow()
  }

  function handleKey(event) {
    if (!open) return false
    var k = event.key
    var mods = event.modifiers

    if (k === Qt.Key_Tab || k === Qt.Key_Backtab) {
      var rev = (k === Qt.Key_Backtab || (mods & Qt.ShiftModifier))
      var stops = ["colors", "tabs"]
      if (tabMode === "icon") stops.push("search")
      stops.push("grid")
      var cur = pickerFocus
      if (searchField.activeFocus) cur = "search"
      var idx = stops.indexOf(cur)
      if (idx < 0) idx = 0
      var next = stops[(idx + (rev ? -1 : 1) + stops.length) % stops.length]
      pickerFocus = next
      if (next === "search") {
        searchField.forceActiveFocus()
      } else {
        releaseTextFocus()
        if (next === "grid") kbGridActive = true
      }
      return true
    }

    if (searchField.activeFocus) {
      var icCount = filteredIcons ? filteredIcons.length : 0
      var colsS = Math.max(1, Math.floor((iconGrid.width + 6) / 40))
      if (k === Qt.Key_Down) {
        kbGridActive = true
        if (icCount > 0) gridCursor = Math.min(icCount - 1, gridCursor + colsS)
        return true
      }
      if (k === Qt.Key_Up) {
        kbGridActive = true
        if (icCount > 0) gridCursor = Math.max(0, gridCursor - colsS)
        return true
      }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) {
        kbGridActive = true
        pickAtCursor()
        searchField.focus = false
        pickerFocus = "grid"
        return true
      }
      return false
    }
    if (isEditingText) return false

    if (pickerFocus === "colors") {
      if (k === Qt.Key_Left) { _stepColor(-1); return true }
      if (k === Qt.Key_Right) { _stepColor(1); return true }
      if (k === Qt.Key_Down) { pickerFocus = "grid"; kbGridActive = true; return true }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { closeModal(); return true }
      return false
    }

    if (pickerFocus === "tabs") {
      if (k === Qt.Key_Left || k === Qt.Key_Right || k === Qt.Key_Space) {
        tabMode = (tabMode === "icon") ? "emoji" : "icon"
        gridCursor = 0
        return true
      }
      if (k === Qt.Key_Down) { pickerFocus = "grid"; kbGridActive = true; return true }
      if (k === Qt.Key_Return || k === Qt.Key_Enter) { closeModal(); return true }
      return false
    }

    if (k === Qt.Key_Delete || k === Qt.Key_Backspace) {
      selIcon = ""
      selEmoji = ""
      emojiInput.text = ""
      commitNow()
      return true
    }

    var total = (tabMode === "icon")
      ? (filteredIcons ? filteredIcons.length : 0)
      : Theme.emojis.length
    var flowW = (tabMode === "icon") ? iconGrid.width : emojiFlow.width
    var cols = Math.max(1, Math.floor((flowW + 6) / 40))

    if (k === Qt.Key_Right) {
      if (total > 0) {
        gridCursor = kbGridActive ? Math.min(total - 1, gridCursor + 1) : 0
        kbGridActive = true
      }
      return true
    }
    if (k === Qt.Key_Left) {
      if (total > 0) {
        gridCursor = kbGridActive ? Math.max(0, gridCursor - 1) : 0
        kbGridActive = true
      }
      return true
    }
    if (k === Qt.Key_Down) {
      if (total > 0) {
        gridCursor = kbGridActive ? Math.min(total - 1, gridCursor + cols) : 0
        kbGridActive = true
      }
      return true
    }
    if (k === Qt.Key_Up) {
      if (total > 0) {
        gridCursor = kbGridActive ? Math.max(0, gridCursor - cols) : 0
        kbGridActive = true
      }
      return true
    }
    if (k === Qt.Key_Space) {
      kbGridActive = true
      pickAtCursor()
      return true
    }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      if (kbGridActive) pickAtCursor()
      closeModal()
      return true
    }
    return false
  }

  function _firstGrapheme(str) {
    var s = String(str || "").trim()
    if (!s) return ""
    var arr = Array.from(s)
    if (arr.length === 0) return ""
    // Keep ZWJ / variation selector sequence attached to the first base emoji if present
    var out = arr[0]
    var i = 1
    while (i < arr.length) {
      var cp = arr[i].codePointAt(0)
      if (cp === 0xFE0F || cp === 0xFE0E || (cp >= 0x1F3FB && cp <= 0x1F3FF)) {
        out += arr[i]
        i++
      } else if (cp === 0x200D && i + 1 < arr.length) {
        out += arr[i] + arr[i + 1]
        i += 2
      } else {
        break
      }
    }
    return out
  }

  function openFor(cat) {
    if (!cat) return
    category = cat
    selColor = cat.color || "#4c8df0"
    selEmoji = cat.emoji || ""
    selIcon = cat.icon || ""
    selIconColor = cat.iconColor || ""
    iconQuery = ""
    searchField.text = ""
    tabMode = (selEmoji !== "" && selIcon === "") ? "emoji" : "icon"
    hexInput.text = selColor
    iconHexInput.text = selIconColor || ""
    emojiInput.text = selEmoji
    gridCursor = 0
    kbGridActive = false
    open = true
  }

  function commitNow() {
    if (!category) return
    root.saveCategory(Number(category.id), selColor, selEmoji, selIcon, selIconColor)
  }

  function closeModal() {
    open = false
    root.closed()
  }

  Rectangle {
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.55)

    MouseArea {
      anchors.fill: parent
      onClicked: root.closeModal()
    }
  }

  Rectangle {
    id: dialog
    anchors.centerIn: parent
    width: Math.min(448, parent.width - 32)
    height: Math.min(578, parent.height - 28)
    radius: 14
    color: root.tokens.card || "#17171b"
    border.width: 1
    border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

    MouseArea {
      anchors.fill: parent
      onClicked: function(mouse) { mouse.accepted = true }
    }

    Column {
      anchors.fill: parent
      anchors.margins: 18
      spacing: 13

      // Header preview + Done
      Item {
        width: parent.width
        height: 36

        Row {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10

          CategorySwatch {
            swatchSize: 32
            swatchColor: root.selColor
            emoji: root.selEmoji
            iconName: root.selIcon
            iconColor: root.selIconColor
          }

          Text {
            textFormat: Text.PlainText
            anchors.verticalCenter: parent.verticalCenter
            text: root.category ? root.category.name : ""
            font.family: root.fontFamily
            font.pixelSize: 15
            font.weight: Font.DemiBold
            color: root.tokens.ink || "#ffffff"
          }
        }

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: doneLabel.implicitWidth + 20
          height: 28
          radius: 7
          color: root.tokens.primaryBg || "#ffffff"

          Text {
            textFormat: Text.PlainText
            id: doneLabel
            anchors.centerIn: parent
            text: Theme.t(root.lang, "Tamam", "Done")
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.tokens.primaryInk || "#000000"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeModal()
          }
        }
      }

      // Section 1: COLOUR
      Column {
        width: parent.width
        spacing: 8

        Text {
          textFormat: Text.PlainText
          text: Theme.t(root.lang, "RENK", "COLOUR")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.DemiBold
          font.letterSpacing: 1.0
          color: root.tokens.muted || "#888888"
        }

        Flow {
          width: parent.width
          spacing: 7

          Repeater {
            model: Theme.palette.length
            delegate: Rectangle {
              readonly property string hex: Theme.palette[index]
              readonly property bool picked: root.selColor.toLowerCase() === hex.toLowerCase()
              width: 24
              height: 24
              radius: 7
              color: hex
              border.width: picked ? 2 : 1
              border.color: picked ? (root.tokens.ink || "#ffffff") : Qt.rgba(0, 0, 0, 0.25)

              Rectangle {
                visible: parent.picked
                anchors.centerIn: parent
                width: 8
                height: 8
                radius: 4
                color: Theme.inkOn(parent.hex)
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selColor = parent.hex
                  hexInput.text = parent.hex
                  root.commitNow()
                }
              }
            }
          }

          // Custom hex input
          Rectangle {
            width: 86
            height: 24
            radius: 7
            color: root.tokens.card2 || "#222228"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

            TextInput {
              id: hexInput
              anchors.fill: parent
              anchors.leftMargin: 8
              anchors.rightMargin: 8
              verticalAlignment: TextInput.AlignVCenter
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.tokens.ink || "#ffffff"
              selectByMouse: true
              text: root.selColor
              onEditingFinished: {
                var v = text.trim()
                if (v.charAt(0) !== "#") v = "#" + v
                if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                  root.selColor = v.toLowerCase()
                  text = root.selColor
                  root.commitNow()
                }
              }
            }
          }
        }
      }

      // Segmented switch: Icon vs Emoji + Clear symbol
      Row {
        width: parent.width
        spacing: 8

        Repeater {
          model: [
            { key: "icon", label: Theme.t(root.lang, "İkon (100)", "Icon (100)") },
            { key: "emoji", label: Theme.t(root.lang, "Emoji", "Emoji") }
          ]
          delegate: Rectangle {
            readonly property bool active: root.tabMode === modelData.key
            width: 110
            height: 28
            radius: 7
            color: active ? (root.tokens.raised || "#2a2a32") : (root.tokens.card2 || "#1e1e24")
            border.width: 1
            border.color: active ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.2)) : "transparent"

            Text {
              textFormat: Text.PlainText
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
              onClicked: root.tabMode = modelData.key
            }
          }
        }

        Rectangle {
          width: clearLbl.implicitWidth + 18
          height: 28
          radius: 7
          color: (root.selIcon === "" && root.selEmoji === "")
            ? (root.tokens.raised || "#2a2a32")
            : (root.tokens.card2 || "#1e1e24")
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

          Text {
            textFormat: Text.PlainText
            id: clearLbl
            anchors.centerIn: parent
            text: "∅ " + Theme.t(root.lang, "Sembol yok", "No symbol")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.secondary || "#aaaaaa"
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.selIcon = ""
              root.selEmoji = ""
              emojiInput.text = ""
              root.commitNow()
            }
          }
        }
      }

      // ICON TAB
      Column {
        visible: root.tabMode === "icon"
        width: parent.width
        spacing: 9

        Rectangle {
          width: parent.width
          height: 32
          radius: 8
          color: root.tokens.card2 || "#1e1e24"
          border.width: 1
          border.color: searchField.activeFocus
            ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
            : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: searchField.text.length === 0
            text: Theme.t(root.lang, "İkon ara (kitap, kod, spor…)", "Search icons (book, code, sport…)")
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.muted || "#777777"
          }

          TextInput {
            id: searchField
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.ink || "#ffffff"
            selectByMouse: true
            onTextChanged: root.iconQuery = text
          }
        }

        Flickable {
          id: iconFlick
          width: parent.width
          height: 178
          contentWidth: width
          contentHeight: iconGrid.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds

          Flow {
            id: iconGrid
            width: parent.width
            spacing: 6

            Repeater {
              model: root.filteredIcons ? root.filteredIcons.length : 0
              delegate: Rectangle {
                id: icCell
                readonly property var ic: root.filteredIcons[index]
                readonly property bool chosen: root.selIcon === ic.name
                readonly property bool kbCur: root.kbGridActive && root.tabMode === "icon" && root.gridCursor === index
                onKbCurChanged: if (kbCur) root.ensureCellVisible(iconFlick, icCell)
                width: 34
                height: 34
                radius: 8
                color: chosen
                  ? root.selColor
                  : ((icHover.containsMouse || kbCur) ? (root.tokens.raised || "#2c2c34") : (root.tokens.card2 || "#1e1e24"))
                border.width: (chosen || kbCur) ? 1.5 : 1
                border.color: (chosen || kbCur)
                  ? (root.tokens.ink || "#ffffff")
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.07))

                Shape {
                  anchors.centerIn: parent
                  width: 18
                  height: 18
                  preferredRendererType: Shape.CurveRenderer

                  ShapePath {
                    strokeWidth: 0
                    strokeColor: "transparent"
                    fillColor: icCell.chosen
                      ? (root.selIconColor !== "" ? root.selIconColor : Theme.inkOn(root.selColor))
                      : (root.tokens.ink || "#ffffff")
                    scale: Qt.size(18.0 / 256.0, 18.0 / 256.0)
                    PathSvg { path: ic.path }
                  }
                }

                MouseArea {
                  id: icHover
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selIcon = ic.name
                    root.selEmoji = ""
                    emojiInput.text = ""
                    root.commitNow()
                  }
                }
              }
            }
          }
        }

        // ICON COLOUR ROW (Auto + White + Black + 15 palette swatches + custom hex)
        Column {
          width: parent.width
          spacing: 6

          Text {
            textFormat: Text.PlainText
            text: Theme.t(root.lang, "İKON RENGİ", "ICON COLOUR")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.DemiBold
            font.letterSpacing: 1.0
            color: root.tokens.muted || "#888888"
          }

          Flow {
            width: parent.width
            spacing: 5

            Rectangle {
              readonly property bool autoOn: root.selIconColor === ""
              width: autoTxt.implicitWidth + 14
              height: 20
              radius: 6
              color: autoOn ? (root.tokens.raised || "#2e2e36") : (root.tokens.card2 || "#1e1e24")
              border.width: 1
              border.color: autoOn ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.1))

              Text {
                textFormat: Text.PlainText
                id: autoTxt
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Otomatik", "Auto")
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.selIconColor = ""
                  iconHexInput.text = ""
                  root.commitNow()
                }
              }
            }

            Repeater {
              model: root.iconColorPalette.length
              delegate: Rectangle {
                readonly property string icHex: root.iconColorPalette[index]
                readonly property bool active: root.selIconColor.toLowerCase() === icHex.toLowerCase()
                width: 20
                height: 20
                radius: 6
                color: icHex
                border.width: active ? 2 : 1
                border.color: active ? (root.tokens.ink || "#ffffff") : (root.tokens.lineStrong || "#444444")

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selIconColor = icHex
                    iconHexInput.text = icHex
                    root.commitNow()
                  }
                }
              }
            }

            Rectangle {
              width: 78
              height: 20
              radius: 6
              color: root.tokens.card2 || "#222228"
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                visible: iconHexInput.text.length === 0
                text: "#hex"
                font.family: "Monospace"
                font.pixelSize: 10
                color: root.tokens.muted || "#777777"
              }

              TextInput {
                id: iconHexInput
                anchors.fill: parent
                anchors.leftMargin: 6
                anchors.rightMargin: 6
                verticalAlignment: TextInput.AlignVCenter
                font.family: "Monospace"
                font.pixelSize: 10
                color: root.tokens.ink || "#ffffff"
                selectByMouse: true
                onEditingFinished: {
                  var v = text.trim()
                  if (!v) {
                    root.selIconColor = ""
                    root.commitNow()
                    return
                  }
                  if (v.charAt(0) !== "#") v = "#" + v
                  if (/^#[0-9a-fA-F]{6}$/.test(v)) {
                    root.selIconColor = v.toLowerCase()
                    text = root.selIconColor
                    root.commitNow()
                  }
                }
              }
            }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: Theme.t(root.lang, "Phosphor ikonları · MIT lisansı", "Phosphor icons · MIT licence")
          font.family: root.fontFamily
          font.pixelSize: 10
          color: root.tokens.faint || "#666666"
        }
      }

      // EMOJI TAB
      Column {
        visible: root.tabMode === "emoji"
        width: parent.width
        spacing: 10

        Rectangle {
          width: 150
          height: 32
          radius: 8
          color: root.tokens.card2 || "#1e1e24"
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            visible: emojiInput.text.length === 0
            text: Theme.t(root.lang, "Emoji yaz…", "Type emoji…")
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.muted || "#777777"
          }

          TextInput {
            id: emojiInput
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            font.pixelSize: 14
            color: root.tokens.ink || "#ffffff"
            onTextEdited: {
              var first = root._firstGrapheme(text)
              if (first.length > 0) {
                if (text !== first) text = first
                root.selEmoji = first
                root.selIcon = ""
                root.commitNow()
              }
            }
          }
        }

        Flickable {
          id: emojiFlick
          width: parent.width
          height: 244
          contentWidth: width
          contentHeight: emojiFlow.implicitHeight
          clip: true

          Flow {
            id: emojiFlow
            width: parent.width
            spacing: 6

            Repeater {
              model: Theme.emojis.length
              delegate: Rectangle {
                id: emCell
                readonly property string em: Theme.emojis[index]
                readonly property bool picked: root.selEmoji === em && root.selIcon === ""
                readonly property bool kbCur: root.kbGridActive && root.tabMode === "emoji" && root.gridCursor === index
                onKbCurChanged: if (kbCur) root.ensureCellVisible(emojiFlick, emCell)
                width: 34
                height: 34
                radius: 8
                color: (picked || kbCur) ? (root.tokens.raised || "#2e2e36") : (root.tokens.card2 || "#1e1e24")
                border.width: (picked || kbCur) ? 1.5 : 1
                border.color: (picked || kbCur) ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: parent.em
                  font.pixelSize: 17
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.selEmoji = parent.em
                    root.selIcon = ""
                    emojiInput.text = parent.em
                    root.commitNow()
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
