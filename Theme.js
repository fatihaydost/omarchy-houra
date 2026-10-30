.pragma library

// Bilingual strings, CIE L* contrast math, formatting, and adaptive
// Omarchy + Houra Classic monochrome color tokens.

var palette = [
  "#e5675c", "#e8894a", "#e6b450", "#dccf6e", "#93c46c",
  "#4fbf95", "#4bb3c9", "#4c8df0", "#6f7cf2", "#9a7bea",
  "#de7ab2", "#c98f73", "#a0a3ad", "#e9e9ee", "#3a3f4d"
]

var emojis = [
  "🎬", "🎥", "✍️", "📝", "📚", "📖", "🎓", "🧠", "🔬", "🧪", "🧬", "💡", "🎯",
  "🚀", "💼", "🤝", "📈", "📊", "💰", "🏦", "🛒", "🏠", "🚗", "✈️", "🏋️", "🏃",
  "🧘", "🕌", "🤲", "☕", "🍳", "🎮", "🎸", "🎧", "🎨", "📷", "💻", "⌨️", "🖥️",
  "📱", "🌍", "🗣️", "📞", "✉️", "🗓️", "⏰", "🔥", "⭐", "❤️", "🌱", "🐾", "👶"
]

var statsAccent = "#3d8cff"

function t(lang, trText, enText) {
  return lang === "tr" ? trText : enText
}

function todoEmoji(state) {
  var s = Number(state) || 0
  if (s === 1) return "🙂‍↔️"
  if (s === 2) return "🥳"
  return "🤓"
}

function todoLabel(state, lang) {
  var s = Number(state) || 0
  if (s === 1) return t(lang, "Şu an", "Doing")
  if (s === 2) return t(lang, "Bitti", "Done")
  return t(lang, "Bekliyor", "Waiting")
}

function parseHexRgb(hexStr) {
  var s = String(hexStr || "").trim()
  if (s.charAt(0) === "#") s = s.slice(1)
  if (s.length === 3) {
    s = s.charAt(0) + s.charAt(0) + s.charAt(1) + s.charAt(1) + s.charAt(2) + s.charAt(2)
  }
  if (s.length < 6) return { r: 76, g: 141, b: 240 }
  var r = parseInt(s.substr(0, 2), 16)
  var g = parseInt(s.substr(2, 2), 16)
  var b = parseInt(s.substr(4, 2), 16)
  if (isNaN(r) || isNaN(g) || isNaN(b)) return { r: 76, g: 141, b: 240 }
  return { r: r, g: g, b: b }
}

function srgbToLinear(c255) {
  var c = c255 / 255.0
  return c <= 0.04045 ? (c / 12.92) : Math.pow((c + 0.055) / 1.055, 2.4)
}

function lightness(hexStr) {
  var rgb = parseHexRgb(hexStr)
  var y = 0.2126 * srgbToLinear(rgb.r) + 0.7152 * srgbToLinear(rgb.g) + 0.0722 * srgbToLinear(rgb.b)
  var yr = y
  var l = yr > 0.008856 ? (116.0 * Math.pow(yr, 1.0 / 3.0) - 16.0) : (903.3 * yr)
  return Math.max(0, Math.min(100, l))
}

function inkOn(hexStr) {
  return lightness(hexStr) > 66 ? "#000000" : "#ffffff"
}

function withAlpha(colorVal, a) {
  var alpha = Math.max(0, Math.min(1, Number(a)))
  if (typeof colorVal === "object" && colorVal !== null && colorVal.r !== undefined) {
    return Qt.rgba(colorVal.r, colorVal.g, colorVal.b, alpha)
  }
  var rgb = parseHexRgb(String(colorVal || "#ffffff"))
  return Qt.rgba(rgb.r / 255.0, rgb.g / 255.0, rgb.b / 255.0, alpha)
}

function mixColors(cA, cB, tRatio) {
  var a = (typeof cA === "object" && cA !== null && cA.r !== undefined)
    ? { r: cA.r, g: cA.g, b: cA.b }
    : (function() { var p = parseHexRgb(cA); return { r: p.r / 255, g: p.g / 255, b: p.b / 255 } })()
  var b = (typeof cB === "object" && cB !== null && cB.r !== undefined)
    ? { r: cB.r, g: cB.g, b: cB.b }
    : (function() { var p = parseHexRgb(cB); return { r: p.r / 255, g: p.g / 255, b: p.b / 255 } })()
  var k = Math.max(0, Math.min(1, Number(tRatio)))
  return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1.0)
}

function formatClock(totalSeconds) {
  var s = Math.max(0, Math.floor(Number(totalSeconds) || 0))
  var mins = Math.floor(s / 60)
  var secs = s % 60
  var mm = mins < 10 ? ("0" + mins) : String(mins)
  var ss = secs < 10 ? ("0" + secs) : String(secs)
  return mm + ":" + ss
}

function formatMinutes(totalMins, lang) {
  var m = Math.max(0, Math.floor(Number(totalMins) || 0))
  var h = Math.floor(m / 60)
  var rem = m % 60
  if (h === 0) return m + " " + t(lang, "dk", "min")
  var remPad = rem < 10 ? ("0" + rem) : String(rem)
  return h + " " + t(lang, "sa", "h") + " " + remPad + " " + t(lang, "dk", "min")
}

function formatMinutesShort(totalMins, lang) {
  var m = Math.max(0, Math.floor(Number(totalMins) || 0))
  var h = Math.floor(m / 60)
  var rem = m % 60
  if (h === 0) return m + t(lang, "d", "m")
  var remPad = rem < 10 ? ("0" + rem) : String(rem)
  return h + t(lang, "s", "h") + " " + remPad + t(lang, "d", "m")
}

function formatRhythm(workMin, restMin, lang) {
  var w = Number(workMin) || 0
  var r = Number(restMin) || 0
  if (w <= 0) return t(lang, "serbest", "free")
  return w + " + " + r
}

function formatHM(epochSec) {
  if (!epochSec) return "--:--"
  var d = new Date(Number(epochSec) * 1000)
  var hh = d.getHours()
  var mm = d.getMinutes()
  return (hh < 10 ? "0" + hh : String(hh)) + ":" + (mm < 10 ? "0" + mm : String(mm))
}

var _monthsEn = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var _monthsTr = ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"]
var _monthsFullEn = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
var _monthsFullTr = ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"]
var _weekdaysShortEn = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
var _weekdaysShortTr = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
var _weekdaysFullEn = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
var _weekdaysFullTr = ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]

function monthShort(m1to12, lang) {
  var idx = Math.max(0, Math.min(11, (Number(m1to12) || 1) - 1))
  return lang === "tr" ? _monthsTr[idx] : _monthsEn[idx]
}

function monthFull(m1to12, lang) {
  var idx = Math.max(0, Math.min(11, (Number(m1to12) || 1) - 1))
  return lang === "tr" ? _monthsFullTr[idx] : _monthsFullEn[idx]
}

function weekdayShort(iso1to7, lang) {
  var idx = Math.max(0, Math.min(6, (Number(iso1to7) || 1) - 1))
  return lang === "tr" ? _weekdaysShortTr[idx] : _weekdaysShortEn[idx]
}

function parseIsoDay(dayStr) {
  var parts = String(dayStr || "").split("-")
  if (parts.length !== 3) return new Date()
  return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
}

function toIsoDay(dateObj) {
  var y = dateObj.getFullYear()
  var m = dateObj.getMonth() + 1
  var d = dateObj.getDate()
  return y + "-" + (m < 10 ? "0" + m : String(m)) + "-" + (d < 10 ? "0" + d : String(d))
}

function addDaysIso(dayStr, deltaDays) {
  var d = parseIsoDay(dayStr)
  d.setDate(d.getDate() + Number(deltaDays))
  return toIsoDay(d)
}

function formatShortDay(dayStr, lang) {
  if (!dayStr) return "—"
  var d = parseIsoDay(dayStr)
  var m = d.getMonth() + 1
  var dom = d.getDate()
  return lang === "tr" ? (dom + " " + monthShort(m, "tr")) : (monthShort(m, "en") + " " + dom)
}

function formatDateRangeLabel(startStr, endStr, lang) {
  if (!startStr || !endStr) return "—"
  var ds = parseIsoDay(startStr)
  var de = parseIsoDay(endStr)
  var ys = ds.getFullYear()
  var ye = de.getFullYear()
  if (startStr === endStr) {
    return formatShortDay(startStr, lang) + (lang === "tr" ? (" " + ys) : (", " + ys))
  }
  if (ys === ye) {
    return formatShortDay(startStr, lang) + " – " + formatShortDay(endStr, lang) + (lang === "tr" ? (" " + ye) : (", " + ye))
  }
  var left = formatShortDay(startStr, lang) + (lang === "tr" ? (" " + ys) : (", " + ys))
  var right = formatShortDay(endStr, lang) + (lang === "tr" ? (" " + ye) : (", " + ye))
  return left + " – " + right
}

function formatStatsTitle(startStr, endStr, periodMode, lang) {
  if (!startStr || !endStr) return t(lang, "Bu hafta", "This week")
  var now = new Date()
  var ds = parseIsoDay(startStr)
  var de = parseIsoDay(endStr)
  if (periodMode === "week") {
    var wd = now.getDay() === 0 ? 7 : now.getDay()
    var curMon = new Date(now.getFullYear(), now.getMonth(), now.getDate() - (wd - 1))
    if (toIsoDay(curMon) === startStr) return t(lang, "Bu hafta", "This week")
    var prevMon = new Date(curMon.getFullYear(), curMon.getMonth(), curMon.getDate() - 7)
    if (toIsoDay(prevMon) === startStr) return t(lang, "Geçen hafta", "Last week")
    return formatShortDay(startStr, lang) + " – " + formatShortDay(endStr, lang)
  }
  if (periodMode === "month") {
    if (ds.getFullYear() === now.getFullYear() && ds.getMonth() === now.getMonth()) {
      return t(lang, "Bu ay", "This month")
    }
    return monthFull(ds.getMonth() + 1, lang) + " " + ds.getFullYear()
  }
  if (periodMode === "year") {
    return String(ds.getFullYear())
  }
  var span = Math.max(1, Math.round((de.getTime() - ds.getTime()) / 86400000) + 1)
  return span + " " + t(lang, "gün", span === 1 ? "day" : "days")
}

function formatDayHeading(dayStr, lang) {
  if (!dayStr) return ""
  var todayStr = toIsoDay(new Date())
  var yest = addDaysIso(todayStr, -1)
  var d = parseIsoDay(dayStr)
  var wd = lang === "tr" ? _weekdaysFullTr[d.getDay()] : _weekdaysFullEn[d.getDay()]
  var base = lang === "tr"
    ? (d.getDate() + " " + monthFull(d.getMonth() + 1, "tr") + " · " + wd)
    : (wd + ", " + monthShort(d.getMonth() + 1, "en") + " " + d.getDate())
  if (dayStr === todayStr) return t(lang, "Bugün", "Today") + " — " + base
  if (dayStr === yest) return t(lang, "Dün", "Yesterday") + " — " + base
  return base
}

function formatTodayEyebrow(lang) {
  var d = new Date()
  var wd = lang === "tr" ? _weekdaysFullTr[d.getDay()] : _weekdaysFullEn[d.getDay()]
  var ds = lang === "tr"
    ? (d.getDate() + " " + monthFull(d.getMonth() + 1, "tr") + " " + wd)
    : (wd + ", " + monthFull(d.getMonth() + 1, "en") + " " + d.getDate())
  return (t(lang, "BUGÜN", "TODAY") + " · " + ds).toUpperCase()
}

function priorityColor(prio, fallbackCol) {
  var p = Number(prio) || 1
  if (p >= 4) return "#e44332"
  if (p === 3) return "#eb8909"
  if (p === 2) return "#4c8df0"
  return fallbackCol || "#8a8d96"
}

function priorityLabel(prio) {
  var p = Math.max(1, Math.min(4, Number(prio) || 1))
  return "P" + String(5 - p)
}

function weekBoundsIso(dayStr) {
  var d = dayStr ? parseIsoDay(dayStr) : new Date()
  var wd = (d.getDay() + 6) % 7 // 0=Mon .. 6=Sun
  var mon = new Date(d.getFullYear(), d.getMonth(), d.getDate() - wd)
  var sun = new Date(mon.getFullYear(), mon.getMonth(), mon.getDate() + 6)
  return { start: toIsoDay(mon), end: toIsoDay(sun) }
}

function monthBoundsIso(dayStr) {
  var d = dayStr ? parseIsoDay(dayStr) : new Date()
  var first = new Date(d.getFullYear(), d.getMonth(), 1)
  var last = new Date(d.getFullYear(), d.getMonth() + 1, 0)
  return { start: toIsoDay(first), end: toIsoDay(last) }
}

function shiftMonthFirstIso(dayStr, deltaMonths) {
  var d = dayStr ? parseIsoDay(dayStr) : new Date()
  var shifted = new Date(d.getFullYear(), d.getMonth() + (Number(deltaMonths) || 0), 1)
  return toIsoDay(shifted)
}

function scopeShortLabel(scope, lang) {
  var s = String(scope || "day")
  if (s === "week") return t(lang, "Hafta", "Week")
  if (s === "month") return t(lang, "Ay", "Month")
  if (s === "range") return t(lang, "Aralık", "Range")
  if (s === "inbox") return t(lang, "Tarihsiz", "Undated")
  return t(lang, "Gün", "Day")
}

function resolveTokens(themeMode, omarchyBg, omarchyFg, omarchyAccent, omarchyUrgent) {
  if (themeMode === "classic") {
    return {
      win: Qt.rgba(14 / 255, 14 / 255, 16 / 255, 1),
      sidebar: Qt.rgba(10 / 255, 10 / 255, 12 / 255, 1),
      card: Qt.rgba(23 / 255, 23 / 255, 27 / 255, 1),
      card2: Qt.rgba(30 / 255, 30 / 255, 35 / 255, 1),
      raised: Qt.rgba(38 / 255, 38 / 255, 45 / 255, 1),
      popup: Qt.rgba(16 / 255, 16 / 255, 19 / 255, 0.97),
      line: Qt.rgba(1, 1, 1, 0.08),
      lineStrong: Qt.rgba(1, 1, 1, 0.16),
      ink: Qt.rgba(1, 1, 1, 1),
      secondary: Qt.rgba(1, 1, 1, 0.68),
      muted: Qt.rgba(1, 1, 1, 0.44),
      faint: Qt.rgba(1, 1, 1, 0.20),
      primaryBg: Qt.rgba(1, 1, 1, 1),
      primaryInk: Qt.rgba(10 / 255, 10 / 255, 12 / 255, 1),
      accent: Qt.rgba(1, 1, 1, 1),
      danger: Qt.rgba(224 / 255, 100 / 255, 88 / 255, 1),
      radius: 12,
      radiusSm: 8
    }
  }

  var bg = omarchyBg || Qt.rgba(16 / 255, 19 / 255, 21 / 255, 1)
  var fg = omarchyFg || Qt.rgba(202 / 255, 204 / 255, 204 / 255, 1)
  var acc = omarchyAccent || fg
  var urg = omarchyUrgent || Qt.rgba(224 / 255, 100 / 255, 88 / 255, 1)

  var bgLum = 0.2126 * bg.r + 0.7152 * bg.g + 0.0722 * bg.b
  var isLight = bgLum > 0.5
  var sidebarCol = isLight ? mixColors(bg, fg, 0.03) : mixColors(bg, "#000000", 0.22)
  var cardCol = mixColors(bg, fg, isLight ? 0.045 : 0.055)
  var card2Col = mixColors(bg, fg, isLight ? 0.08 : 0.095)
  var raisedCol = mixColors(bg, fg, isLight ? 0.12 : 0.14)
  var accHex = "#" +
    ("0" + Math.round(acc.r * 255).toString(16)).slice(-2) +
    ("0" + Math.round(acc.g * 255).toString(16)).slice(-2) +
    ("0" + Math.round(acc.b * 255).toString(16)).slice(-2)
  var pInk = lightness(accHex) > 62 ? Qt.rgba(0.05, 0.06, 0.07, 1) : Qt.rgba(1, 1, 1, 1)

  return {
    win: Qt.rgba(bg.r, bg.g, bg.b, 1),
    sidebar: sidebarCol,
    card: cardCol,
    card2: card2Col,
    raised: raisedCol,
    popup: Qt.rgba(bg.r, bg.g, bg.b, 0.97),
    line: withAlpha(fg, isLight ? 0.12 : 0.10),
    lineStrong: withAlpha(fg, isLight ? 0.22 : 0.20),
    ink: Qt.rgba(fg.r, fg.g, fg.b, 1),
    secondary: withAlpha(fg, 0.72),
    muted: withAlpha(fg, 0.48),
    faint: withAlpha(fg, 0.22),
    primaryBg: Qt.rgba(acc.r, acc.g, acc.b, 1),
    primaryInk: pInk,
    accent: Qt.rgba(acc.r, acc.g, acc.b, 1),
    danger: Qt.rgba(urg.r, urg.g, urg.b, 1),
    radius: 10,
    radiusSm: 7
  }
}
