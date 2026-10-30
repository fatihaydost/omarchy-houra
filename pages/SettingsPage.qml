import QtQuick
import "../Theme.js" as Theme

Item {
  id: root

  property var service: null
  property var tokens: service ? service.tokens : ({})
  property string lang: service ? service.lang : "en"
  property string fontFamily: "Sans Serif"
  property bool kbPageActive: false

  readonly property bool isEditingText: weeklyInput.activeFocus || tdTokenInput.activeFocus || todoistFilterInput.activeFocus || dbPathInput.activeFocus

  readonly property var settings: service && service.settings ? service.settings : ({})
  readonly property var weekly: service && service.weeklyData ? service.weeklyData : ({})
  readonly property var todoist: service && service.todoistData ? service.todoistData : ({})
  property bool revealTodoistToken: false

  Connections {
    target: root.service
    function onSettingsChanged() {
      if (!weeklyInput.activeFocus && root.service && root.service.settings) {
        weeklyInput.text = root.service.settings.weeklyTemplate || ""
      }
      if (!todoistFilterInput.activeFocus && root.service && root.service.settings) {
        todoistFilterInput.text = root.service.settings.todoistFilter || "today | overdue"
      }
    }
  }

  Component.onCompleted: {
    if (service && service.settings) {
      weeklyInput.text = service.settings.weeklyTemplate || ""
      todoistFilterInput.text = service.settings.todoistFilter || "today | overdue"
    }
  }

  // Auto-save weekly template 550ms after typing pauses
  Timer {
    id: weeklySaveTimer
    interval: 550
    onTriggered: {
      if (!root.service) return
      var trimmed = weeklyInput.text.trim()
      var current = root.settings && root.settings.weeklyTemplate ? String(root.settings.weeklyTemplate) : ""
      if (trimmed !== current) {
        root.service.patchSettings({ weeklyTemplate: trimmed })
      }
    }
  }

  function commitWeeklyTemplate(forceEnable) {
    weeklySaveTimer.stop()
    if (!service) return
    var trimmed = weeklyInput.text.trim()
    var patch = { weeklyTemplate: trimmed }
    if (forceEnable && trimmed.length > 0) patch.weeklyOn = true
    service.patchSettings(patch)
  }

  function submitTodoistToken() {
    if (!service) return
    var tok = tdTokenInput.text.trim()
    if (!tok) return
    tdTokenInput.text = ""
    tdTokenInput.focus = false
    revealTodoistToken = false
    service.saveTodoistToken(tok)
  }

  function commitTodoistFilter() {
    if (!service) return
    var filt = todoistFilterInput.text.trim() || "today | overdue"
    todoistFilterInput.text = filt
    if (todoist.hasToken && settings.todoistOn) {
      service.syncTodoistNow(filt, true)
    } else {
      service.patchSettings({ todoistFilter: filt })
    }
  }

  function releaseTextFocus() {
    if (!isEditingText) return false
    weeklyInput.focus = false
    tdTokenInput.focus = false
    todoistFilterInput.focus = false
    dbPathInput.focus = false
    return true
  }

  function dismissOverlay() {
    return false
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, settingsFlick.contentHeight - settingsFlick.height)
    settingsFlick.contentY = Math.max(0, Math.min(maxY, settingsFlick.contentY + dy))
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(settingsFlick.contentItem, 0, 0)
    var top = pt.y - 32
    var bot = pt.y + item.height + 32
    if (top < settingsFlick.contentY) {
      settingsFlick.contentY = Math.max(0, top)
    } else if (bot > settingsFlick.contentY + settingsFlick.height) {
      const maxY = Math.max(0, settingsFlick.contentHeight - settingsFlick.height)
      settingsFlick.contentY = Math.min(maxY, bot - settingsFlick.height)
    }
  }

  function hasOpenOverlay() {
    return false
  }

  function _focusStops() {
    var stops = ["scroll"]
    if (settings.weeklyOn) stops.push("weeklyInput")
    if (settings.todoistOn) {
      if (!todoist.hasToken) stops.push("tdTokenInput")
      stops.push("todoistFilterInput")
    }
    stops.push("dbPathInput")
    return stops
  }

  function _applyStop(stop) {
    if (stop === "weeklyInput") {
      ensureItemVisible(weeklyInput)
      weeklyInput.forceActiveFocus()
    } else if (stop === "tdTokenInput") {
      ensureItemVisible(tdTokenInput)
      tdTokenInput.forceActiveFocus()
    } else if (stop === "todoistFilterInput") {
      ensureItemVisible(todoistFilterInput)
      todoistFilterInput.forceActiveFocus()
    } else if (stop === "dbPathInput") {
      ensureItemVisible(dbPathInput)
      dbPathInput.forceActiveFocus()
    } else {
      releaseTextFocus()
    }
  }

  function enterFromTab(delta) {
    var stops = _focusStops()
    _applyStop(delta >= 0 ? stops[0] : stops[stops.length - 1])
  }

  function stepFocus(delta) {
    var stops = _focusStops()
    var cur = "scroll"
    if (weeklyInput.activeFocus) cur = "weeklyInput"
    else if (tdTokenInput.activeFocus) cur = "tdTokenInput"
    else if (todoistFilterInput.activeFocus) cur = "todoistFilterInput"
    else if (dbPathInput.activeFocus) cur = "dbPathInput"
    var idx = stops.indexOf(cur)
    if (idx < 0) idx = (delta >= 0 ? -1 : stops.length)
    var next = idx + delta
    if (next < 0 || next >= stops.length) return false
    _applyStop(stops[next])
    return true
  }

  function handleKey(event) {
    if (isEditingText) return false
    var k = event.key

    if (k === Qt.Key_Left) {
      return "sidebar"
    }
    if (k === Qt.Key_Down) { scrollBy(64); return true }
    if (k === Qt.Key_Up) { scrollBy(-64); return true }
    if (k === Qt.Key_PageDown) { scrollBy(Math.round(settingsFlick.height * 0.72)); return true }
    if (k === Qt.Key_PageUp) { scrollBy(-Math.round(settingsFlick.height * 0.72)); return true }
    if (k === Qt.Key_Home) { settingsFlick.contentY = 0; return true }
    if (k === Qt.Key_End) { scrollBy(99999); return true }
    return false
  }

  Flickable {
    id: settingsFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: pageCol.implicitHeight + 52
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: pageCol
      x: 28
      y: 24
      width: Math.min(760, parent.width - 56)
      spacing: 18

      // Header
      Column {
        width: parent.width
        spacing: 4

        Text {
          text: Theme.t(root.lang, "TERCİHLER", "PREFERENCES")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 1.3
          color: root.tokens.muted || "#888888"
        }

        Text {
          text: Theme.t(root.lang, "Ayarlar", "Settings")
          font.family: root.fontFamily
          font.pixelSize: 26
          font.weight: Font.Light
          color: root.tokens.ink || "#ffffff"
        }
      }

      // 1. OMARCHY & HYPRLAND INTEGRATION
      Rectangle {
        width: parent.width
        height: omarchyCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: omarchyCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 14

          Text {
            text: Theme.t(root.lang, "OMARCHY & SİSTEM UYUMU", "OMARCHY & SYSTEM INTEGRATION")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.1
            color: root.tokens.muted || "#888888"
          }

          // Theme mode: Omarchy theme vs Houra classic
          Item {
            width: parent.width
            height: 36

            Column {
              anchors.left: parent.left
              anchors.right: themeModeRow.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                text: Theme.t(root.lang, "Görünüm teması", "Appearance theme")
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              Text {
                width: parent.width
                elide: Text.ElideRight
                text: Theme.t(
                  root.lang,
                  "Aktif Omarchy temasıyla canlı eşleşir veya klasik monokrom Houra görünümünü kullanır.",
                  "Adapts live to your active Omarchy theme or uses Houra's classic monochrome dark palette."
                )
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.tokens.muted || "#888888"
              }
            }

            Row {
              id: themeModeRow
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6

              Repeater {
                model: [
                  { key: "omarchy", label: Theme.t(root.lang, "Omarchy teması", "Omarchy theme") },
                  { key: "classic", label: Theme.t(root.lang, "Houra klasik", "Houra classic") }
                ]
                delegate: Rectangle {
                  readonly property bool active: (root.settings.themeMode || "omarchy") === modelData.key
                  width: tmLbl.implicitWidth + 18
                  height: 28
                  radius: 7
                  color: active ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#1f1f25")
                  border.width: 1
                  border.color: active ? "transparent" : (root.tokens.line || Qt.rgba(1, 1, 1, 0.1))

                  Text {
                    id: tmLbl
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                    color: parent.active ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#bbbbbb")
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.patchSettings({ themeMode: modelData.key })
                  }
                }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08) }

          // Do Not Disturb during focus
          Item {
            width: parent.width
            height: 36

            Column {
              anchors.left: parent.left
              anchors.right: dndSwitch.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2

              Text {
                text: Theme.t(root.lang, "Odak sırasında Rahatsız Etme (DND)", "Do Not Disturb during focus")
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              Text {
                width: parent.width
                elide: Text.ElideRight
                text: Theme.t(
                  root.lang,
                  "Odak başladığında Omarchy bildirimlerini sessize alır, mola veya bitişte eski haline döndürür.",
                  "Silences Omarchy notifications when focus starts and restores your previous DND state on break."
                )
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.tokens.muted || "#888888"
              }
            }

            Rectangle {
              id: dndSwitch
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 44
              height: 24
              radius: 12
              color: root.settings.focusDnd ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#222228")
              border.width: 1
              border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

              Rectangle {
                x: root.settings.focusDnd ? 22 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: root.settings.focusDnd ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#aaaaaa")
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.patchSettings({ focusDnd: !root.settings.focusDnd })
              }
            }
          }
        }
      }

      // 2. LANGUAGE & ON-SCREEN VIEW
      Rectangle {
        width: parent.width
        height: genCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: genCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 14

          // Language
          Item {
            width: parent.width
            height: 30

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "Dil", "Language")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 6

              Repeater {
                model: [
                  { key: "system", label: Theme.t(root.lang, "Sistem", "System") },
                  { key: "tr", label: "Türkçe" },
                  { key: "en", label: "English" }
                ]
                delegate: Rectangle {
                  readonly property bool active: (root.settings.language || "system") === modelData.key
                  width: langLbl.implicitWidth + 18
                  height: 28
                  radius: 7
                  color: active ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#1f1f25")

                  Text {
                    id: langLbl
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                    color: parent.active ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#bbbbbb")
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.patchSettings({ language: modelData.key })
                  }
                }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08) }

          // Show on screen
          Column {
            width: parent.width
            spacing: 8

            Text {
              text: Theme.t(root.lang, "Ekranda göster", "Show on screen")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }

            Flow {
              width: parent.width
              spacing: 6

              Repeater {
                model: [
                  { key: "tag", label: Theme.t(root.lang, "Etiket", "Tag") },
                  { key: "strip", label: Theme.t(root.lang, "İnce şerit", "Thin strip") },
                  { key: "capsule", label: Theme.t(root.lang, "Kapsül", "Capsule") },
                  { key: "card", label: Theme.t(root.lang, "Kart", "Card") },
                  { key: "ring", label: Theme.t(root.lang, "Halka", "Ring") },
                  { key: "none", label: Theme.t(root.lang, "Hiçbiri", "None") }
                ]
                delegate: Rectangle {
                  readonly property bool active: (root.service ? root.service.widgetStyle : "tag") === modelData.key
                  width: wsTxt.implicitWidth + 22
                  height: 30
                  radius: 8
                  color: active ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#1f1f25")

                  Text {
                    id: wsTxt
                    anchors.centerIn: parent
                    text: modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: parent.active ? Font.DemiBold : Font.Normal
                    color: parent.active ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#bbbbbb")
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.service) root.service.setWidgetStyle(modelData.key)
                  }
                }
              }
            }
          }
        }
      }

      // 3. WEEKLY MARKDOWN TASKS
      Rectangle {
        width: parent.width
        height: wkCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: wkCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 10

          Item {
            width: parent.width
            height: 26

            Text {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "Haftalık görevler (Markdown)", "Weekly tasks (Markdown)")
              font.family: root.fontFamily
              font.pixelSize: 13
              font.weight: Font.Medium
              color: root.tokens.ink || "#ffffff"
            }

            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 44
              height: 24
              radius: 12
              color: root.settings.weeklyOn ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#222228")
              border.width: 1
              border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

              Rectangle {
                x: root.settings.weeklyOn ? 22 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: root.settings.weeklyOn ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#aaaaaa")
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.patchSettings({ weeklyOn: !root.settings.weeklyOn, weeklyTemplate: weeklyInput.text.trim() })
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: Theme.t(
              root.lang,
              "Salt-okuma Markdown yol şablonu (Obsidian vb. dosyalara asla yazmaz). Yer tutucular: {YYYY}, {WW}, {W}, {MM} ve * joker karakteri.",
              "Read-only Markdown path template (never writes to your notes). Placeholders: {YYYY}, {WW}, {W}, {MM}, plus * wildcard."
            )
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.muted || "#888888"
          }

          Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: root.tokens.card2 || "#1f1f25"
            border.width: 1
            border.color: weeklyInput.activeFocus
              ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
              : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

            Text {
              anchors.left: parent.left
              anchors.leftMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              visible: weeklyInput.text.length === 0
              text: "~/Notes/Weekly/{YYYY}-W{WW}.md"
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.tokens.muted || "#777777"
            }

            TextInput {
              id: weeklyInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              verticalAlignment: TextInput.AlignVCenter
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.tokens.ink || "#ffffff"
              selectByMouse: true
              onTextEdited: weeklySaveTimer.restart()
              onEditingFinished: root.commitWeeklyTemplate(false)
              Keys.onReturnPressed: {
                root.commitWeeklyTemplate(true)
                focus = false
              }
            }
          }

          // Native folder & file picker buttons + manual Save
          Flow {
            width: parent.width
            spacing: 8

            Rectangle {
              width: chooseFolderLbl.implicitWidth + 20
              height: 30
              radius: 8
              color: chooseFolderHov.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                id: chooseFolderLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Klasör seç…", "Choose folder…")
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: chooseFolderHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.chooseWeeklyFolder()
              }
            }

            Rectangle {
              width: chooseFileLbl.implicitWidth + 20
              height: 30
              radius: 8
              color: chooseFileHov.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                id: chooseFileLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Dosya seç…", "Choose file…")
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: chooseFileHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.chooseWeeklyFile()
              }
            }

            Rectangle {
              width: saveWkLbl.implicitWidth + 20
              height: 30
              radius: 8
              color: saveWkHov.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                id: saveWkLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Şimdi yenile", "Refresh now")
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.secondary || "#cccccc"
              }

              MouseArea {
                id: saveWkHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.commitWeeklyTemplate(true)
              }
            }
          }

          Text {
            visible: !!root.settings.weeklyOn && String(root.settings.weeklyTemplate || "").trim().length > 0
            text: root.weekly.exists
              ? (Theme.t(root.lang, "Bu hafta: ", "This week: ") + root.weekly.fileName + " · " + root.weekly.openCount + " " + Theme.t(root.lang, "açık görev", "open tasks"))
              : Theme.t(root.lang, "Bu hafta için eşleşen Markdown dosyası bulunamadı.", "No matching weekly Markdown file found.")
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.weekly.exists ? (root.tokens.secondary || "#bbbbbb") : (root.tokens.muted || "#777777")
          }
        }
      }

      // 4. TODOIST 2-WAY INTEGRATION
      Rectangle {
        width: parent.width
        height: tdCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: tdCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 12

          // Title + Connection Pill + Toggle Switch
          Item {
            width: parent.width
            height: 26

            Row {
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "Todoist"
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              Rectangle {
                readonly property bool hasErr: (root.todoist.error || "") !== ""
                readonly property bool isLive: !hasErr && !!root.todoist.hasToken && !!root.settings.todoistOn
                readonly property string accText: String(root.todoist.account || "").trim()
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(340, tdConnLbl.implicitWidth + 14)
                height: 20
                radius: 10
                color: hasErr
                  ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.16)
                  : (isLive
                    ? Theme.withAlpha("#4fc08d", 0.16)
                    : (root.tokens.card2 || "#1f1f25"))
                border.width: 1
                border.color: hasErr
                  ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.48)
                  : (isLive
                    ? Theme.withAlpha("#4fc08d", 0.45)
                    : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08)))

                Text {
                  id: tdConnLbl
                  width: Math.min(326, implicitWidth)
                  anchors.centerIn: parent
                  elide: Text.ElideRight
                  text: parent.hasErr
                    ? Theme.t(root.lang, "Bağlantı hatası", "Connection error")
                    : (!root.todoist.hasToken
                      ? Theme.t(root.lang, "Bağlı değil", "Not connected")
                      : (root.settings.todoistOn
                        ? (parent.accText !== ""
                          ? (Theme.t(root.lang, "Bağlı · ", "Connected · ") + parent.accText)
                          : Theme.t(root.lang, "Bağlı", "Connected"))
                        : (parent.accText !== ""
                          ? (Theme.t(root.lang, "Kapalı · ", "Off · ") + parent.accText)
                          : Theme.t(root.lang, "Anahtar kayıtlı · kapalı", "Token saved · off"))))
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  font.weight: Font.Medium
                  color: parent.hasErr
                    ? (root.tokens.danger || "#e06458")
                    : (parent.isLive ? "#4fc08d" : (root.tokens.muted || "#888888"))
                }
              }
            }

            Rectangle {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: 44
              height: 24
              radius: 12
              color: root.settings.todoistOn ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#222228")
              border.width: 1
              border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.16)

              Rectangle {
                x: root.settings.todoistOn ? 22 : 2
                y: 2
                width: 20
                height: 20
                radius: 10
                color: root.settings.todoistOn ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#aaaaaa")
                Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!root.service) return
                  var nextOn = !root.settings.todoistOn
                  if (nextOn && root.todoist.hasToken) {
                    root.service.syncTodoistNow(todoistFilterInput.text.trim() || "today | overdue", true)
                  } else {
                    root.service.patchSettings({ todoistOn: nextOn })
                  }
                }
              }
            }
          }

          // Direct Todoist website API token instructions + 1-click link to Todoist Developer Settings
          Item {
            width: parent.width
            height: Math.max(30, tdHelpTxt.implicitHeight)

            Text {
              id: tdHelpTxt
              anchors.left: parent.left
              anchors.right: openTdWebBtn.left
              anchors.rightMargin: 12
              anchors.verticalCenter: parent.verticalCenter
              wrapMode: Text.WordWrap
              text: Theme.t(
                root.lang,
                "Todoist web sitesinden (Settings → Integrations → Developer) kişisel API anahtarını kopyalayıp hesabını doğrudan bağla. Anahtar yalnız ~/.local/state/houra/todoist_token (chmod 600) içinde saklanır.",
                "Copy your personal API token from Todoist's website (Settings → Integrations → Developer) to connect your account directly. Stored privately in ~/.local/state/houra/todoist_token (chmod 600)."
              )
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }

            Rectangle {
              id: openTdWebBtn
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: openTdWebLbl.implicitWidth + 18
              height: 30
              radius: 8
              color: openTdWebArea.containsMouse
                ? Theme.withAlpha("#e44332", 0.22)
                : Theme.withAlpha("#e44332", 0.12)
              border.width: 1
              border.color: Theme.withAlpha("#e44332", openTdWebArea.containsMouse ? 0.60 : 0.38)

              Text {
                id: openTdWebLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Todoist API sayfasını aç ↗", "Open Todoist API page ↗")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: openTdWebArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.openTodoistDeveloperSettings()
              }
            }
          }

          // Personal API key input + Paste / Show + Connect (or Switch Account) / Disconnect
          Row {
            width: parent.width
            spacing: 8

            Rectangle {
              width: parent.width - saveTdBtn.width - (disconnectTdBtn.visible ? (disconnectTdBtn.width + 16) : 8)
              height: 34
              radius: 8
              color: root.tokens.card2 || "#1f1f25"
              border.width: 1
              border.color: tdTokenInput.activeFocus
                ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
                : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: tdInlineBtns.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                visible: tdTokenInput.text.length === 0
                text: root.todoist.hasToken
                  ? Theme.t(root.lang, "Başka bir Todoist hesabı bağlamak için yeni API anahtarı yapıştır…", "Paste a new API token to switch Todoist accounts…")
                  : Theme.t(root.lang, "Todoist API anahtarını buraya yapıştır…", "Paste your Todoist API token here…")
                font.family: "Monospace"
                font.pixelSize: 11
                color: root.tokens.muted || "#777777"
              }

              TextInput {
                id: tdTokenInput
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: tdInlineBtns.left
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                echoMode: root.revealTodoistToken ? TextInput.Normal : TextInput.Password
                font.family: "Monospace"
                font.pixelSize: 11
                color: root.tokens.ink || "#ffffff"
                selectByMouse: true
                Keys.onReturnPressed: root.submitTodoistToken()
              }

              Row {
                id: tdInlineBtns
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Rectangle {
                  visible: tdTokenInput.text.length > 0
                  width: showTdKeyLbl.implicitWidth + 10
                  height: 22
                  radius: 5
                  color: showTdKeyArea.containsMouse ? (root.tokens.raised || "#2b2b33") : "transparent"

                  Text {
                    id: showTdKeyLbl
                    anchors.centerIn: parent
                    text: root.revealTodoistToken
                      ? Theme.t(root.lang, "Gizle", "Hide")
                      : Theme.t(root.lang, "Göster", "Show")
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    color: root.tokens.muted || "#888888"
                  }

                  MouseArea {
                    id: showTdKeyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.revealTodoistToken = !root.revealTodoistToken
                  }
                }

                Rectangle {
                  width: pasteTdKeyLbl.implicitWidth + 12
                  height: 22
                  radius: 5
                  color: pasteTdKeyArea.containsMouse
                    ? (root.tokens.raised || "#2b2b33")
                    : Theme.withAlpha(root.tokens.ink || "#ffffff", 0.05)

                  Text {
                    id: pasteTdKeyLbl
                    anchors.centerIn: parent
                    text: Theme.t(root.lang, "Yapıştır", "Paste")
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    font.weight: Font.Medium
                    color: root.tokens.secondary || "#cccccc"
                  }

                  MouseArea {
                    id: pasteTdKeyArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.service) {
                        root.service.readClipboardText(function(val) {
                          if (val) tdTokenInput.text = val
                        })
                      }
                    }
                  }
                }
              }
            }

            Rectangle {
              id: saveTdBtn
              width: saveTdLbl.implicitWidth + 18
              height: 34
              radius: 8
              opacity: tdTokenInput.text.trim().length > 0 ? 1.0 : 0.5
              color: saveTdArea.containsMouse && tdTokenInput.text.trim().length > 0
                ? Theme.withAlpha(root.tokens.primaryBg || "#ffffff", 0.88)
                : (root.tokens.primaryBg || "#ffffff")

              Text {
                id: saveTdLbl
                anchors.centerIn: parent
                text: root.todoist.hasToken
                  ? Theme.t(root.lang, "Hesabı bağla", "Switch account")
                  : Theme.t(root.lang, "Kaydet & Bağla", "Connect account")
                font.family: root.fontFamily
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: root.tokens.primaryInk || "#000000"
              }

              MouseArea {
                id: saveTdArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: tdTokenInput.text.trim().length > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.submitTodoistToken()
              }
            }

            Rectangle {
              id: disconnectTdBtn
              visible: !!root.todoist.hasToken
              width: disconnectTdLbl.implicitWidth + 18
              height: 34
              radius: 8
              color: disconnectTdArea.containsMouse
                ? Theme.withAlpha(root.tokens.danger || "#e06458", 0.18)
                : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: disconnectTdArea.containsMouse
                ? (root.tokens.danger || "#e06458")
                : (root.tokens.line || Qt.rgba(1, 1, 1, 0.1))

              Text {
                id: disconnectTdLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Bağlantıyı kes", "Disconnect")
                font.family: root.fontFamily
                font.pixelSize: 11
                color: disconnectTdArea.containsMouse
                  ? (root.tokens.danger || "#e06458")
                  : (root.tokens.secondary || "#cccccc")
              }

              MouseArea {
                id: disconnectTdArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.clearTodoistToken()
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08) }

          // Filter presets + custom Todoist query + Sync Now
          Column {
            width: parent.width
            spacing: 8

            Item {
              width: parent.width
              height: 26

              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.t(root.lang, "Görev filtresi", "Task filter")
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                Repeater {
                  model: [
                    { query: "today | overdue", label: Theme.t(root.lang, "Bugün & Gecikmiş", "Today & Overdue") },
                    { query: "#Inbox", label: Theme.t(root.lang, "Gelen Kutusu", "Inbox") },
                    { query: "all", label: Theme.t(root.lang, "Tümü", "All") }
                  ]
                  delegate: Rectangle {
                    readonly property bool active: (root.settings.todoistFilter || "today | overdue") === modelData.query
                    width: presetLbl.implicitWidth + 16
                    height: 24
                    radius: 6
                    color: active ? (root.tokens.primaryBg || "#ffffff") : (root.tokens.card2 || "#1f1f25")
                    border.width: 1
                    border.color: active ? "transparent" : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                    Text {
                      id: presetLbl
                      anchors.centerIn: parent
                      text: modelData.label
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      font.weight: parent.active ? Font.DemiBold : Font.Normal
                      color: parent.active ? (root.tokens.primaryInk || "#000000") : (root.tokens.secondary || "#bbbbbb")
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        todoistFilterInput.text = modelData.query
                        root.commitTodoistFilter()
                      }
                    }
                  }
                }
              }
            }

            Row {
              width: parent.width
              spacing: 8

              Rectangle {
                width: parent.width - syncTdBtn.width - 8
                height: 32
                radius: 8
                color: root.tokens.card2 || "#1f1f25"
                border.width: 1
                border.color: todoistFilterInput.activeFocus
                  ? (root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.24))
                  : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

                Text {
                  anchors.left: parent.left
                  anchors.leftMargin: 10
                  anchors.verticalCenter: parent.verticalCenter
                  visible: todoistFilterInput.text.length === 0
                  text: "today | overdue"
                  font.family: "Monospace"
                  font.pixelSize: 11
                  color: root.tokens.muted || "#777777"
                }

                TextInput {
                  id: todoistFilterInput
                  anchors.fill: parent
                  anchors.leftMargin: 10
                  anchors.rightMargin: 10
                  verticalAlignment: TextInput.AlignVCenter
                  font.family: "Monospace"
                  font.pixelSize: 11
                  color: root.tokens.ink || "#ffffff"
                  selectByMouse: true
                  onEditingFinished: root.commitTodoistFilter()
                  Keys.onReturnPressed: {
                    root.commitTodoistFilter()
                    focus = false
                  }
                }
              }

              Rectangle {
                id: syncTdBtn
                width: syncTdLbl.implicitWidth + 18
                height: 32
                radius: 8
                color: syncTdArea.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
                border.width: 1
                border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

                Text {
                  id: syncTdLbl
                  anchors.centerIn: parent
                  text: (root.service && root.service.todoistSyncing)
                    ? Theme.t(root.lang, "Eşitleniyor…", "Syncing…")
                    : Theme.t(root.lang, "Şimdi eşitle", "Sync now")
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  color: root.tokens.ink || "#ffffff"
                }

                MouseArea {
                  id: syncTdArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.commitTodoistFilter()
                }
              }
            }
          }

          Rectangle { width: parent.width; height: 1; color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08) }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            text: Theme.t(
              root.lang,
              "Odak oturumunun bitmesi veya kapatılması Todoist görevini otomatik kapatmaz. Görevi Todoist'te tamamlamak için oturum kartındaki / bar menüsündeki 'Todoist'te tamamla' düğmesini veya Todoist kartındaki ○ işaretini kullanabilirsin.",
              "Finishing or closing a focus session never auto-completes Todoist tasks. Use the explicit 'Complete in Todoist' button on the session card / bar menu or the ○ checkbox in the Todoist card."
            )
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.muted || "#888888"
          }

          Text {
            visible: ((root.todoist.error || "") !== "") || (!!root.settings.todoistOn && !!root.todoist.hasToken)
            width: parent.width
            wrapMode: Text.WordWrap
            text: (root.todoist.error || "") !== ""
              ? String(root.todoist.error)
              : ((root.service && root.service.todoistSyncing)
                ? Theme.t(root.lang, "Todoist ile eşitleniyor…", "Syncing with Todoist…")
                : (Theme.t(root.lang, "Eşitlendi · ", "Synced · ") + (root.todoist.openCount || 0) + " " + Theme.t(root.lang, "açık görev", "open tasks")))
            font.family: root.fontFamily
            font.pixelSize: 11
            color: (root.todoist.error || "") !== ""
              ? (root.tokens.danger || "#e06458")
              : (root.tokens.secondary || "#bbbbbb")
          }
        }
      }

      // 5. DATA & CSV EXPORT
      Rectangle {
        width: parent.width
        height: dataCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: dataCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 10

          Text {
            text: Theme.t(root.lang, "YEREL VERİ", "LOCAL DATA")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.1
            color: root.tokens.muted || "#888888"
          }

          Rectangle {
            width: parent.width
            height: 30
            radius: 7
            color: root.tokens.card2 || "#1f1f25"
            border.width: 1
            border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

            TextInput {
              id: dbPathInput
              anchors.fill: parent
              anchors.leftMargin: 10
              anchors.rightMargin: 10
              verticalAlignment: TextInput.AlignVCenter
              readOnly: true
              selectByMouse: true
              text: root.service ? root.service.dbPath : "~/.local/share/houra/houra.sqlite"
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.tokens.secondary || "#bbbbbb"
            }
          }

          Row {
            spacing: 10

            Rectangle {
              width: openDirLbl.implicitWidth + 22
              height: 32
              radius: 8
              color: openDirHov.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                id: openDirLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "Klasörü aç", "Open folder")
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: openDirHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.openDataFolder()
              }
            }

            Rectangle {
              width: expLbl.implicitWidth + 22
              height: 32
              radius: 8
              color: expHov.containsMouse ? (root.tokens.raised || "#2b2b33") : (root.tokens.card2 || "#1f1f25")
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.1)

              Text {
                id: expLbl
                anchors.centerIn: parent
                text: Theme.t(root.lang, "CSV olarak dışa aktar…", "Export as CSV…")
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                id: expHov
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.service) root.service.exportCsvInteractive()
              }
            }
          }

          Text {
            visible: root.service && root.service.lastCsvStatus !== ""
            text: root.service ? root.service.lastCsvStatus : ""
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.tokens.secondary || "#cccccc"
          }
        }
      }

      // Version footer matching Panel.swift:713
      Text {
        text: "Houra 1.0"
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.tokens.faint || "#555555"
      }
    }
  }
}
