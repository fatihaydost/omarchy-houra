import QtQuick
import "../Theme.js" as Theme
import "../components"

// Full Statistics dashboard matching Stats.swift & upstream screenshots:
// - Dynamic hero title (Week/Month/Year/Range) + Week / Month / Year segmented + < date range > navigator + RangePicker
// - Category-tinted "Only <Category> ×" filter chip row
// - 4 metrics: Total focus (with ↑/↓ % vs previous period), Daily average, Tasks, Best day
// - OVER TIME section with [1 · Calendar | 2 · Flow | 3 · Time map] segmented switcher (keys 1 / 2 / 3)
// - Full-width Categories breakdown (unfiltered list, barRatio bars, hover-highlight + click-filter)
// - Full-width 24-cell Most productive hours heat-strip
// - Unfiltered slide-over DayDrawer
Item {
  id: root

  property var service: null
  property var tokens: service ? service.tokens : ({})
  property string lang: service ? service.lang : "en"
  property string fontFamily: "Sans Serif"
  property bool kbPageActive: false
  property string focusArea: "content" // "period" | "range" | "chart" | "content"
  readonly property bool isEditingText: false

  onKbPageActiveChanged: {
    if (!kbPageActive) focusArea = "content"
  }

  function releaseTextFocus() { return false }

  function hasOpenOverlay() {
    return rangePicker.open || drawerDay !== null
  }

  signal jumpToSessionsDay(string dayIso)

  readonly property var stats: service && service.statsData ? service.statsData : ({})
  readonly property var days: stats.days || []
  readonly property int spanDays: Number(stats.spanDays) || 7
  readonly property int maxDayMins: Math.max(30, Number(stats.maxDayMinutes) || 60)
  readonly property var catBreakdown: stats.categoryBreakdown || []
  readonly property var hourly: stats.hourly || []
  readonly property int filterTopicId: Number(stats.filterTopicId) || 0
  readonly property string todayIso: Theme.toIsoDay(new Date())

  property string periodMode: "week" // "week" | "month" | "year" | "custom"
  property int chartTab: 1 // 1 = Calendar, 2 = Flow, 3 = Time map
  property int hoveredCategoryId: 0
  property int flowHoverIdx: -1
  property real flowMouseX: 0
  property real flowMouseY: 0
  property int hoveredHour: -1
  property var drawerDay: null

  readonly property var activeFilterCat: {
    if (filterTopicId <= 0 || !service || !service.categories) return null
    for (var i = 0; i < service.categories.length; i++) {
      if (Number(service.categories[i].id) === filterTopicId) return service.categories[i]
    }
    return null
  }

  readonly property string activeAccentColor: {
    if (activeFilterCat && activeFilterCat.color) return String(activeFilterCat.color)
    return Theme.statsAccent || "#3d8cff"
  }

  function selectChart(num) {
    if (num >= 1 && num <= 3) chartTab = num
  }

  function dismissOverlay() {
    if (rangePicker.open) {
      rangePicker.open = false
      return true
    }
    if (drawerDay !== null) {
      if (dayDrawerItem.dismissConfirm()) return true
      drawerDay = null
      return true
    }
    return false
  }

  function scrollBy(dy) {
    var maxY = Math.max(0, statsFlick.contentHeight - statsFlick.height)
    statsFlick.contentY = Math.max(0, Math.min(maxY, statsFlick.contentY + dy))
  }

  function stepDrawerDay(delta) {
    if (!drawerDay || days.length === 0) return
    var curIdx = -1
    for (var i = 0; i < days.length; i++) {
      if (days[i].day === drawerDay.day) { curIdx = i; break }
    }
    if (curIdx < 0) return
    var nextIdx = Math.max(0, Math.min(days.length - 1, curIdx + delta))
    drawerDay = days[nextIdx]
  }

  function ensureItemVisible(item) {
    if (!item) return
    var pt = item.mapToItem(statsFlick.contentItem, 0, 0)
    var top = pt.y - 24
    var bot = pt.y + item.height + 24
    if (top < statsFlick.contentY) {
      statsFlick.contentY = Math.max(0, top)
    } else if (bot > statsFlick.contentY + statsFlick.height) {
      var maxY = Math.max(0, statsFlick.contentHeight - statsFlick.height)
      statsFlick.contentY = Math.min(maxY, bot - statsFlick.height)
    }
  }

  function _applyFocusArea(area) {
    focusArea = area
    if (area === "period" || area === "range") statsFlick.contentY = 0
    else if (area === "chart") ensureItemVisible(chartSegBox)
  }

  function enterFromTab(delta) {
    _applyFocusArea(delta >= 0 ? "period" : "content")
  }

  function stepFocus(delta) {
    var stops = ["period", "range", "chart", "content"]
    var idx = stops.indexOf(focusArea)
    if (idx < 0) idx = (delta >= 0 ? -1 : stops.length)
    var next = idx + delta
    if (next < 0 || next >= stops.length) return false
    _applyFocusArea(stops[next])
    return true
  }

  function _stepPeriod(delta) {
    var modes = ["week", "month", "year"]
    var cur = modes.indexOf(periodMode)
    if (cur < 0) cur = 0
    selectPeriod(modes[(cur + delta + modes.length) % modes.length])
  }

  function _openBestDrawerDay() {
    if (days.length === 0) return
    var pick = null
    for (var d = 0; d < days.length; d++) {
      if (days[d].day === todayIso) { pick = days[d]; break }
    }
    if (!pick) {
      for (var j = days.length - 1; j >= 0; j--) {
        if ((Number(days[j].totalMinutes) || 0) > 0 && days[j].day <= todayIso) {
          pick = days[j]
          break
        }
      }
    }
    if (!pick) pick = days[days.length - 1]
    drawerDay = pick
  }

  function handleKey(event) {
    if (rangePicker.open) return rangePicker.handleKey(event)
    if (drawerDay !== null) return dayDrawerItem.handleKey(event)

    var k = event.key

    if (focusArea === "period") {
      if (k === Qt.Key_Left) { _stepPeriod(-1); return true }
      if (k === Qt.Key_Right) { _stepPeriod(1); return true }
      if (k === Qt.Key_Down) { _applyFocusArea("content"); return true }
      return false
    }

    if (focusArea === "range") {
      if (k === Qt.Key_Left) { stepRange(-1); return true }
      if (k === Qt.Key_Right) { stepRange(1); return true }
      if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) {
        rangePicker.open = !rangePicker.open
        return true
      }
      if (k === Qt.Key_Down) { _applyFocusArea("content"); return true }
      return false
    }

    if (focusArea === "chart") {
      if (k === Qt.Key_Left) { selectChart(((chartTab + 1) % 3) + 1); return true }
      if (k === Qt.Key_Right) { selectChart((chartTab % 3) + 1); return true }
      if (k === Qt.Key_Down) { scrollBy(64); return true }
      if (k === Qt.Key_Up) { scrollBy(-64); return true }
      return false
    }

    if (k === Qt.Key_Left) { stepRange(-1); return true }
    if (k === Qt.Key_Right) { stepRange(1); return true }
    if (k === Qt.Key_Return || k === Qt.Key_Enter) { _openBestDrawerDay(); return true }
    if (k === Qt.Key_Down) { scrollBy(64); return true }
    if (k === Qt.Key_Up) { scrollBy(-64); return true }
    if (k === Qt.Key_PageDown) { scrollBy(Math.round(statsFlick.height * 0.72)); return true }
    if (k === Qt.Key_PageUp) { scrollBy(-Math.round(statsFlick.height * 0.72)); return true }
    if (k === Qt.Key_Home) { statsFlick.contentY = 0; return true }
    if (k === Qt.Key_End) { scrollBy(99999); return true }
    return false
  }

  onDaysChanged: {
    flowCanvas.requestPaint()
    if (drawerDay) {
      var found = null
      for (var i = 0; i < days.length; i++) {
        if (days[i].day === drawerDay.day) { found = days[i]; break }
      }
      drawerDay = found
    }
  }

  onHoveredCategoryIdChanged: flowCanvas.requestPaint()
  onFlowHoverIdxChanged: flowCanvas.requestPaint()
  onFilterTopicIdChanged: flowCanvas.requestPaint()

  function selectPeriod(mode) {
    periodMode = mode
    var now = new Date()
    if (mode === "week") {
      var isoDow = now.getDay() === 0 ? 7 : now.getDay()
      var mon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (isoDow - 1))
      var sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
      if (service) service.setStatsRange(Theme.toIsoDay(mon), Theme.toIsoDay(sun), filterTopicId)
    } else if (mode === "month") {
      var mStart = new Date(now.getFullYear(), now.getMonth(), 1)
      var mEnd = new Date(now.getFullYear(), now.getMonth() + 1, 0)
      if (service) service.setStatsRange(Theme.toIsoDay(mStart), Theme.toIsoDay(mEnd), filterTopicId)
    } else if (mode === "year") {
      var yStart = new Date(now.getFullYear(), 0, 1)
      var yEnd = new Date(now.getFullYear(), 11, 31)
      if (service) service.setStatsRange(Theme.toIsoDay(yStart), Theme.toIsoDay(yEnd), filterTopicId)
    }
  }

  function stepRange(dir) {
    if (!service || !stats.rangeStart || !stats.rangeEnd) return
    if (periodMode === "month") {
      var cur = Theme.parseIsoDay(stats.rangeStart)
      var nmStart = new Date(cur.getFullYear(), cur.getMonth() + dir, 1)
      var nmEnd = new Date(nmStart.getFullYear(), nmStart.getMonth() + 1, 0)
      service.setStatsRange(Theme.toIsoDay(nmStart), Theme.toIsoDay(nmEnd), filterTopicId)
    } else if (periodMode === "year") {
      var yCur = Theme.parseIsoDay(stats.rangeStart)
      var nextY = yCur.getFullYear() + dir
      service.setStatsRange(
        Theme.toIsoDay(new Date(nextY, 0, 1)),
        Theme.toIsoDay(new Date(nextY, 11, 31)),
        filterTopicId
      )
    } else {
      var delta = spanDays * dir
      service.setStatsRange(
        Theme.addDaysIso(stats.rangeStart, delta),
        Theme.addDaysIso(stats.rangeEnd, delta),
        filterTopicId
      )
    }
  }

  function openDayByIso(isoStr) {
    if (!isoStr) return
    for (var i = 0; i < days.length; i++) {
      if (days[i].day === isoStr) {
        drawerDay = days[i]
        return
      }
    }
  }

  // Padded calendar cells for <= 42 days (aligned to Monday..Sunday with muted out-of-range neighbor dates)
  readonly property var tileCells: {
    if (spanDays > 42 || days.length === 0) return []
    var firstDow = Number(days[0].weekday) || 1
    var arr = []
    for (var p = firstDow - 1; p >= 1; p--) {
      var prevIso = Theme.addDaysIso(days[0].day, -p)
      var pd = Theme.parseIsoDay(prevIso)
      arr.push({ outside: true, day: prevIso, dayNum: pd.getDate(), month: pd.getMonth() + 1, totalMinutes: 0 })
    }
    for (var i = 0; i < days.length; i++) arr.push(days[i])
    var rem = arr.length % 7
    if (rem !== 0) {
      var need = 7 - rem
      var lastIso = days[days.length - 1].day
      for (var t = 1; t <= need; t++) {
        var nextIso = Theme.addDaysIso(lastIso, t)
        var nd = Theme.parseIsoDay(nextIso)
        arr.push({ outside: true, day: nextIso, dayNum: nd.getDate(), month: nd.getMonth() + 1, totalMinutes: 0 })
      }
    }
    return arr
  }

  // Heatmap columns (weeks x 7) for > 42 days
  readonly property var heatmapWeeks: {
    if (spanDays <= 42 || days.length === 0) return []
    var firstDow = Number(days[0].weekday) || 1
    var padded = []
    for (var p = 1; p < firstDow; p++) padded.push(null)
    for (var i = 0; i < days.length; i++) padded.push(days[i])
    while (padded.length % 7 !== 0) padded.push(null)
    var cols = []
    for (var w = 0; w < padded.length; w += 7) {
      cols.push(padded.slice(w, w + 7))
    }
    return cols
  }

  // Flow points: daily for <=62 days, weekly buckets for >62 days (Stats.swift:410-427)
  readonly property var flowPoints: {
    if (days.length === 0) return []
    if (spanDays <= 62) {
      return days.map(function(d) {
        return {
          labelIso: d.day,
          endIso: d.day,
          totalMinutes: Number(d.totalMinutes) || 0,
          byCategory: d.byCategory || [],
          isFuture: d.day > root.todayIso,
          rawDay: d
        }
      })
    }
    var buckets = []
    for (var i = 0; i < days.length; i += 7) {
      var slice = days.slice(i, Math.min(days.length, i + 7))
      var tot = 0
      var catMap = ({})
      for (var j = 0; j < slice.length; j++) {
        if (slice[j].day > root.todayIso) continue
        tot += Number(slice[j].totalMinutes) || 0
        var bc = slice[j].byCategory || []
        for (var k = 0; k < bc.length; k++) {
          var cid = String(bc[k].categoryId)
          if (!catMap[cid]) {
            catMap[cid] = {
              categoryId: bc[k].categoryId,
              categoryName: bc[k].categoryName,
              color: bc[k].color,
              minutes: 0
            }
          }
          catMap[cid].minutes += Number(bc[k].minutes) || 0
        }
      }
      var mergedCats = []
      for (var ck in catMap) mergedCats.push(catMap[ck])
      buckets.push({
        labelIso: slice[0].day,
        endIso: slice[slice.length - 1].day,
        totalMinutes: tot,
        byCategory: mergedCats,
        isFuture: slice[0].day > root.todayIso,
        rawDay: slice[0]
      })
    }
    return buckets
  }

  readonly property int maxFlowMins: {
    var m = 30
    for (var i = 0; i < flowPoints.length; i++) {
      if ((flowPoints[i].totalMinutes || 0) > m) m = flowPoints[i].totalMinutes
    }
    return m
  }

  // Last 31 days slice for Time Map
  readonly property var timeMapDays: {
    if (days.length <= 31) return days
    return days.slice(days.length - 31)
  }

  Flickable {
    id: statsFlick
    anchors.fill: parent
    contentWidth: width
    contentHeight: pageCol.implicitHeight + 56
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    MouseArea {
      anchors.fill: parent
      enabled: rangePicker.open
      onClicked: rangePicker.open = false
    }

    Column {
      id: pageCol
      x: 28
      y: 24
      width: parent.width - 56
      spacing: 16

      // Header + Period Segmented + Date Range Navigator
      Item {
        width: parent.width
        height: 44
        z: 30

        Column {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          spacing: 3

          Text {
            textFormat: Text.PlainText
            text: Theme.t(root.lang, "İSTATİSTİKLER", "STATISTICS")
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 1.3
            color: root.tokens.muted || "#888888"
          }

          Text {
            textFormat: Text.PlainText
            text: Theme.formatStatsTitle(root.stats.rangeStart, root.stats.rangeEnd, root.periodMode, root.lang)
            font.family: root.fontFamily
            font.pixelSize: 26
            font.weight: Font.Light
            color: root.tokens.ink || "#ffffff"
          }
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 10

          // Week / Month / Year segmented
          Rectangle {
            id: periodSegBox
            readonly property bool kbFocused: root.kbPageActive && root.focusArea === "period"
            height: 32
            width: segRow.implicitWidth + 6
            radius: 9
            color: root.tokens.card || "#17171c"
            border.width: kbFocused ? 1.5 : 1
            border.color: kbFocused ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.09))

            Row {
              id: segRow
              anchors.centerIn: parent
              spacing: 2

              Repeater {
                model: [
                  { key: "week", label: Theme.t(root.lang, "Hafta", "Week") },
                  { key: "month", label: Theme.t(root.lang, "Ay", "Month") },
                  { key: "year", label: Theme.t(root.lang, "Yıl", "Year") }
                ]
                delegate: Rectangle {
                  readonly property bool active: root.periodMode === modelData.key
                  width: pLbl.implicitWidth + 20
                  height: 26
                  radius: 7
                  color: active ? (root.tokens.raised || "#2b2b33") : "transparent"

                  Text {
                    textFormat: Text.PlainText
                    id: pLbl
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
                    onClicked: root.selectPeriod(modelData.key)
                  }
                }
              }
            }
          }

          // < Date Range > Navigator
          Row {
            spacing: 4

            Rectangle {
              width: 28
              height: 32
              radius: 8
              color: root.tokens.card || "#17171c"
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
              Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "‹"; font.pixelSize: 15; color: root.tokens.ink || "#ffffff" }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepRange(-1) }
            }

            Rectangle {
              id: rangeBtn
              readonly property bool kbFocused: root.kbPageActive && root.focusArea === "range"
              width: rangeTxt.implicitWidth + 22
              height: 32
              radius: 8
              color: rangePicker.open ? (root.tokens.raised || "#2b2b33") : (root.tokens.card || "#17171c")
              border.width: kbFocused ? 1.5 : 1
              border.color: kbFocused ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.08))

              Text {
                textFormat: Text.PlainText
                id: rangeTxt
                anchors.centerIn: parent
                text: Theme.formatDateRangeLabel(root.stats.rangeStart, root.stats.rangeEnd, root.lang)
                font.family: root.fontFamily
                font.pixelSize: 12
                font.weight: Font.Medium
                color: root.tokens.ink || "#ffffff"
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: rangePicker.open = !rangePicker.open
              }
            }

            Rectangle {
              width: 28
              height: 32
              radius: 8
              color: root.tokens.card || "#17171c"
              border.width: 1
              border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)
              Text { textFormat: Text.PlainText; anchors.centerIn: parent; text: "›"; font.pixelSize: 15; color: root.tokens.ink || "#ffffff" }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.stepRange(1) }
            }
          }
        }

        RangePicker {
          id: rangePicker
          anchors.right: parent.right
          anchors.top: parent.bottom
          anchors.topMargin: 6
          rangeStart: root.stats.rangeStart || ""
          rangeEnd: root.stats.rangeEnd || ""
          tokens: root.tokens
          lang: root.lang
          fontFamily: root.fontFamily
          onApplyRange: function(sIso, eIso) {
            root.periodMode = "custom"
            if (root.service) root.service.setStatsRange(sIso, eIso, root.filterTopicId)
          }
        }
      }

      // Dedicated Category Filter Chip Row ("Only <Category> ×")
      Item {
        visible: root.filterTopicId > 0 && !!root.activeFilterCat
        width: parent.width
        height: 28

        Rectangle {
          height: 28
          width: filtRow.implicitWidth + 20
          radius: 14
          color: Theme.withAlpha(root.activeAccentColor, 0.16)
          border.width: 1
          border.color: Theme.withAlpha(root.activeAccentColor, 0.55)

          Row {
            id: filtRow
            anchors.centerIn: parent
            spacing: 7

            CategorySwatch {
              anchors.verticalCenter: parent.verticalCenter
              swatchSize: 13
              swatchColor: root.activeFilterCat ? (root.activeFilterCat.color || "#4c8df0") : "#4c8df0"
              emoji: root.activeFilterCat ? (root.activeFilterCat.emoji || "") : ""
              iconName: root.activeFilterCat ? (root.activeFilterCat.icon || "") : ""
              iconColor: root.activeFilterCat ? (root.activeFilterCat.iconColor || "") : ""
            }

            Text {
              textFormat: Text.PlainText
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "Yalnız ", "Only ") + (root.activeFilterCat ? root.activeFilterCat.name : "") + "  ×"
              font.family: root.fontFamily
              font.pixelSize: 11
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: if (root.service) root.service.setStatsRange(root.stats.rangeStart, root.stats.rangeEnd, 0)
          }
        }
      }

      // 4 Metric Cards
      Row {
        width: parent.width
        spacing: 12

        // 1. Total focus + delta % vs previous period
        Rectangle {
          width: (pageCol.width - 36) / 4
          height: 86
          radius: 12
          color: root.tokens.card || "#17171c"
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "Toplam odak", "Total focus")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              text: Theme.formatMinutes(root.stats.totalMinutes || 0, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 20
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              text: {
                var dp = root.stats.deltaPct
                if (dp === null || dp === undefined) {
                  return Theme.t(root.lang, "önceki dönem kaydı yok", "no previous period")
                }
                var arrow = dp >= 0 ? "↑ " : "↓ "
                return arrow + Math.abs(dp) + "% " + Theme.t(root.lang, "önceki döneme göre", "vs previous period")
              }
              font.family: root.fontFamily
              font.pixelSize: 10
              color: (root.stats.deltaPct !== null && root.stats.deltaPct !== undefined && root.stats.deltaPct >= 0)
                ? "#4fc08d"
                : (root.tokens.secondary || "#aaaaaa")
            }
          }
        }

        // 2. Daily average
        Rectangle {
          width: (pageCol.width - 36) / 4
          height: 86
          radius: 12
          color: root.tokens.card || "#17171c"
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "Günlük ortalama", "Daily average")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              text: Theme.formatMinutes(root.stats.dailyAvgMinutes || 0, root.lang)
              font.family: root.fontFamily
              font.pixelSize: 20
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              text: (root.stats.sessionsCount || 0) + " " + Theme.t(root.lang, "oturum", "sessions") +
                    " · " + (root.stats.activeDays || 0) + " " + Theme.t(root.lang, "aktif gün", "active days")
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.secondary || "#aaaaaa"
            }
          }
        }

        // 3. Tasks completed
        Rectangle {
          width: (pageCol.width - 36) / 4
          height: 86
          radius: 12
          color: root.tokens.card || "#17171c"
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "Görevler", "Tasks")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              text: (root.stats.tasksDone || 0) + " / " + (root.stats.tasksTotal || 0) + " 🥳"
              font.family: root.fontFamily
              font.pixelSize: 20
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              text: "%" + (root.stats.tasksPct || 0) + " " + Theme.t(root.lang, "tamamlandı", "completed")
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.secondary || "#aaaaaa"
            }
          }
        }

        // 4. Best day (clickable -> opens DayDrawer)
        Rectangle {
          width: (pageCol.width - 36) / 4
          height: 86
          radius: 12
          color: bestHover.containsMouse ? (root.tokens.card2 || "#1f1f25") : (root.tokens.card || "#17171c")
          border.width: 1
          border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

          Column {
            anchors.fill: parent
            anchors.margins: 13
            spacing: 4

            Text {
              textFormat: Text.PlainText
              text: Theme.t(root.lang, "En iyi gün", "Best day")
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              text: (root.stats.bestDayMinutes || 0) > 0
                ? Theme.formatMinutes(root.stats.bestDayMinutes, root.lang)
                : "—"
              font.family: root.fontFamily
              font.pixelSize: 20
              font.weight: Font.DemiBold
              color: root.tokens.ink || "#ffffff"
            }

            Text {
              textFormat: Text.PlainText
              text: root.stats.bestDay
                ? (Theme.formatShortDay(root.stats.bestDay, root.lang) + " ↗")
                : Theme.t(root.lang, "henüz kayıt yok", "no sessions yet")
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.secondary || "#aaaaaa"
            }
          }

          MouseArea {
            id: bestHover
            enabled: !!root.stats.bestDay
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.openDayByIso(root.stats.bestDay)
          }
        }
      }

      // =======================================================================
      // OVER TIME SECTION HEADER + [1 · Calendar | 2 · Flow | 3 · Time map] SWITCHER
      // =======================================================================
      Item {
        width: parent.width
        height: 30

        Text {
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: Theme.t(root.lang, "ZAMANA GÖRE", "OVER TIME")
          font.family: root.fontFamily
          font.pixelSize: 10
          font.weight: Font.Bold
          font.letterSpacing: 1.2
          color: root.tokens.muted || "#888888"
        }

        Rectangle {
          id: chartSegBox
          readonly property bool kbFocused: root.kbPageActive && root.focusArea === "chart"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          height: 30
          width: chartSegRow.implicitWidth + 6
          radius: 8
          color: root.tokens.card || "#17171c"
          border.width: kbFocused ? 1.5 : 1
          border.color: kbFocused ? (root.tokens.ink || "#ffffff") : (root.tokens.line || Qt.rgba(1, 1, 1, 0.09))

          Row {
            id: chartSegRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
              model: [
                { num: 1, label: Theme.t(root.lang, "Takvim", "Calendar") },
                { num: 2, label: Theme.t(root.lang, "Akış", "Flow") },
                { num: 3, label: Theme.t(root.lang, "Saat haritası", "Time map") }
              ]
              delegate: Rectangle {
                readonly property bool active: root.chartTab === modelData.num
                width: cTabTxt.implicitWidth + 18
                height: 24
                radius: 6
                color: active ? (root.tokens.raised || "#2b2b33") : "transparent"

                Text {
                  textFormat: Text.PlainText
                  id: cTabTxt
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
                  onClicked: root.chartTab = modelData.num
                }
              }
            }
          }
        }
      }

      // =======================================================================
      // CHART 1 · CALENDAR (Tiles <=42 days | GitHub Heatmap >42 days)
      // =======================================================================
      Rectangle {
        visible: root.chartTab === 1
        width: parent.width
        height: calInner.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: calInner
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 12

          // Heatmap less..more legend when >42d
          Item {
            visible: root.spanDays > 42
            width: parent.width
            height: 16

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: 4

              Text {
                textFormat: Text.PlainText
                text: Theme.t(root.lang, "az", "less")
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.muted || "#888888"
              }

              Repeater {
                model: [0.07, 0.24, 0.46, 0.72, 0.96]
                delegate: Rectangle {
                  width: 10
                  height: 10
                  radius: 2.5
                  color: index === 0
                    ? Theme.withAlpha(root.tokens.ink || "#ffffff", 0.06)
                    : Theme.withAlpha(root.activeAccentColor, modelData)
                }
              }

              Text {
                textFormat: Text.PlainText
                text: Theme.t(root.lang, "çok", "more")
                font.family: root.fontFamily
                font.pixelSize: 10
                color: root.tokens.muted || "#888888"
              }
            }
          }

          // Mode A: 7-column Day Tiles (<= 42 days)
          Column {
            visible: root.spanDays <= 42
            width: parent.width
            spacing: 6

            Row {
              width: parent.width
              spacing: 6
              Repeater {
                model: [1, 2, 3, 4, 5, 6, 7]
                delegate: Text {
                  textFormat: Text.PlainText
                  width: (calInner.width - 36) / 7
                  horizontalAlignment: Text.AlignLeft
                  text: Theme.weekdayShort(modelData, root.lang)
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  color: root.tokens.muted || "#888888"
                }
              }
            }

            Grid {
              width: parent.width
              columns: 7
              spacing: 6

              Repeater {
                model: root.tileCells.length
                delegate: Rectangle {
                  readonly property var dObj: root.tileCells[index]
                  readonly property bool isOutside: !dObj || !!dObj.outside
                  readonly property bool isToday: !!dObj && !isOutside && dObj.day === root.todayIso
                  readonly property int mins: (!isOutside && dObj) ? (Number(dObj.totalMinutes) || 0) : 0
                  readonly property real intensity: mins > 0 ? Math.min(0.42, 0.12 + 0.30 * (mins / root.maxDayMins)) : 0.0
                  width: (calInner.width - 36) / 7
                  height: root.spanDays <= 7 ? 78 : 62
                  radius: 9
                  color: isOutside
                    ? Theme.withAlpha(root.tokens.card2 || "#1d1d22", 0.35)
                    : (tileHov.containsMouse
                        ? (root.tokens.raised || "#2b2b33")
                        : (mins > 0
                            ? Theme.withAlpha(root.activeAccentColor, intensity)
                            : (root.tokens.card2 || "#1d1d22")))
                  border.width: isToday ? 1.5 : 1
                  border.color: isToday
                    ? (root.tokens.ink || "#ffffff")
                    : (isOutside
                        ? Theme.withAlpha(root.tokens.line || "#ffffff", 0.03)
                        : (root.tokens.line || Qt.rgba(1, 1, 1, 0.07)))
                  clip: true

                  Column {
                    visible: !!dObj
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 3

                    Text {
                      textFormat: Text.PlainText
                      text: dObj ? (dObj.dayNum === 1 ? (Theme.monthShort(dObj.month, root.lang) + " 1") : String(dObj.dayNum)) : ""
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      font.weight: parent.parent.isToday ? Font.Bold : Font.Normal
                      color: parent.parent.isOutside
                        ? (root.tokens.faint || "#555555")
                        : (parent.parent.isToday ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#888888"))
                    }

                    Text {
                      textFormat: Text.PlainText
                      visible: mins > 0
                      text: Theme.formatMinutesShort(mins, root.lang)
                      font.family: "Monospace"
                      font.pixelSize: 12
                      font.weight: Font.DemiBold
                      color: root.tokens.ink || "#ffffff"
                    }
                  }

                  // Bottom stacked category mix bar (inset inside 9px rounded tile corners)
                  Row {
                    visible: !isOutside && mins > 0
                    anchors.left: parent.left
                    anchors.leftMargin: 7
                    anchors.right: parent.right
                    anchors.rightMargin: 7
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 4
                    height: 3
                    spacing: 1

                    Repeater {
                      model: (!isOutside && dObj && dObj.byCategory) ? dObj.byCategory.length : 0
                      delegate: Rectangle {
                        readonly property var seg: dObj.byCategory[index]
                        readonly property int cnt: dObj.byCategory.length
                        width: Math.max(2, (parent.width - Math.max(0, cnt - 1)) * ((seg.minutes || 0) / Math.max(1, mins)))
                        height: 3
                        radius: 1.5
                        color: seg.color || "#4c8df0"
                      }
                    }
                  }

                  MouseArea {
                    id: tileHov
                    enabled: !isOutside
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.drawerDay = dObj
                  }
                }
              }
            }
          }

          // Mode B: GitHub-style Year Heatmap (> 42 days)
          Flickable {
            visible: root.spanDays > 42
            width: parent.width
            height: 122
            contentWidth: Math.max(width, heatRow.implicitWidth)
            contentHeight: 122
            clip: true

            Row {
              id: heatRow
              spacing: 3

              Repeater {
                model: root.heatmapWeeks.length
                delegate: Column {
                  readonly property var wk: root.heatmapWeeks[index]
                  spacing: 3

                  Repeater {
                    model: 7
                    delegate: Rectangle {
                      readonly property var cellDay: wk[index]
                      readonly property int mins: cellDay ? (Number(cellDay.totalMinutes) || 0) : 0
                      readonly property real ratio: mins > 0 ? Math.min(1.0, mins / root.maxDayMins) : 0
                      readonly property bool isTodayCell: !!cellDay && cellDay.day === root.todayIso
                      width: 13
                      height: 13
                      radius: 3
                      border.width: isTodayCell ? 1 : 0
                      border.color: root.tokens.ink || "#ffffff"
                      color: !cellDay
                        ? "transparent"
                        : (mins === 0
                            ? Theme.withAlpha(root.tokens.ink || "#ffffff", 0.05)
                            : Theme.withAlpha(root.activeAccentColor, 0.22 + 0.76 * ratio))

                      MouseArea {
                        enabled: !!cellDay
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.drawerDay = cellDay
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }

      // =======================================================================
      // CHART 2 · FLOW (Cubic-Bezier Stacked / Single-Accent Area Chart)
      // =======================================================================
      Rectangle {
        visible: root.chartTab === 2
        width: parent.width
        height: 244
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Item {
          anchors.fill: parent
          anchors.margins: 16

          Canvas {
            id: flowCanvas
            anchors.fill: parent

            onPaint: {
              var ctx = getContext("2d")
              ctx.reset()
              var w = width
              var h = height - 20
              var pts = root.flowPoints
              var cats = root.catBreakdown
              if (w <= 10 || h <= 10 || pts.length === 0) return

              ctx.strokeStyle = "rgba(255,255,255,0.07)"
              ctx.lineWidth = 1
              for (var g = 0; g <= 2; g++) {
                var gy = Math.round((h * g) / 2) + 0.5
                ctx.beginPath()
                ctx.moveTo(0, gy)
                ctx.lineTo(w, gy)
                ctx.stroke()
              }

              var n = pts.length
              var lastActiveIdx = -1
              for (var p = 0; p < n; p++) {
                if (!pts[p].isFuture) lastActiveIdx = p
              }
              if (lastActiveIdx < 0) return

              var maxM = Math.max(30, root.maxFlowMins)
              function xAt(i) {
                return n === 1 ? (w / 2) : (i / (n - 1)) * w
              }
              function yAt(minsVal) {
                return h - Math.min(h - 4, (minsVal / maxM) * (h - 6))
              }

              var drawN = lastActiveIdx + 1

              if (root.filterTopicId > 0) {
                // Single-accent area curve for filtered category
                var rgbSingle = Theme.parseHexRgb(root.activeAccentColor)
                if (drawN > 1) {
                  ctx.beginPath()
                  ctx.moveTo(xAt(0), yAt(pts[0].totalMinutes || 0))
                  for (var a = 0; a < drawN - 1; a++) {
                    var ax0 = xAt(a), ax1 = xAt(a + 1)
                    var aMid = (ax0 + ax1) * 0.5
                    ctx.bezierCurveTo(aMid, yAt(pts[a].totalMinutes || 0), aMid, yAt(pts[a + 1].totalMinutes || 0), ax1, yAt(pts[a + 1].totalMinutes || 0))
                  }
                  ctx.lineTo(xAt(drawN - 1), h)
                  ctx.lineTo(xAt(0), h)
                  ctx.closePath()
                  ctx.fillStyle = "rgba(" + rgbSingle.r + "," + rgbSingle.g + "," + rgbSingle.b + ",0.32)"
                  ctx.fill()

                  ctx.beginPath()
                  ctx.moveTo(xAt(0), yAt(pts[0].totalMinutes || 0))
                  for (var b = 0; b < drawN - 1; b++) {
                    var bx0 = xAt(b), bx1 = xAt(b + 1)
                    var bMid = (bx0 + bx1) * 0.5
                    ctx.bezierCurveTo(bMid, yAt(pts[b].totalMinutes || 0), bMid, yAt(pts[b + 1].totalMinutes || 0), bx1, yAt(pts[b + 1].totalMinutes || 0))
                  }
                  ctx.strokeStyle = "rgba(" + rgbSingle.r + "," + rgbSingle.g + "," + rgbSingle.b + ",0.92)"
                  ctx.lineWidth = 2.0
                  ctx.stroke()
                }
              } else {
                var lower = []
                for (var z = 0; z < drawN; z++) lower.push(0)

                for (var cIdx = cats.length - 1; cIdx >= 0; cIdx--) {
                  var cat = cats[cIdx]
                  var cid = Number(cat.categoryId)
                  var upper = []
                  var anyNonZero = false
                  for (var dIdx = 0; dIdx < drawN; dIdx++) {
                    var bc = pts[dIdx].byCategory || []
                    var addM = 0
                    for (var k = 0; k < bc.length; k++) {
                      if (Number(bc[k].categoryId) === cid) { addM = Number(bc[k].minutes) || 0; break }
                    }
                    if (addM > 0) anyNonZero = true
                    upper.push(lower[dIdx] + addM)
                  }
                  if (!anyNonZero) continue

                  var dimmed = root.hoveredCategoryId > 0 && root.hoveredCategoryId !== cid
                  var rgb = Theme.parseHexRgb(cat.color || "#4c8df0")
                  var fillAlpha = dimmed ? 0.08 : 0.34
                  var strokeAlpha = dimmed ? 0.18 : 0.88

                  if (drawN > 1) {
                    ctx.beginPath()
                    ctx.moveTo(xAt(0), yAt(upper[0]))
                    for (var i = 0; i < drawN - 1; i++) {
                      var x0 = xAt(i), x1 = xAt(i + 1)
                      var cxMid = (x0 + x1) * 0.5
                      ctx.bezierCurveTo(cxMid, yAt(upper[i]), cxMid, yAt(upper[i + 1]), x1, yAt(upper[i + 1]))
                    }
                    ctx.lineTo(xAt(drawN - 1), yAt(lower[drawN - 1]))
                    for (var j = drawN - 1; j > 0; j--) {
                      var lx1 = xAt(j), lx0 = xAt(j - 1)
                      var lMid = (lx1 + lx0) * 0.5
                      ctx.bezierCurveTo(lMid, yAt(lower[j]), lMid, yAt(lower[j - 1]), lx0, yAt(lower[j - 1]))
                    }
                    ctx.closePath()
                    ctx.fillStyle = "rgba(" + rgb.r + "," + rgb.g + "," + rgb.b + "," + fillAlpha + ")"
                    ctx.fill()

                    ctx.beginPath()
                    ctx.moveTo(xAt(0), yAt(upper[0]))
                    for (var s = 0; s < drawN - 1; s++) {
                      var sx0 = xAt(s), sx1 = xAt(s + 1)
                      var sMid = (sx0 + sx1) * 0.5
                      ctx.bezierCurveTo(sMid, yAt(upper[s]), sMid, yAt(upper[s + 1]), sx1, yAt(upper[s + 1]))
                    }
                    ctx.strokeStyle = "rgba(" + rgb.r + "," + rgb.g + "," + rgb.b + "," + strokeAlpha + ")"
                    ctx.lineWidth = 1.7
                    ctx.stroke()
                  }

                  lower = upper
                }
              }

              // Hover vertical crosshair
              if (root.flowHoverIdx >= 0 && root.flowHoverIdx < n) {
                var hx = Math.round(xAt(root.flowHoverIdx)) + 0.5
                ctx.beginPath()
                ctx.moveTo(hx, 0)
                ctx.lineTo(hx, h)
                ctx.strokeStyle = "rgba(255,255,255,0.42)"
                ctx.lineWidth = 1
                ctx.stroke()
              }
            }
          }

          // Floating hover tooltip near cursor
          Rectangle {
            visible: root.flowHoverIdx >= 0 && root.flowHoverIdx < root.flowPoints.length
            x: Math.max(4, Math.min(parent.width - width - 4, root.flowMouseX - width * 0.5))
            y: Math.max(4, Math.min(parent.height - height - 26, root.flowMouseY - height - 12))
            width: flowTipTxt.implicitWidth + 18
            height: 26
            radius: 7
            color: root.tokens.popup || "#131318"
            border.width: 1
            border.color: root.tokens.lineStrong || Qt.rgba(1, 1, 1, 0.22)
            z: 10

            Text {
              textFormat: Text.PlainText
              id: flowTipTxt
              anchors.centerIn: parent
              text: {
                if (root.flowHoverIdx < 0 || root.flowHoverIdx >= root.flowPoints.length) return ""
                var fp = root.flowPoints[root.flowHoverIdx]
                var dLbl = fp.labelIso !== fp.endIso
                  ? (Theme.formatShortDay(fp.labelIso, root.lang) + " – " + Theme.formatShortDay(fp.endIso, root.lang))
                  : Theme.formatShortDay(fp.labelIso, root.lang)
                return dLbl + " · " + Theme.formatMinutes(fp.totalMinutes || 0, root.lang)
              }
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.tokens.ink || "#ffffff"
            }
          }

          // Bottom date ticks
          Text {
            textFormat: Text.PlainText
            anchors.left: parent.left
            anchors.bottom: parent.bottom
            text: root.days.length > 0 ? Theme.formatShortDay(root.days[0].day, root.lang) : ""
            font.family: root.fontFamily
            font.pixelSize: 10
            color: root.tokens.muted || "#777777"
          }

          Text {
            textFormat: Text.PlainText
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: root.days.length > 1 ? Theme.formatShortDay(root.days[root.days.length - 1].day, root.lang) : ""
            font.family: root.fontFamily
            font.pixelSize: 10
            color: root.tokens.muted || "#777777"
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onPositionChanged: function(mouse) {
              var n = root.flowPoints.length
              if (n <= 0) { root.flowHoverIdx = -1; return }
              root.flowMouseX = mouse.x
              root.flowMouseY = mouse.y
              var idx = Math.round((mouse.x / Math.max(1, width)) * (n - 1))
              root.flowHoverIdx = Math.max(0, Math.min(n - 1, idx))
            }
            onExited: root.flowHoverIdx = -1
            onClicked: {
              if (root.flowHoverIdx >= 0 && root.flowHoverIdx < root.flowPoints.length) {
                var raw = root.flowPoints[root.flowHoverIdx].rawDay
                if (raw) root.drawerDay = raw
              }
            }
          }
        }
      }

      // =======================================================================
      // CHART 3 · TIME MAP (06:00..24:00 Horizontal Session Blocks + Right Day Total)
      // =======================================================================
      Rectangle {
        visible: root.chartTab === 3
        width: parent.width
        height: tmCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: tmCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 8

          Item {
            visible: root.days.length > 31
            width: parent.width
            height: 16

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "Son 31 gün gösteriliyor", "Showing last 31 days")
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.muted || "#777777"
            }
          }

          // Hour header ticks (06, 09, 12, 15, 18, 21, 24)
          Item {
            width: parent.width
            height: 14

            Repeater {
              model: [6, 9, 12, 15, 18, 21, 24]
              delegate: Text {
                textFormat: Text.PlainText
                readonly property real plotW: tmCol.width - 64 - 64
                x: 64 + ((modelData - 6) / 18.0) * plotW - (modelData === 24 ? implicitWidth : 0)
                text: (modelData < 10 ? "0" + modelData : String(modelData))
                font.family: "Monospace"
                font.pixelSize: 9
                color: root.tokens.muted || "#777777"
              }
            }
          }

          Column {
            width: parent.width
            spacing: 4

            Repeater {
              model: root.timeMapDays.length
              delegate: Item {
                readonly property var tdObj: root.timeMapDays[index]
                readonly property var rowSessions: tdObj ? (tdObj.sessions || []) : []
                readonly property int rowMins: tdObj ? (Number(tdObj.totalMinutes) || 0) : 0
                width: tmCol.width
                height: 20

                Text {
                  textFormat: Text.PlainText
                  width: 58
                  anchors.verticalCenter: parent.verticalCenter
                  text: tdObj ? (Theme.weekdayShort(tdObj.weekday, root.lang) + " " + tdObj.dayNum) : ""
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  color: (tdObj && tdObj.day === root.todayIso) ? (root.tokens.ink || "#ffffff") : (root.tokens.muted || "#888888")
                }

                Rectangle {
                  id: rowTrack
                  x: 64
                  width: parent.width - 128
                  height: 15
                  anchors.verticalCenter: parent.verticalCenter
                  radius: 4
                  color: tmRowHov.containsMouse ? (root.tokens.raised || "#282830") : (root.tokens.card2 || "#1d1d22")
                  clip: true

                  Repeater {
                    model: rowSessions.length
                    delegate: Rectangle {
                      readonly property var rs: rowSessions[index]
                      readonly property real sh: Math.max(6.0, Math.min(24.0, Number(rs.startHourFrac) || 0))
                      readonly property real eh: Math.max(sh, Math.min(24.0, Number(rs.endHourFrac) || 0))
                      readonly property bool dimmed: root.hoveredCategoryId > 0 && root.hoveredCategoryId !== Number(rs.categoryId)
                      visible: eh > 6.0 && (eh - sh) > 0.01
                      x: ((sh - 6.0) / 18.0) * rowTrack.width
                      y: 2.5
                      width: Math.max(3, ((eh - sh) / 18.0) * rowTrack.width)
                      height: 10
                      radius: 2.5
                      color: rs.color || "#4c8df0"
                      opacity: dimmed ? 0.18 : 0.92
                    }
                  }
                }

                Text {
                  textFormat: Text.PlainText
                  anchors.right: parent.right
                  width: 58
                  horizontalAlignment: Text.AlignRight
                  anchors.verticalCenter: parent.verticalCenter
                  text: rowMins > 0 ? Theme.formatMinutesShort(rowMins, root.lang) : "—"
                  font.family: "Monospace"
                  font.pixelSize: 10
                  color: rowMins > 0 ? (root.tokens.secondary || "#bbbbbb") : (root.tokens.faint || "#555555")
                }

                MouseArea {
                  id: tmRowHov
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.drawerDay = tdObj
                }
              }
            }
          }
        }
      }

      // =======================================================================
      // FULL-WIDTH CATEGORIES BREAKDOWN (unfiltered list, barRatio bars, click to filter)
      // =======================================================================
      Rectangle {
        width: parent.width
        height: catBreakCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: catBreakCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 10

          Item {
            width: parent.width
            height: 18

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "KATEGORİLER", "CATEGORIES")
              font.family: root.fontFamily
              font.pixelSize: 10
              font.weight: Font.Bold
              font.letterSpacing: 1.1
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(
                root.lang,
                "Üzerine gel: grafikte vurgula · Tıkla: sayfayı filtrele",
                "Hover to highlight · Click to filter page"
              )
              font.family: root.fontFamily
              font.pixelSize: 10
              color: root.tokens.muted || "#777777"
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.catBreakdown.length === 0
            text: Theme.t(root.lang, "Bu dönemde oturum yok.", "No sessions in this period.")
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.tokens.muted || "#777777"
          }

          Repeater {
            model: root.catBreakdown.length
            delegate: Rectangle {
              readonly property var cb: root.catBreakdown[index]
              readonly property bool isFiltered: root.filterTopicId === Number(cb.categoryId)
              readonly property bool isDimmed: root.filterTopicId > 0 && !isFiltered
              readonly property real ratio: cb.barRatio !== undefined
                ? Math.max(0.0, Math.min(1.0, Number(cb.barRatio) || 0))
                : ((Number(cb.pct) || 0) / 100.0)
              width: catBreakCol.width
              height: 38
              radius: 8
              opacity: isDimmed ? 0.35 : 1.0
              color: isFiltered
                ? (root.tokens.raised || "#2b2b33")
                : (cbHover.hovered ? (root.tokens.card2 || "#1f1f25") : "transparent")

              Behavior on opacity { NumberAnimation { duration: 140 } }

              HoverHandler {
                id: cbHover
                onHoveredChanged: {
                  if (hovered) root.hoveredCategoryId = Number(cb.categoryId)
                  else if (root.hoveredCategoryId === Number(cb.categoryId)) root.hoveredCategoryId = 0
                }
              }

              Column {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                anchors.topMargin: 5
                spacing: 5

                Item {
                  width: parent.width
                  height: 18

                  Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    CategorySwatch {
                      swatchSize: 16
                      swatchColor: cb.color || "#4c8df0"
                      emoji: cb.emoji || ""
                      iconName: cb.icon || ""
                      iconColor: cb.iconColor || ""
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.verticalCenter: parent.verticalCenter
                      text: cb.name || ""
                      font.family: root.fontFamily
                      font.pixelSize: 12
                      font.weight: Font.Medium
                      color: root.tokens.ink || "#ffffff"
                    }
                  }

                  Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.formatMinutes(cb.minutes || 0, root.lang) + "   " + (cb.pct || 0) + "%"
                    font.family: "Monospace"
                    font.pixelSize: 11
                    color: root.tokens.secondary || "#bbbbbb"
                  }
                }

                Rectangle {
                  width: parent.width
                  height: 4
                  radius: 2
                  color: root.tokens.card2 || "#222228"

                  Rectangle {
                    visible: (cb.minutes || 0) > 0
                    width: Math.max(4, parent.width * ratio)
                    height: 4
                    radius: 2
                    color: cb.color || "#4c8df0"
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!root.service) return
                  var nextTopic = isFiltered ? 0 : Number(cb.categoryId)
                  root.service.setStatsRange(root.stats.rangeStart, root.stats.rangeEnd, nextTopic)
                }
              }
            }
          }
        }
      }

      // =======================================================================
      // FULL-WIDTH MOST PRODUCTIVE HOURS (24-cell horizontal heat-strip)
      // =======================================================================
      Rectangle {
        width: parent.width
        height: prodCol.implicitHeight + 32
        radius: 14
        color: root.tokens.card || "#17171c"
        border.width: 1
        border.color: root.tokens.line || Qt.rgba(1, 1, 1, 0.08)

        Column {
          id: prodCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 16
          spacing: 10

          Item {
            width: parent.width
            height: 18

            Text {
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: Theme.t(root.lang, "EN VERİMLİ SAATLER", "MOST PRODUCTIVE HOURS")
              font.family: root.fontFamily
              font.pixelSize: 10
              font.weight: Font.Bold
              font.letterSpacing: 1.1
              color: root.tokens.muted || "#888888"
            }

            Text {
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: {
                if (root.hoveredHour >= 0 && root.hoveredHour < root.hourly.length) {
                  var hh = root.hoveredHour < 10 ? ("0" + root.hoveredHour) : String(root.hoveredHour)
                  var nh = ((root.hoveredHour + 1) % 24)
                  var nhStr = nh < 10 ? ("0" + nh) : String(nh)
                  return hh + ":00 – " + nhStr + ":00 · " + Theme.formatMinutes(root.hourly[root.hoveredHour] || 0, root.lang)
                }
                var ph = Number(root.stats.peakHour)
                var pm = Number(root.stats.peakHourMinutes) || 0
                if (isNaN(ph) || ph < 0 || pm <= 0) {
                  return Theme.t(root.lang, "Oturumlar tamamlandıkça oluşur", "Builds as you complete sessions")
                }
                var phs = ph < 10 ? ("0" + ph) : String(ph)
                return Theme.t(root.lang, "Zirve: ", "Peak: ") + phs + ":00 (" + Theme.formatMinutes(pm, root.lang) + ")"
              }
              font.family: "Monospace"
              font.pixelSize: 11
              color: root.hoveredHour >= 0 ? (root.tokens.ink || "#ffffff") : (root.tokens.secondary || "#aaaaaa")
            }
          }

          // 24 horizontal heat-strip cells (matching stats_070.png / stats_140.png)
          Row {
            width: parent.width
            height: 32
            spacing: 4

            Repeater {
              model: 24
              delegate: Rectangle {
                readonly property int hMins: index < root.hourly.length ? (Number(root.hourly[index]) || 0) : 0
                readonly property int peakM: Math.max(15, Number(root.stats.peakHourMinutes) || 30)
                readonly property real ratio: hMins > 0 ? Math.min(1.0, hMins / peakM) : 0
                readonly property bool isHov: root.hoveredHour === index
                width: (prodCol.width - 23 * 4) / 24
                height: 32
                radius: 5
                border.width: isHov ? 1 : 0
                border.color: root.tokens.ink || "#ffffff"
                color: hMins === 0
                  ? Theme.withAlpha(root.tokens.ink || "#ffffff", 0.05)
                  : Theme.withAlpha(root.activeAccentColor, 0.22 + 0.76 * ratio)

                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  onEntered: root.hoveredHour = index
                  onExited: if (root.hoveredHour === index) root.hoveredHour = -1
                }
              }
            }
          }

          // 00 .. 03 .. 06 .. 09 .. 12 .. 15 .. 18 .. 21 .. 23 ticks
          Item {
            width: parent.width
            height: 14

            Repeater {
              model: [0, 3, 6, 9, 12, 15, 18, 21, 23]
              delegate: Text {
                textFormat: Text.PlainText
                x: modelData === 23
                  ? (parent.width - implicitWidth)
                  : ((modelData / 24.0) * parent.width)
                text: modelData < 10 ? ("0" + modelData) : String(modelData)
                font.family: "Monospace"
                font.pixelSize: 9
                color: root.tokens.muted || "#777777"
              }
            }
          }
        }
      }
    }
  }

  DayDrawer {
    id: dayDrawerItem
    dayData: root.drawerDay
    tokens: root.tokens
    lang: root.lang
    fontFamily: root.fontFamily
    onCloseRequested: root.drawerDay = null
    onStepDayRequested: function(delta) {
      root.stepDrawerDay(delta)
    }
    onDeleteSession: function(sid) {
      if (root.service) root.service.deleteSession(sid)
    }
    onOpenInSessions: function(dayIso) {
      root.drawerDay = null
      root.jumpToSessionsDay(dayIso)
    }
  }
}
