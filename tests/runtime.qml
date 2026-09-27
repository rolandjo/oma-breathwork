import QtQuick
import Quickshell
import "plugin" as BW
import "plugin/BreathworkModel.js" as Model

ShellRoot {
  property int writesFinished: 0
  BW.DecimalField { id: decimal; value: 5.5; from: 1; to: 30 }
  BW.BreathworkOverlay {
    id: overlay
    property int completions: 0
    property int cues: 0
    function endSession(completed) { if (completed) completions++ }
    function phaseCue() { cues++ }
  }
  BW.BarWidget { id: widget }
  BW.JsonWriter {
    id: writer
    onFinished: function(ok, message, context) {
      if (context.expectFailure) {
        if (ok || message.indexOf("Unknown storage operation") < 0) throw new Error("Save error was not reported")
      } else if (!ok) throw new Error(message)
      writesFinished++
      if (writesFinished === 3) {
        console.log("PASS QML editor precision, date refresh, release, cues, and persistence")
        Qt.quit()
      }
    }
  }
  Component.onCompleted: {
    if (decimal.value !== 5.5 || decimal.field.value !== 55) throw new Error("Decimal field lost precision")
    if (decimal.field.valueFromText(decimal.field.textFromValue(55, decimal.field.locale), decimal.field.locale) !== 55)
      throw new Error("Decimal roundtrip failed")
    widget.loadEditorFromPattern("sigh")
    if (widget.editorInhale !== 3 || widget.editorTopUp !== 1 || widget.editorExhale !== 6) throw new Error("Sigh editor lost a phase")
    overlay.pattern = Model.patternFromData(Model.pattern("sigh"))
    overlay.getReadySecs = 0
    overlay.startedAt = 1000
    overlay.nowMs = 1000
    overlay.phaseCuesWanted = true
    overlay.lastPhaseIndex = -999
    overlay.cueCurrentPhaseIfNeeded()
    overlay.nowMs = 4000
    overlay.cueCurrentPhaseIfNeeded()
    overlay.cueCurrentPhaseIfNeeded()
    if (overlay.breath.label !== "Top-up inhale" || overlay.breath.fullness !== 0.8) throw new Error("Sigh top-up visual failed")
    overlay.nowMs = 5000
    overlay.cueCurrentPhaseIfNeeded()
    if (overlay.cues !== 3 || overlay.breath.label !== "Breathe out") throw new Error("Sigh cues failed")
    overlay.startedAt = 0
    overlay.cues = 0
    widget.loadEditorFromPattern("coherent")
    if (widget.editorInhale !== 5.5 || widget.editorExhale !== 5.5) throw new Error("Editor lost decimals")
    widget.todayKey = "2000-01-01"
    widget.open()
    widget.close()
    if (widget.todayKey !== Qt.formatDateTime(new Date(), "yyyy-MM-dd")) throw new Error("Date did not refresh")
    overlay.phaseCuesWanted = false
    overlay.bellWanted = false
    overlay.dndWanted = false
    overlay.powerMode = true
    overlay.powerRetentionHoldSecs = 15
    overlay.powerRetentionIncreaseSecs = 10
    for (var round = 1; round <= 8; round++) {
      overlay.powerRound = round
      overlay.powerStage = "retention"
      overlay.powerStageStartedAt = 1000
      var duration = 15 + (round - 1) * 10
      overlay.nowMs = 1000
      if (overlay.centerText !== String(duration)) throw new Error("Wrong exhale countdown")
      overlay.nowMs = 1000 + duration * 1000 - 1
      overlay.updatePowerSession()
      if (overlay.powerStage !== "retention" || overlay.centerText !== "1") throw new Error("Exhale hold ended early")
      overlay.nowMs += 1
      overlay.updatePowerSession()
      if (overlay.powerStage !== "recoveryIn") throw new Error("Exhale hold did not end on time")
    }
    overlay.powerStage = "retention"
    overlay.beginPowerRecovery()
    if (overlay.powerStage !== "recoveryIn") throw new Error("Early exit failed")
    overlay.powerRounds = 2
    overlay.powerRound = 1
    overlay.powerStage = "recoveryHold"
    overlay.powerStageStartedAt = 1000
    overlay.nowMs = 11000
    overlay.updatePowerSession()
    if (overlay.powerStage !== "release" || overlay.breath.fullness !== 1) throw new Error("Missing release")
    overlay.nowMs = 12500
    overlay.updatePowerSession()
    if (overlay.powerStage !== "breathing" || overlay.powerRound !== 2) throw new Error("Round failed")
    overlay.powerRound = 2
    overlay.powerStage = "recoveryHold"
    overlay.powerStageStartedAt = 0
    overlay.nowMs = 10000
    overlay.updatePowerSession()
    if (overlay.powerStage !== "release" || overlay.completions !== 0) throw new Error("Completed before release")
    overlay.nowMs = 11500
    overlay.updatePowerSession()
    if (overlay.completions !== 1) throw new Error("Final release failed")
    overlay.phaseCuesWanted = true
    overlay.lastPhaseIndex = -999
    overlay.cueCurrentPhaseIfNeeded()
    overlay.cueCurrentPhaseIfNeeded()
    if (overlay.cues !== 1) throw new Error("Duplicate phase cue")
    var testPath = decodeURIComponent(Qt.resolvedUrl("history.json").toString().replace(/^file:\/\//, ""))
    writer.submit(testPath, "add-minutes", {day: "2026-09-27", minutes: 1})
    writer.submit(testPath, "invalid-operation", {}, {expectFailure: true})
    writer.submit(testPath, "add-minutes", {day: "2026-09-27", minutes: 1})
  }
  Timer { interval: 10000; running: true; onTriggered: { console.error("FAIL timed out"); Qt.quit() } }
}
