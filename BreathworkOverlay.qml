import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "BreathworkModel.js" as Model

// Fullscreen breathing pacer. A circle grows as you breathe in, holds, and
// shrinks as you breathe out, with the phase name and a countdown digit —
// visual pacing so the eyes can lead the breath and the mind has one thing
// to come back to.
//
// Summon with:
//   omarchy-shell shell summon oma.breathwork '{}'
//   omarchy-shell shell summon oma.breathwork '{"pattern": "478", "minutes": 5}'
// Patterns include box, 4-7-8, coherent, equal, extended exhale,
// triangle, and custom timings.
//
// Esc ends the session early; practice up to that point still counts.
Item {
  id: root

  // Injected by the shell's panel loader — omarchyPath must stay writable,
  // or the injection TypeError aborts onLoaded before registerPanelLoader
  // and every summon silently no-ops.
  property var shell: null
  property var manifest: null
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string statsPath: Quickshell.env("HOME") + "/.local/state/omarchy/breathwork/stats.json"

  property bool opened: false
  property string fontFamily: Style.font.menuFamily

  property var pattern: Model.pattern("box")
  property double startedAt: 0
  property int totalSecs: 600
  property int getReadySecs: 5
  property string visualStyle: "orb"
  property double nowMs: Date.now()
  property var stats: Model.parseStats("")

  // Power Breathe follows a round-based sequence rather than a fixed-length
  // repeating rhythm: 30 deep breaths, retention after exhale, then a full
  // recovery inhale held for 15 seconds.
  property bool powerMode: false
  property int powerRound: 1
  property int powerRounds: 3
  property int powerBreathsPerRound: 30
  property string powerStage: "breathing"
  property double powerStageStartedAt: 0
  readonly property double powerStageElapsed: Math.max(0, (nowMs - powerStageStartedAt) / 1000)
  property double powerBreathCycleSecs: 3
  property int powerRecoveryHoldSecs: 10
  property int powerRecoveryHoldIncreaseSecs: 5
  readonly property int powerCurrentRecoveryHoldSecs: powerRecoveryHoldSecs
    + (powerRound - 1) * powerRecoveryHoldIncreaseSecs

  // Session comforts, set per-summon via payload. DND is borrowed, not owned:
  // it engages only if it was off, and the previous state is restored.
  property bool bellWanted: true
  property bool phaseCuesWanted: true
  property bool dndWanted: true
  property bool dndApplied: false
  property int lastPhaseIndex: -1

  function notificationService() {
    return root.shell && typeof root.shell.serviceFor === "function"
      ? root.shell.serviceFor("omarchy.notifications") : null
  }

  function applyDnd() {
    if (!dndWanted || dndApplied) return
    var svc = notificationService()
    if (!svc || typeof svc.setDoNotDisturb !== "function") return
    if (svc.doNotDisturb === true) return
    svc.setDoNotDisturb(true)
    dndApplied = true
    Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.indicators", "refresh"])
  }

  function restoreDnd() {
    if (!dndApplied) return
    dndApplied = false
    var svc = notificationService()
    if (svc && typeof svc.setDoNotDisturb === "function") svc.setDoNotDisturb(false)
    Quickshell.execDetached(["omarchy-shell", "-q", "omarchy.indicators", "refresh"])
  }

  function ring(soundFile) {
    if (!bellWanted) return
    Quickshell.execDetached(Model.bellCommand("/usr/share/sounds/freedesktop/stereo/" + soundFile))
  }

  function phaseCue() {
    if (!phaseCuesWanted) return
    Quickshell.execDetached(Model.bellCommand(
      "/usr/share/sounds/freedesktop/stereo/audio-volume-change.oga"))
  }

  function cueCurrentPhaseIfNeeded() {
    if (!phaseCuesWanted) return
    var phaseIndex = Number(root.breath.phaseIndex)
    if (phaseIndex === root.lastPhaseIndex) return
    root.lastPhaseIndex = phaseIndex
    root.phaseCue()
  }

  function enterPowerStage(stage) {
    root.powerStage = stage
    root.powerStageStartedAt = root.nowMs
    root.lastPhaseIndex = -999
  }

  function beginPowerRecovery() {
    if (!root.powerMode || root.gettingReady || root.powerStage !== "retention") return
    root.enterPowerStage("recoveryIn")
  }

  function updatePowerSession() {
    if (!root.powerMode || root.gettingReady) return
    if (root.powerStage === "breathing"
        && root.powerStageElapsed >= root.powerBreathsPerRound * root.powerBreathCycleSecs) {
      root.enterPowerStage("retention")
    } else if (root.powerStage === "recoveryIn"
               && root.powerStageElapsed >= root.powerBreathCycleSecs / 2) {
      root.enterPowerStage("recoveryHold")
    } else if (root.powerStage === "recoveryHold"
               && root.powerStageElapsed >= root.powerCurrentRecoveryHoldSecs) {
      if (root.powerRound >= root.powerRounds) root.endSession(true)
      else {
        root.powerRound += 1
        root.enterPowerStage("breathing")
      }
    }
  }

  function powerBreathState() {
    if (root.powerStage === "breathing") {
      var state = Model.breathAt(root.pattern, root.powerStageElapsed)
      var number = Math.min(root.powerBreathsPerRound,
        Math.floor(root.powerStageElapsed / root.powerBreathCycleSecs) + 1)
      return {
        phaseIndex: state.phaseIndex,
        label: (state.phaseIndex === 0 ? "Deep breath in" : "Let go")
          + " · " + number + "/" + root.powerBreathsPerRound,
        secsLeft: state.secsLeft,
        fullness: state.fullness
      }
    }
    if (root.powerStage === "retention")
      return { phaseIndex: 100, label: "Hold after exhale", secsLeft: 0, fullness: 0 }
    if (root.powerStage === "recoveryIn") {
      var recoveryInSecs = root.powerBreathCycleSecs / 2
      var x = Math.min(1, root.powerStageElapsed / recoveryInSecs)
      var eased = 0.5 - 0.5 * Math.cos(Math.PI * x)
      return {
        phaseIndex: 101,
        label: "Recovery breath in",
        secsLeft: Math.max(1, Math.ceil(recoveryInSecs - root.powerStageElapsed)),
        fullness: eased
      }
    }
    return {
      phaseIndex: 102,
      label: "Hold recovery breath",
      secsLeft: Math.max(0, Math.ceil(root.powerCurrentRecoveryHoldSecs - root.powerStageElapsed)),
      fullness: 1
    }
  }

  readonly property double sessionElapsedSecs: startedAt > 0 ? Math.max(0, (nowMs - startedAt) / 1000) : 0
  readonly property bool gettingReady: startedAt > 0 && sessionElapsedSecs < getReadySecs
  readonly property double readyRemainingSecs: Math.max(0, getReadySecs - sessionElapsedSecs)
  readonly property double elapsedSecs: Math.max(0, sessionElapsedSecs - getReadySecs)
  readonly property double remainingSecs: Math.max(0, totalSecs - elapsedSecs)
  readonly property var breath: gettingReady
    ? ({ phaseIndex: -1, label: "Get ready", secsLeft: Math.ceil(readyRemainingSecs), fullness: 0 })
    : (powerMode ? powerBreathState() : Model.breathAt(pattern, elapsedSecs))
  readonly property string centerText: powerMode && !gettingReady && powerStage === "retention"
    ? Model.formatRemaining(Math.floor(powerStageElapsed)) : String(breath.secsLeft)

  property color foreground: Color.menu.text
  readonly property color dim: Qt.darker(foreground, 1.55)

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    if (payload.fontFamily) root.fontFamily = payload.fontFamily

    root.pattern = Model.pattern(payload.pattern, payload)
    root.powerMode = root.pattern.key === "power"
    var powerRounds = Number(payload.powerRounds)
    if (!isFinite(powerRounds)) powerRounds = 3
    root.powerRounds = Math.max(1, Math.min(20, Math.round(powerRounds)))
    var powerBreaths = Number(payload.powerBreaths)
    if (!isFinite(powerBreaths)) powerBreaths = 30
    root.powerBreathsPerRound = Math.max(30, Math.min(40, Math.round(powerBreaths)))
    var powerPace = Number(payload.powerBreathSeconds)
    if (!isFinite(powerPace)) powerPace = 3
    root.powerBreathCycleSecs = Math.max(2, Math.min(5, powerPace))
    var recoveryHold = Number(payload.powerRecoveryHold)
    if (!isFinite(recoveryHold)) recoveryHold = 10
    root.powerRecoveryHoldSecs = Math.max(5, Math.min(30, Math.round(recoveryHold)))
    var recoveryIncrease = Number(payload.powerRecoveryIncrease)
    if (!isFinite(recoveryIncrease)) recoveryIncrease = 5
    root.powerRecoveryHoldIncreaseSecs = Math.max(0, Math.min(15, Math.round(recoveryIncrease)))
    if (root.powerMode) {
      root.pattern = {
        key: "power",
        name: "Power Breathe",
        hint: root.powerRounds + " rounds · " + root.powerBreathsPerRound + " deep breaths",
        phases: [
          { label: "Deep breath in", secs: root.powerBreathCycleSecs / 2, to: 1 },
          { label: "Let go", secs: root.powerBreathCycleSecs / 2, to: 0 }
        ]
      }
    }
    var minutes = Number(payload.minutes)
    if (!isFinite(minutes) || minutes <= 0) minutes = 10
    root.totalSecs = Math.max(10, Math.round(minutes * 60))
    var ready = Number(payload.getReadySeconds)
    if (!isFinite(ready)) ready = 5
    root.getReadySecs = Math.max(0, Math.min(30, Math.round(ready)))
    var visual = String(payload.visualStyle || "orb")
    root.visualStyle = visual === "rings" || visual === "bar" ? visual : "orb"
    root.bellWanted = payload.bell !== false
    root.phaseCuesWanted = payload.phaseCues !== false
    root.dndWanted = payload.dnd !== false

    root.nowMs = Date.now()
    root.startedAt = root.nowMs
    root.powerRound = 1
    root.powerStage = "breathing"
    root.powerStageStartedAt = root.startedAt + root.getReadySecs * 1000
    root.lastPhaseIndex = root.getReadySecs > 0 ? -1 : 0
    root.opened = true
    statsFile.reload()
    root.applyDnd()
    root.ring("bell.oga")
    // The session bell marks the get-ready phase (or the first inhale when
    // the countdown is disabled). Without it, use the ordinary phase cue.
    if (root.phaseCuesWanted) {
      if (!root.bellWanted) root.phaseCue()
    }
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
    root.restoreDnd()
  }

  function dismiss() {
    root.opened = false
    root.restoreDnd()
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "oma.breathwork")
  }

  function toggle() {
    if (root.opened) root.endSession(false)
    else root.open("{}")
  }

  // Ending early still logs the minutes actually practiced — a streak kept
  // by a short session beats one lost to perfectionism.
  function endSession(completed) {
    // DND back to the user's state before the completion notification, or
    // the bell we just rang announces a notification nobody sees.
    root.restoreDnd()
    var minutes = Math.floor(root.elapsedSecs / 60)
    if (completed) minutes = root.powerMode
      ? Math.max(1, Math.round(root.elapsedSecs / 60))
      : Math.max(1, Math.round(root.totalSecs / 60))
    if (minutes >= 1) {
      var today = Qt.formatDateTime(new Date(), "yyyy-MM-dd")
      root.stats = Model.addMinutes(root.stats, today, minutes)
      Quickshell.execDetached(Model.persistStatsCommand(root.statsPath, root.stats))
    }
    if (completed) {
      root.ring("complete.oga")
      var summary = Model.statsSummary(root.stats, Qt.formatDateTime(new Date(), "yyyy-MM-dd"))
      Quickshell.execDetached([
        root.omarchyPath + "/bin/omarchy-notification-send",
        "Session complete",
        minutes + " min of " + root.pattern.name.toLowerCase() + " — " + summary
      ])
    }
    root.startedAt = 0
    root.dismiss()
  }

  FileView {
    id: statsFile
    path: root.statsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.stats = Model.parseStats(text())
    onFileChanged: reload()
    onLoadFailed: root.stats = Model.parseStats("")
  }

  Timer {
    interval: 100
    running: root.opened && root.startedAt > 0
    repeat: true
    onTriggered: {
      root.nowMs = Date.now()
      if (root.powerMode) root.updatePowerSession()
      else if (root.remainingSecs <= 0) root.endSession(true)
      if (root.opened) root.cueCurrentPhaseIfNeeded()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "oma-breathwork"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore

    readonly property real circleMax: Math.min(width, height) * 0.38
    readonly property real circleMin: circleMax * 0.42
    readonly property real circleSize: circleMin + (circleMax - circleMin) * root.breath.fullness

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    // The desktop fully gone: a breathing pacer over readable terminals is
    // just another notification fighting for attention.
    Rectangle {
      anchors.fill: parent
      color: Color.menu.background
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) {
          root.endSession(false)
          event.accepted = true
        } else if (root.powerMode && !root.gettingReady && root.powerStage === "retention"
                   && (event.key === Qt.Key_Space || event.key === Qt.Key_Return
                       || event.key === Qt.Key_Enter)) {
          root.beginPowerRecovery()
          event.accepted = true
        }
      }
    }

    // Fixed-size stage for the breathing circle so the labels below never
    // move as it grows and shrinks — a bobbing layout would defeat the calm.
    Column {
      anchors.centerIn: parent
      spacing: Style.space(28)

      Item {
        width: panel.circleMax
        height: panel.circleMax
        anchors.horizontalCenter: parent.horizontalCenter

        Item {
          anchors.fill: parent
          visible: root.visualStyle === "orb"

          // Halo: a faint outer ring at full inhale size, the target the
          // breath is growing toward.
          Rectangle {
            anchors.centerIn: parent
            width: panel.circleMax
            height: panel.circleMax
            radius: width / 2
            color: "transparent"
            border.color: root.dim
            border.width: 1
            opacity: 0.35
          }

          Rectangle {
            anchors.centerIn: parent
            width: panel.circleSize
            height: panel.circleSize
            radius: width / 2
            color: Qt.alpha(Color.accent, 0.25)
            border.color: Color.accent
            border.width: 2
          }
        }

        Item {
          anchors.fill: parent
          visible: root.visualStyle === "rings"

          Repeater {
            model: 3

            Rectangle {
              required property int index
              readonly property real inset: index * panel.circleMax * 0.055
              anchors.centerIn: parent
              width: Math.max(panel.circleMin * 0.64, panel.circleSize - inset * 2)
              height: width
              radius: width / 2
              color: index === 2 ? Qt.alpha(Color.accent, 0.08) : "transparent"
              border.color: Color.accent
              border.width: index === 0 ? 3 : 1.5
              opacity: 0.9 - index * 0.2
            }
          }

          Rectangle {
            anchors.centerIn: parent
            width: panel.circleMax
            height: panel.circleMax
            radius: width / 2
            color: "transparent"
            border.color: root.dim
            border.width: 1
            opacity: 0.25
          }
        }

        Item {
          anchors.centerIn: parent
          width: panel.circleMax * 0.32
          height: panel.circleMax
          visible: root.visualStyle === "bar"

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "transparent"
            border.color: root.dim
            border.width: 1
            opacity: 0.55
          }

          Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Style.space(5)
            width: parent.width - Style.space(10)
            height: width + (parent.height - Style.space(10) - width) * root.breath.fullness
            radius: width / 2
            color: Qt.alpha(Color.accent, 0.28)
            border.color: Color.accent
            border.width: 2
          }
        }

        Text {
          anchors.centerIn: parent
          text: root.centerText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Math.round(panel.circleMin * 0.32)
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.breath.label
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
      }

      Button {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root.powerMode && !root.gettingReady && root.powerStage === "retention"
        text: "Take recovery breath"
        bordered: true
        foreground: Color.accent
        fontFamily: root.fontFamily
        onClicked: root.beginPowerRecovery()
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: {
          if (root.gettingReady && root.powerMode)
            return "Sit or lie down · never practice near water or while driving"
          if (root.gettingReady)
            return root.pattern.name + " · starts after countdown · Esc to end"
          if (!root.powerMode)
            return root.pattern.name + " · " + Model.formatRemaining(root.remainingSecs) + " left · Esc to end"
          if (root.powerStage === "breathing")
            return "Round " + root.powerRound + "/" + root.powerRounds + " · breathe fully in, let go without force"
          if (root.powerStage === "retention")
            return "Round " + root.powerRound + "/" + root.powerRounds
              + " · hold only until the urge to breathe · Space/Enter to continue"
          return "Round " + root.powerRound + "/" + root.powerRounds + " · recovery breath · "
            + root.powerCurrentRecoveryHoldSecs + " sec hold"
        }
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
