# Breathwork improvement tasks

Review date: 2026-09-27. The six P1/P2 fixes were implemented on 2026-09-27. The P3 design tasks remain open.

Priority: P1 = correctness or data protection; P2 = behavior and usability; P3 = architectural improvement.

## P1 — Correctness and data protection

- [x] **Add a release/exhale step after the Power Breathe recovery hold.**
  - Current behavior: `updatePowerSession()` immediately starts the next round or completes the session, without a release phase. The visual jumps from full to empty.
  - Add an explicit release state, visual transition, and phase cue before advancing or completing.
  - Verify both intermediate rounds and the final round, including a one-round session and progressive recovery holds.
  - Source: `BreathworkOverlay.qml`, `updatePowerSession()` and `powerBreathState()`.

- [x] **Fix duplicate IDs for long protocol names.**
  - Reproduced: saving two new protocols with the same 48-character name generates identical IDs; reloading retains only one.
  - Reserve space for the uniqueness suffix before truncating, or generate stable IDs independently of names.
  - Verify duplicate long names survive saving and reloading and can be edited/deleted independently. Cover punctuation, non-ASCII names, and renaming too.
  - Source: `BreathworkModel.js`, `cleanId()`, `uniqueProtocolId()`, and `saveProtocol()`.

- [x] **Make persistence atomic, serialized, and observable.**
  - Statistics currently overwrite the destination directly. Protocol writes share a fixed temporary filename, allowing overlapping writes to conflict.
  - Serialize writes, use safe atomic replacement, and report completion/failure to the UI. Show success only after a successful save.
  - Preserve recoverable data when a file cannot be read or parsed; avoid silently replacing it with an empty library on the next save.
  - Verify rapid consecutive saves, interrupted writes, invalid JSON, and write failures using isolated temporary files. Existing history and protocols must remain intact.
  - Source: `BreathworkModel.js`, validation helpers; `persist.py` and `JsonWriter.qml`; `BarWidget.qml`, persistence and FileView handlers.

## P2 — Behavior and usability

- [x] **Preserve fractional phase durations in the editor.**
  - Coherent breathing uses 5.5-second phases, but editor properties are integers, changing the timing when creating a personal version.
  - Support decimal durations consistently through controls, validation, saving, and playback.
  - Verify copying Coherent preserves 5.5 seconds for inhale and exhale after a save/reload cycle.
  - Source: `BarWidget.qml`, editor timing properties and NumberField controls; `BreathworkModel.js`, `timingFromPattern()`.

- [x] **Refresh the date used by daily statistics.**
  - `todayKey` has no reactive clock dependency, so a long-running widget can keep yesterday's date.
  - Refresh on panel opening and date changes; ensure today's total, streak, and weekly chart use the same date.
  - Verify midnight rollover without restarting the shell, including days with and without practice.
  - Source: `BarWidget.qml`, `todayKey` and statistics bindings.

- [x] **Improve immediate motion and animation smoothness.**
  - Visual updates occur every 100 ms. Half-cosine easing moves only about 0.15% during the first 100 ms of a four-second inhale, which can contribute to a perceived delay.
  - Separate smooth rendering from phase scheduling and tune the easing for perceptible motion from the start while preserving accurate durations.
  - Verify orb, rings, and bar at phase boundaries and immediately after preparation. Ensure audio cues occur once per transition and remain aligned with visuals.
  - Source: `BreathworkOverlay.qml`, FrameAnimation and visual bindings; `BreathworkModel.js`, `breathAt()`.

## P3 — Customization and architecture

- [ ] **Store complete named protocol presets.**
  - Currently preparation time, visuals, and audio choices are global, and Power Breathe cannot have multiple named variants.
  - Extend saved records to include protocol type, phases or round configuration, preparation time, visual style, and audio choices.
  - Define how preset values interact with global defaults and migrate existing records without losing names or timings.
  - Verify independently named Power Breathe variants and ordinary rhythms preserve their own settings across restarts.

- [ ] **Extract a separately testable session engine.**
  - Move phase progression out of the overlay into an engine with explicit states and transitions; let the UI render its output.
  - Centralize timing validation and phase events so visuals and audio share the same transition source.
  - Add deterministic tests for preparation, ordinary cycles, manual retention, recovery/release, round progression, increasing holds, cancellation, and completion.
  - Include delayed timer ticks and clock/suspend behavior; verify no duplicate cues or duplicate session logging.

## Suggested implementation order

1. Fix the missing release step, duplicate IDs, and persistence failures.
2. Preserve decimal timings and refresh daily statistics correctly.
3. Improve visual timing while maintaining phase/audio synchronization.
4. Extract the session engine and introduce complete presets with migration coverage.

For each implementation, mark the task complete only after its verification steps pass. Verification: model regression tests, temporary-file persistence tests, QML integration checks, and Omarchy manifest validation. Visual smoothness is implemented through frame updates and tested progression math; subjective feel still benefits from a real session.

## Follow-up correction: timed Power Breathe exhale holds

- [x] Apply the increasing hold schedule to the exhale retention, show a countdown, and advance automatically at its end. Keep an early-exit action and a separate constant recovery-hold setting.
  - Verified countdown values and transitions immediately before/at the boundary for all eight rounds (15, 25, 35, 45, 55, 65, 75, 85 seconds), plus early exit.
