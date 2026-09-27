.pragma library

// Pure helpers for the personal breathing plugin: patterns, session math, and
// streak bookkeeping. No Qt imports — everything here is testable data-in
// data-out.

// Each phase: label shown to the breather, seconds it lasts, and where the
// circle should be at its end (0 = fully exhaled, 1 = fully inhaled).
var PATTERNS = {
  box: {
    key: "box",
    name: "Box breathing",
    hint: "4-4-4-4 — steady focus",
    phases: [
      { label: "Breathe in", secs: 4, to: 1 },
      { label: "Hold", secs: 4, to: 1 },
      { label: "Breathe out", secs: 4, to: 0 },
      { label: "Hold", secs: 4, to: 0 }
    ]
  },
  "478": {
    key: "478",
    name: "4-7-8",
    hint: "long exhale — wind down",
    phases: [
      { label: "Breathe in", secs: 4, to: 1 },
      { label: "Hold", secs: 7, to: 1 },
      { label: "Breathe out", secs: 8, to: 0 }
    ]
  },
  coherent: {
    key: "coherent",
    name: "Coherent",
    hint: "5.5 in, 5.5 out — balance",
    phases: [
      { label: "Breathe in", secs: 5.5, to: 1 },
      { label: "Breathe out", secs: 5.5, to: 0 }
    ]
  },
  equal: {
    key: "equal",
    name: "Equal breathing",
    hint: "4 in, 4 out — simple and steady",
    phases: [
      { label: "Breathe in", secs: 4, to: 1 },
      { label: "Breathe out", secs: 4, to: 0 }
    ]
  },
  extended: {
    key: "extended",
    name: "Extended exhale",
    hint: "4 in, 6 out — a slower exhale",
    phases: [
      { label: "Breathe in", secs: 4, to: 1 },
      { label: "Breathe out", secs: 6, to: 0 }
    ]
  },
  triangle: {
    key: "triangle",
    name: "Triangle breathing",
    hint: "4 in, 4 hold, 4 out",
    phases: [
      { label: "Breathe in", secs: 4, to: 1 },
      { label: "Hold", secs: 4, to: 1 },
      { label: "Breathe out", secs: 4, to: 0 }
    ]
  },
  power: {
    key: "power",
    name: "Power Breathe",
    hint: "3 rounds · 30 deep breaths · guided retention",
    phases: [
      { label: "Deep breath in", secs: 1.5, to: 1 },
      { label: "Let go", secs: 1.5, to: 0 }
    ]
  }
}

var PATTERN_ORDER = ["box", "478", "coherent", "equal", "extended", "triangle", "power", "custom"]

function boundedSeconds(value, fallback, minimum) {
  var n = Number(value)
  if (!isFinite(n)) n = fallback
  return Math.max(minimum, Math.min(30, n))
}

function phasesForTimings(inhale, holdIn, exhale, holdOut) {
  var phases = [{ label: "Breathe in", secs: boundedSeconds(inhale, 4, 1), to: 1 }]
  holdIn = boundedSeconds(holdIn, 0, 0)
  holdOut = boundedSeconds(holdOut, 0, 0)
  if (holdIn > 0) phases.push({ label: "Hold", secs: holdIn, to: 1 })
  phases.push({ label: "Breathe out", secs: boundedSeconds(exhale, 4, 1), to: 0 })
  if (holdOut > 0) phases.push({ label: "Hold", secs: holdOut, to: 0 })
  return phases
}

function customPattern(options) {
  options = options || {}
  var inhale = boundedSeconds(options.customIn, 4, 1)
  var holdIn = boundedSeconds(options.customHoldIn, 2, 0)
  var exhale = boundedSeconds(options.customOut, 6, 1)
  var holdOut = boundedSeconds(options.customHoldOut, 0, 0)
  return {
    key: "custom",
    name: "Custom",
    hint: inhale + "-" + holdIn + "-" + exhale + "-" + holdOut + " — your rhythm",
    phases: phasesForTimings(inhale, holdIn, exhale, holdOut)
  }
}

function cleanId(value) {
  return String(value || "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .substring(0, 48)
}

function cleanProtocolRecord(record) {
  if (!record) return null
  var name = String(record.name || "").trim()
  if (!name) return null
  var id = cleanId(record.id || name)
  if (!id) id = "protocol"
  return {
    id: id,
    name: name.substring(0, 60),
    inhale: boundedSeconds(record.inhale, 4, 1),
    holdIn: boundedSeconds(record.holdIn, 0, 0),
    exhale: boundedSeconds(record.exhale, 4, 1),
    holdOut: boundedSeconds(record.holdOut, 0, 0)
  }
}

function normalizeProtocolLibrary(value) {
  var source = value && Array.isArray(value.protocols) ? value.protocols : []
  var protocols = []
  var seen = {}
  for (var i = 0; i < source.length; i++) {
    var record = cleanProtocolRecord(source[i])
    if (!record || seen[record.id]) continue
    seen[record.id] = true
    protocols.push(record)
  }
  return { version: 1, protocols: protocols }
}

function parseProtocolLibrary(raw) {
  try { return normalizeProtocolLibrary(JSON.parse(raw || "{}")) }
  catch (e) { return { version: 1, protocols: [] } }
}

function savedProtocolKey(id) {
  return "saved:" + cleanId(id)
}

function recordPattern(record) {
  var clean = cleanProtocolRecord(record)
  if (!clean) return null
  return {
    key: savedProtocolKey(clean.id),
    name: clean.name,
    hint: clean.inhale + "-" + clean.holdIn + "-" + clean.exhale + "-" + clean.holdOut + " — saved",
    phases: phasesForTimings(clean.inhale, clean.holdIn, clean.exhale, clean.holdOut)
  }
}

function findProtocolRecord(library, key) {
  var id = String(key || "")
  if (id.indexOf("saved:") === 0) id = id.substring(6)
  var normalized = normalizeProtocolLibrary(library)
  for (var i = 0; i < normalized.protocols.length; i++)
    if (normalized.protocols[i].id === id) return normalized.protocols[i]
  return null
}

function patternFromData(data) {
  if (!data || !Array.isArray(data.phases) || data.phases.length < 2) return null
  var phases = []
  for (var i = 0; i < data.phases.length; i++) {
    var source = data.phases[i] || {}
    var secs = boundedSeconds(source.secs, 0, 0)
    if (secs <= 0) continue
    phases.push({
      label: String(source.label || (Number(source.to) >= 0.5 ? "Breathe in" : "Breathe out")),
      secs: secs,
      to: Number(source.to) >= 0.5 ? 1 : 0
    })
  }
  if (phases.length < 2) return null
  return {
    key: String(data.key || "saved"),
    name: String(data.name || "Saved protocol").substring(0, 60),
    hint: String(data.hint || "Saved protocol"),
    phases: phases
  }
}

function pattern(key, options, library) {
  if (options && options.patternData) {
    var supplied = patternFromData(options.patternData)
    if (supplied) return supplied
  }
  var normalized = String(key || "").toLowerCase()
  if (normalized === "custom") return customPattern(options)
  if (normalized.indexOf("saved:") === 0) {
    var saved = recordPattern(findProtocolRecord(library, normalized))
    if (saved) return saved
  }
  return PATTERNS[normalized] || PATTERNS.box
}

function protocolOptions(library, options) {
  var out = []
  for (var i = 0; i < PATTERN_ORDER.length; i++) out.push(pattern(PATTERN_ORDER[i], options, library))
  var normalized = normalizeProtocolLibrary(library)
  for (var j = 0; j < normalized.protocols.length; j++) out.push(recordPattern(normalized.protocols[j]))
  return out
}

function timingFromPattern(pat) {
  var timing = { inhale: 4, holdIn: 0, exhale: 4, holdOut: 0 }
  if (!pat || !Array.isArray(pat.phases)) return timing
  var exhaled = false
  for (var i = 0; i < pat.phases.length; i++) {
    var phase = pat.phases[i]
    if (phase.label === "Breathe in") timing.inhale = phase.secs
    else if (phase.label === "Breathe out") { timing.exhale = phase.secs; exhaled = true }
    else if (phase.label === "Hold" && exhaled) timing.holdOut = phase.secs
    else if (phase.label === "Hold") timing.holdIn = phase.secs
  }
  return timing
}

function uniqueProtocolId(name, protocols) {
  var base = cleanId(name) || "protocol"
  var id = base
  var suffix = 2
  var used = {}
  for (var i = 0; i < protocols.length; i++) used[protocols[i].id] = true
  while (used[id]) { id = base + "-" + suffix; suffix++ }
  return id
}

function saveProtocol(library, draft) {
  var normalized = normalizeProtocolLibrary(library)
  var name = String((draft && draft.name) || "").trim()
  if (!name) return { library: normalized, record: null, error: "Enter a protocol name" }
  var requestedId = cleanId(draft && draft.id)
  var existingIndex = -1
  for (var i = 0; i < normalized.protocols.length; i++)
    if (normalized.protocols[i].id === requestedId) existingIndex = i
  var id = existingIndex >= 0 ? requestedId : uniqueProtocolId(name, normalized.protocols)
  var record = cleanProtocolRecord({
    id: id,
    name: name,
    inhale: draft.inhale,
    holdIn: draft.holdIn,
    exhale: draft.exhale,
    holdOut: draft.holdOut
  })
  var next = normalized.protocols.slice(0)
  if (existingIndex >= 0) next[existingIndex] = record
  else next.push(record)
  return { library: { version: 1, protocols: next }, record: record, error: "" }
}

function removeProtocol(library, id) {
  var normalized = normalizeProtocolLibrary(library)
  var target = cleanId(id)
  var next = []
  for (var i = 0; i < normalized.protocols.length; i++)
    if (normalized.protocols[i].id !== target) next.push(normalized.protocols[i])
  return { version: 1, protocols: next }
}

function cycleSeconds(pat) {
  var total = 0
  for (var i = 0; i < pat.phases.length; i++) total += pat.phases[i].secs
  return total
}

// Where the breath is at `t` seconds into the cycle. Returns the phase, the
// seconds left in it (for the countdown digit), and the circle's fullness in
// [0, 1], eased with a half-cosine so movement starts and ends softly —
// linear motion reads as mechanical, breath is not.
function breathAt(pat, t) {
  var into = t % cycleSeconds(pat)
  var from = pat.phases[pat.phases.length - 1].to
  for (var i = 0; i < pat.phases.length; i++) {
    var ph = pat.phases[i]
    if (into < ph.secs) {
      var x = ph.secs > 0 ? into / ph.secs : 1
      var eased = 0.5 - 0.5 * Math.cos(Math.PI * x)
      return {
        phaseIndex: i,
        label: ph.label,
        secsLeft: Math.ceil(ph.secs - into),
        fullness: from + (ph.to - from) * eased
      }
    }
    into -= ph.secs
    from = ph.to
  }
  return { phaseIndex: 0, label: pat.phases[0].label, secsLeft: pat.phases[0].secs, fullness: from }
}

// ---- Session stats. Stored as {"days": {"2026-08-22": 10, ...}} minutes.

function parseStats(raw) {
  try {
    var parsed = JSON.parse(raw || "{}")
    if (parsed && typeof parsed.days === "object" && parsed.days !== null) return { days: parsed.days }
  } catch (e) {}
  return { days: {} }
}

function addMinutes(stats, dayKey, minutes) {
  var days = {}
  for (var k in stats.days) days[k] = stats.days[k]
  days[dayKey] = Math.round((Number(days[dayKey]) || 0) + minutes)
  return { days: days }
}

function dayKeyOffset(dayKey, offsetDays) {
  var parts = String(dayKey).split("-")
  var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]) + offsetDays)
  var m = d.getMonth() + 1
  var day = d.getDate()
  return d.getFullYear() + "-" + (m < 10 ? "0" : "") + m + "-" + (day < 10 ? "0" : "") + day
}

// Consecutive days with any practice, counting back from today — or from
// yesterday when today is still blank, so the streak isn't shown broken
// before the day is over.
function streakDays(stats, todayKey) {
  var start = (Number(stats.days[todayKey]) || 0) > 0 ? todayKey : dayKeyOffset(todayKey, -1)
  var streak = 0
  var cursor = start
  while ((Number(stats.days[cursor]) || 0) > 0) {
    streak++
    cursor = dayKeyOffset(cursor, -1)
  }
  return streak
}

function todayMinutes(stats, todayKey) {
  return Number(stats.days[todayKey]) || 0
}

function statsSummary(stats, todayKey) {
  var streak = streakDays(stats, todayKey)
  var today = todayMinutes(stats, todayKey)
  var parts = []
  if (streak > 0) parts.push(streak + "-day streak")
  if (today > 0) parts.push(today + " min today")
  return parts.length ? parts.join(" · ") : "No sessions yet"
}

// Last 7 days (oldest first) for the weekly practice view: single-letter
// weekday label, minutes practiced, and whether the column is today.
function weekSeries(stats, todayKey) {
  var letters = ["S", "M", "T", "W", "T", "F", "S"]
  var out = []
  for (var i = 6; i >= 0; i--) {
    var key = dayKeyOffset(todayKey, -i)
    var parts = key.split("-")
    var d = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    out.push({
      key: key,
      label: letters[d.getDay()],
      minutes: Number(stats.days[key]) || 0,
      isToday: i === 0
    })
  }
  return out
}

function weekTotal(series) {
  var total = 0
  for (var i = 0; i < series.length; i++) total += series[i].minutes
  return total
}

// Argv for playing a session bell; prefers pw-play (PipeWire) and falls back
// to paplay, exiting quietly when neither exists.
function bellCommand(soundFile) {
  return [
    "sh", "-c",
    'f="$1"; [ -f "$f" ] || exit 0; ' +
    'if command -v pw-play >/dev/null 2>&1; then exec pw-play "$f"; ' +
    'elif command -v paplay >/dev/null 2>&1; then exec paplay "$f"; fi',
    "sh", soundFile
  ]
}

// Argv for persisting the stats file; JSON travels as a positional arg so it
// is data to the shell, never syntax.
function persistStatsCommand(path, stats) {
  return [
    "sh", "-c",
    'mkdir -p "$(dirname "$1")" && printf %s "$2" > "$1"',
    "sh", path, JSON.stringify(stats)
  ]
}

function persistJsonCommand(path, value) {
  return [
    "sh", "-c",
    'mkdir -p "$(dirname "$1")" && tmp="$1.tmp" && printf %s "$2" > "$tmp" && mv "$tmp" "$1"',
    "sh", path, JSON.stringify(value)
  ]
}

function formatRemaining(totalSecs) {
  var s = Math.max(0, Math.round(totalSecs))
  var m = Math.floor(s / 60)
  var sec = s % 60
  return m + ":" + (sec < 10 ? "0" : "") + sec
}
