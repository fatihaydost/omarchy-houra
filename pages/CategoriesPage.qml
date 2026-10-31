import QtQuick
import "../Theme.js" as Theme
import "../components"

Item {
  id: root

  property var service: null
  property var tokens: service ? service.tokens : ({})
  property string lang: service ? service.lang : "en"
  property string fontFamily: "Sans Serif"
  property bool kbPageActive: false
  property bool kbActive: false
  property int kbIndex: 0
  property string focusArea: "list" // "addBtn" | "list"
  property Item activeNameInput: null

  onKbPageActiveChanged: {
    if (!kbPageActive) focusArea = "list"
  }

  readonly property var categories: service ? service.categories : []
  readonly property bool isEditingText: (activeNameInput !== null && activeNameInput.activeFocus) || symbolPicker.isEditingText
  property int confirmDeleteId: 0

  onCategoriesChanged: {
    if (categories.length === 0) kbIndex = 0
    else if (kbIndex >= categories.length) kbIndex = categories.length - 1
  }

  function releaseTextFocus() {
    if (symbolPicker.open && symbolPicker.isEditingText) {
      return symbolPicker.releaseTextFocus()
    }
    if (activeNameInput !== null && activeNameInput.activeFocus) {
      activeNameInput.focus = false
      activeNameInput = null
      return true
    }
    return false
  }

  function addNewCategory() {
    if (!service) return
    var nextCol = Theme.palette[categories.length % Theme.palette.length]
    service.addCategory(
      Theme.t(lang, "Yeni Kategori", "New Category"),
      nextCol,
      "",
      "",
      ""
    )
    kbActive = true
    kbIndex = Math.max(0, categories.length)
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(catFlick.contentItem, 0, 0)
    var top = pt.y - 24
    var bot = pt.y + item.height + 24
    if (top < catFlick.contentY) {
      catFlick.contentY = Math.max(0, top)
    } else if (bot > catFlick.contentY + catFlick.height) {
      var maxY = Math.max(0, catFlick.contentHeight - catFlick.height)
      catFlick.contentY = Math.min(maxY, bot - catFlick.height)
    }
  }

  function hasOpenOverlay() {
    return symbolPicker.open
  }

  function _focusStops() {
    var stops = ["addBtn"]
    if (categories.length > 0) stops.push("list")
    return stops
  }

  function _applyStop(stop) {
    releaseTextFocus()
    focusArea = stop
    if (stop === "addBtn") catFlick.contentY = 0
    else kbActive = true
  }

  function enterFromTab(delta) {
    var stops = _focusStops()
    _applyStop(delta >= 0 ? stops[0] : stops[stops.length - 1])
  }

  function stepFocus(delta) {
    if (activeNameInput !== null && activeNameInput.activeFocus) {
      releaseTextFocus()
      focusArea = "list"
      if (delta < 0) {
        _applyStop("addBtn")
        return true
      }
      return false
    }
    var stops = _focusStops()
    var idx = stops.indexOf(focusArea)
    if (idx < 0) idx = (delta >= 0 ? -1 : stops.length)
    var next = idx + delta
    if (next < 0 || next >= stops.length) return false
    _applyStop(stops[next])
    return true
  }

  function handleKey(event) {
    if (symbolPicker.open) {
      return symbolPicker.handleKey(event)
    }
    if (isEditingText) return false

    var k = event.key
    var count = categories.length

    if (k === Qt.Key_Left) {
      return "sidebar"
    }

    if (focusArea === "addBtn") {
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
        addNewCategory()
        focusArea = "list"
        return true
      }
      if (k === Qt.Key_Down && count > 0) {
        _applyStop("list")
        return true
      }
      return false
    }

    if (k === Qt.Key_Down) {
      if (count > 0) {
        if (!kbActive || !kbPageActive) kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        else kbIndex = Math.min(count - 1, kbIndex + 1)
        kbActive = true
      }
      return true
    }
    if (k === Qt.Key_Up) {
      if (count > 0) {
        if (!kbActive || !kbPageActive) kbIndex = Math.max(0, Math.min(count - 1, kbIndex))
        else if (kbIndex === 0) { _applyStop("addBtn"); return true }
        else kbIndex = Math.max(0, kbIndex - 1)
        kbActive = true
      }
      return true
    }
    if (k === Qt.Key_Home) {
      kbActive = true
      kbIndex = 0
      catFlick.contentY = 0
      return true
    }
    if (k === Qt.Key_End) {
      kbActive = true
      if (count > 0) kbIndex = count - 1
      return true
    }
    if (count === 0) return false
    var idx = Math.max(0, Math.min(count - 1, kbIndex))
    var cat = categories[idx]

    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
      kbActive = true
      kbIndex = idx
      var rowItem = catListRepeater.itemAt(idx)
      if (rowItem) rowItem.focusRename()
      return true
    }
    if (k === Qt.Key_Space) {
      kbActive = true
      kbIndex = idx
      if (cat) symbolPicker.openFor(cat)
      return true
    }
    if ((k === Qt.Key_Delete || k === Qt.Key_Backspace) && count > 1 && cat) {
      kbActive = true
      kbIndex = idx
      var cid = Number(cat.id)
      if (confirmDeleteId === cid) {
        confirmDeleteId = 0
        if (service) service.deleteCategory(cid)
      } else {
        confirmDeleteId = cid
      }
      return true
    }
    return false
  }

  function dismissOverlay() {
    if (symbolPicker.open) {
      symbolPicker.closeModal()
      return true
    }
    if (confirmDeleteId !== 0) {
      confirmDeleteId = 0
      return true
    }
    return false
  }

  Flickable {
    id: catFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: pageCol.implicitHeight + 48
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pageCol
      x: 28
      y: 24
      width: parent.width - 56
      spacing: 18

      // Header + "+ Category" button
      Item {
        width: parent.width
        height: 44

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3

          Text {
            textFormat: Text.PlainText
            text: Theme.t(root.lang, "KONULAR", "TOPICS")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.3
            color: root.tokens.muted || "#888888"
          }

          Text {
            textFormat: Text.PlainText
            text: Theme.t(root.lang, "Kategoriler", "Categories")
            font.family: root.fontFamily
            font.pixelSize: 26
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }
        }

        Rectangle {
          readonly property bool kbFocused: root.kbPageActive && root.focusArea === "addBtn"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: addCatLbl.implicitWidth + 24
          height: 34
          radius: 9
          color: (addCatHov.containsMouse || kbFocused)
            ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.86)
            : (root.tokens.primaryBg || "#ffffff")
          border.width: kbFocused ? 2 : 0
          border.color: root.tokens.accent || "#3d8cff"

          Text {
            textFormat: Text.PlainText
            id: addCatLbl
            anchors.centerIn: parent
            text: "+ " + Theme.t(root.lang, "Kategori", "Category")
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.tokens.primaryInk || "#000000"
          }

          MouseArea {
            id: addCatHov
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.addNewCategory()
          }
        }
      }

      Text {
        textFormat: Text.PlainText
        width: parent.width
        text: Theme.t(
          root.lang,
          "Renk, emoji veya 100 ikondan birini seçmek için kategori kutucuğuna tıkla. Adını doğrudan düzenleyebilirsin.",
          "Click any category swatch to pick a colour, emoji, or one of 100 icons. Edit names inline."
        )
        font.family: root.fontFamily
        font.pixelSize: 12
        color: root.tokens.muted || "#888888"
      }

      // Category list
      Column {
        width: parent.width
        spacing: 10

        Repeater {
          id: catListRepeater
          model: root.categories.length
          delegate: Rectangle {
            id: catRowCard
            readonly property var cat: root.categories[index]
            readonly property bool confirming: root.confirmDeleteId === Number(cat.id)
            readonly property bool kbSelected: root.kbPageActive && root.focusArea === "list" && root.kbActive && root.kbIndex === index
            onKbSelectedChanged: if (kbSelected) root.ensureItemVisible(catRowCard)
            function focusRename() {
              nameInput.forceActiveFocus()
              nameInput.selectAll()
            }
            width: pageCol.width
            height: 58
            radius: 12
            color: kbSelected
              ? (root.tokens.raised || "#26262f")
              : (catRowHover.hovered ? (root.tokens.card2 || "#1c1c22") : (root.tokens.card || "#17171c"))
            border.width: (kbSelected || nameInput.activeFocus) ? 1.5 : 1
            border.color: (kbSelected || nameInput.activeFocus)
              ? (root.tokens.ink || "#ffffff")
              : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

            HoverHandler { id: catRowHover }

            Item {
              anchors.fill: parent
              anchors.leftMargin: 14
              anchors.rightMargin: 14

              // Swatch button -> opens SymbolPicker
              Item {
                id: swatchBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 34
                height: 34

                CategorySwatch {
                  anchors.centerIn: parent
                  swatchSize: 32
                  swatchColor: cat.color || "#4c8df0"
                  emoji: cat.emoji || ""
                  iconName: cat.icon || ""
                  iconColor: cat.iconColor || ""
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: symbolPicker.openFor(cat)
                }
              }

              // Inline editable name
              TextInput {
                id: nameInput
                anchors.left: swatchBtn.right
                anchors.leftMargin: 14
                anchors.right: statsRow.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                text: cat.name || ""
                font.family: root.fontFamily
                font.pixelSize: 14
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
                selectByMouse: true
                onActiveFocusChanged: {
                  if (activeFocus) {
                    root.activeNameInput = nameInput
                    root.kbIndex = index
                  } else if (root.activeNameInput === nameInput) {
                    root.activeNameInput = null
                  }
                }
                onEditingFinished: {
                  var trimmed = text.trim()
                  if (trimmed.length > 0 && trimmed !== cat.name && root.service) {
                    root.service.updateCategory(cat.id, trimmed, cat.color, cat.emoji, cat.icon, cat.iconColor)
                  } else {
                    text = cat.name
                  }
                }
                Keys.onReturnPressed: focus = false
              }

              // Lifetime stats + Hover-only Delete button
              Row {
                id: statsRow
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                  textFormat: Text.PlainText
                  anchors.verticalCenter: parent.verticalCenter
                  text: (cat.sessionCount || 0) + " " + Theme.t(root.lang, "oturum", "sessions") +
                        " · " + Theme.formatMinutes(cat.totalMinutes || 0, root.lang)
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  color: root.tokens.secondary || "#aaaaaa"
                }

                Rectangle {
                  visible: root.categories.length > 1 && (catRowHover.hovered || catRowCard.confirming || catRowCard.kbSelected)
                  anchors.verticalCenter: parent.verticalCenter
                  width: catRowCard.confirming ? (delLbl.implicitWidth + 16) : 28
                  height: 28
                  radius: 7
                  color: catRowCard.confirming
                    ? (root.tokens.danger || "#e06458")
                    : (delArea.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent")

                  Text {
                    textFormat: Text.PlainText
                    id: delLbl
                    anchors.centerIn: parent
                    text: catRowCard.confirming
                      ? Theme.t(root.lang, "Sil?", "Delete?")
                      : "×"
                    font.family: root.fontFamily
                    font.pixelSize: catRowCard.confirming ? 11 : 16
                    font.weight: Font.DemiBold
                    color: catRowCard.confirming
                      ? "#ffffff"
                      : (root.tokens.muted || "#888888")
                  }

                  MouseArea {
                    id: delArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (catRowCard.confirming) {
                        root.confirmDeleteId = 0
                        if (root.service) root.service.deleteCategory(cat.id)
                      } else {
                        root.confirmDeleteId = Number(cat.id)
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
  }

  SymbolPicker {
    id: symbolPicker
    tokens: root.tokens
    lang: root.lang
    fontFamily: root.fontFamily
    onSaveCategory: function(catId, col, em, ic, icCol) {
      if (!root.service) return
      var cname = ""
      for (var i = 0; i < root.categories.length; i++) {
        if (Number(root.categories[i].id) === catId) {
          cname = root.categories[i].name
          break
        }
      }
      root.service.updateCategory(catId, cname, col, em, ic, icCol)
    }
  }
}
