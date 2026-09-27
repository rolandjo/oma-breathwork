import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "BreathworkModel.js" as Model

// Personal breathing widget with a saved protocol library. The quick panel
// starts sessions; the settings panel creates and edits named rhythms.
Panel {
  id: root
  moduleName: "oma.breathwork"
  ipcTarget: "oma.breathwork"
  manageIpc: false

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/breathwork"
  readonly property string statsPath: statePath + "/stats.json"
  readonly property string protocolsPath: statePath + "/protocols.json"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  property var stats: Model.parseStats("")
  property var protocolLibrary: Model.parseProtocolLibrary("")
  readonly property string todayKey: Qt.formatDateTime(new Date(), "yyyy-MM-dd")
  readonly property string summary: Model.statsSummary(stats, todayKey)
  readonly property int streak: Model.streakDays(stats, todayKey)

  property string chosenPattern: String(setting("pattern", "box"))
  property int chosenMinutes: Number(setting("minutes", 10))
  readonly property int getReadySeconds: {
    var value = Number(setting("getReadySeconds", 5))
    return isFinite(value) ? Math.max(0, Math.min(30, Math.round(value))) : 5
  }
  readonly property var customConfig: ({
    customIn: Number(setting("customIn", 4)),
    customHoldIn: Number(setting("customHoldIn", 2)),
    customOut: Number(setting("customOut", 6)),
    customHoldOut: Number(setting("customHoldOut", 0))
  })
  readonly property var protocolOptions: Model.protocolOptions(protocolLibrary, customConfig)
  readonly property var minuteChoices: [3, 5, 10, 15, 20, 30]
  readonly property var visualChoices: [
    { key: "orb", name: "Orb" },
    { key: "rings", name: "Pulse rings" },
    { key: "bar", name: "Breath bar" }
  ]

  property bool settingsOpened: false
  property string editingProtocolId: ""
  property string editorName: ""
  property int editorInhale: 4
  property int editorHoldIn: 0
  property int editorExhale: 4
  property int editorHoldOut: 0
  property bool editingPowerProtocol: false
  property int editorPowerRounds: 3
  property int editorPowerBreaths: 30
  property int editorPowerBreathSeconds: 3
  property int editorPowerRecoveryHold: 10
  property int editorPowerRecoveryIncrease: 5
  property string settingsMessage: ""
  property bool deleteArmed: false

  function resolvedPattern(patternKey) {
    return Model.pattern(patternKey || root.chosenPattern, root.customConfig, root.protocolLibrary)
  }

  function powerHoldPlan(firstHold, increase, rounds) {
    var values = []
    for (var i = 0; i < rounds; i++) values.push(Number(firstHold) + i * Number(increase))
    return values.join(" / ")
  }

  function choose(patternKey, minutes) {
    chosenPattern = patternKey
    chosenMinutes = minutes
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.pattern = patternKey
    entry.minutes = minutes
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setBooleanSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var currentKey in root.settings)
      if (currentKey !== "id") entry[currentKey] = root.settings[currentKey]
    entry[key] = value
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setNumberSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var currentKey in root.settings)
      if (currentKey !== "id") entry[currentKey] = root.settings[currentKey]
    entry[key] = Number(value)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setStringSetting(key, value) {
    var entry = { id: root.moduleName }
    for (var currentKey in root.settings)
      if (currentKey !== "id") entry[currentKey] = root.settings[currentKey]
    entry[key] = String(value)
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function setSettingValues(values) {
    var entry = { id: root.moduleName }
    for (var currentKey in root.settings)
      if (currentKey !== "id") entry[currentKey] = root.settings[currentKey]
    for (var key in values) entry[key] = values[key]
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function startSession(patternKey, minutes) {
    var selected = root.resolvedPattern(patternKey || root.chosenPattern)
    var payload = JSON.stringify({
      pattern: selected.key,
      patternData: selected,
      minutes: minutes || root.chosenMinutes,
      getReadySeconds: root.getReadySeconds,
      visualStyle: String(setting("visualStyle", "orb")),
      bell: setting("bell", true) !== false,
      phaseCues: setting("phaseCues", true) !== false,
      dnd: setting("dnd", true) !== false,
      customIn: root.customConfig.customIn,
      customHoldIn: root.customConfig.customHoldIn,
      customOut: root.customConfig.customOut,
      customHoldOut: root.customConfig.customHoldOut,
      powerRounds: Number(setting("powerRounds", 3)),
      powerBreaths: Number(setting("powerBreaths", 30)),
      powerBreathSeconds: Number(setting("powerBreathSeconds", 3)),
      powerRecoveryHold: Number(setting("powerRecoveryHold", 10)),
      powerRecoveryIncrease: Number(setting("powerRecoveryIncrease", 5))
    })
    if (root.bar && root.bar.shell && typeof root.bar.shell.summon === "function")
      root.bar.shell.summon(root.moduleName, payload)
    else
      Quickshell.execDetached(["omarchy-shell", "shell", "summon", root.moduleName, payload])
    root.close()
    root.settingsOpened = false
  }

  function persistProtocolLibrary() {
    Quickshell.execDetached(Model.persistJsonCommand(root.protocolsPath, root.protocolLibrary))
  }

  function loadEditorFromPattern(patternKey) {
    root.editingPowerProtocol = String(patternKey) === "power"
    if (root.editingPowerProtocol) {
      root.editingProtocolId = ""
      root.editorName = "Power Breathe"
      root.editorPowerRounds = Number(root.setting("powerRounds", 3))
      root.editorPowerBreaths = Number(root.setting("powerBreaths", 30))
      root.editorPowerBreathSeconds = Number(root.setting("powerBreathSeconds", 3))
      root.editorPowerRecoveryHold = Number(root.setting("powerRecoveryHold", 10))
      root.editorPowerRecoveryIncrease = Number(root.setting("powerRecoveryIncrease", 5))
      root.settingsMessage = ""
      root.deleteArmed = false
      return
    }
    var record = Model.findProtocolRecord(root.protocolLibrary, patternKey)
    if (record) {
      root.editingProtocolId = record.id
      root.editorName = record.name
      root.editorInhale = record.inhale
      root.editorHoldIn = record.holdIn
      root.editorExhale = record.exhale
      root.editorHoldOut = record.holdOut
    } else {
      var pat = root.resolvedPattern(patternKey)
      var timing = Model.timingFromPattern(pat)
      root.editingProtocolId = ""
      root.editorName = ""
      root.editorInhale = timing.inhale
      root.editorHoldIn = timing.holdIn
      root.editorExhale = timing.exhale
      root.editorHoldOut = timing.holdOut
    }
    root.settingsMessage = ""
    root.deleteArmed = false
  }

  function openSettings() {
    root.close()
    root.settingsOpened = true
    protocolsFile.reload()
    root.loadEditorFromPattern(root.chosenPattern)
    if (!root.editingPowerProtocol)
      Qt.callLater(function() { protocolNameField.forceActiveFocus() })
  }

  function closeSettings(openMain) {
    root.settingsOpened = false
    root.deleteArmed = false
    if (openMain) Qt.callLater(function() { root.open() })
  }

  function editSavedProtocol(key) {
    root.loadEditorFromPattern(key)
    Qt.callLater(function() { protocolNameField.forceActiveFocus() })
  }

  function newProtocol() {
    root.loadEditorFromPattern(root.chosenPattern === "power" ? "box" : root.chosenPattern)
    root.editingPowerProtocol = false
    root.editingProtocolId = ""
    root.editorName = ""
    root.settingsMessage = ""
    Qt.callLater(function() { protocolNameField.forceActiveFocus() })
  }

  function savePowerEditor() {
    root.setSettingValues({
      powerRounds: root.editorPowerRounds,
      powerBreaths: root.editorPowerBreaths,
      powerBreathSeconds: root.editorPowerBreathSeconds,
      powerRecoveryHold: root.editorPowerRecoveryHold,
      powerRecoveryIncrease: root.editorPowerRecoveryIncrease
    })
    root.choose("power", root.chosenMinutes)
    root.settingsMessage = "Saved Power Breathe settings"
  }

  function saveEditor() {
    var result = Model.saveProtocol(root.protocolLibrary, {
      id: root.editingProtocolId,
      name: root.editorName,
      inhale: root.editorInhale,
      holdIn: root.editorHoldIn,
      exhale: root.editorExhale,
      holdOut: root.editorHoldOut
    })
    if (result.error) {
      root.settingsMessage = result.error
      protocolNameField.forceActiveFocus()
      return
    }
    root.protocolLibrary = result.library
    root.editingProtocolId = result.record.id
    root.editorName = result.record.name
    root.editorInhale = result.record.inhale
    root.editorHoldIn = result.record.holdIn
    root.editorExhale = result.record.exhale
    root.editorHoldOut = result.record.holdOut
    root.persistProtocolLibrary()
    root.choose(Model.savedProtocolKey(result.record.id), root.chosenMinutes)
    root.settingsMessage = "Saved and selected: " + result.record.name
    root.deleteArmed = false
  }

  function deleteEditor() {
    if (!root.editingProtocolId) return
    if (!root.deleteArmed) {
      root.deleteArmed = true
      root.settingsMessage = "Press delete again to confirm"
      return
    }
    var deletedKey = Model.savedProtocolKey(root.editingProtocolId)
    root.protocolLibrary = Model.removeProtocol(root.protocolLibrary, root.editingProtocolId)
    root.persistProtocolLibrary()
    if (root.chosenPattern === deletedKey) root.choose("box", root.chosenMinutes)
    root.newProtocol()
    root.settingsMessage = "Protocol deleted"
  }

  onOpenedChanged: if (opened) {
    statsFile.reload()
    protocolsFile.reload()
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

  FileView {
    id: protocolsFile
    path: root.protocolsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.protocolLibrary = Model.parseProtocolLibrary(text())
    onFileChanged: reload()
    onLoadFailed: root.protocolLibrary = Model.parseProtocolLibrary("")
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void { root.settingsOpened = false; root.open() }
    function close(): void { root.close(); root.settingsOpened = false }
    function show(): void { root.settingsOpened = false; root.open() }
    function hide(): void { root.close(); root.settingsOpened = false }
    function toggle(): void { root.settingsOpened = false; root.toggle() }
    function settings(): void { root.openSettings() }
    function start(pattern: string, minutes: string): string {
      var m = parseInt(minutes, 10)
      root.startSession(pattern || root.chosenPattern, isFinite(m) && m > 0 ? m : root.chosenMinutes)
      return "ok"
    }
    function status(): string {
      return JSON.stringify({
        streakDays: root.streak,
        todayMinutes: Model.todayMinutes(root.stats, root.todayKey),
        defaultPattern: root.chosenPattern,
        defaultMinutes: root.chosenMinutes,
        getReadySeconds: root.getReadySeconds,
        visualStyle: String(root.setting("visualStyle", "orb")),
        powerRounds: Number(root.setting("powerRounds", 3)),
        powerBreaths: Number(root.setting("powerBreaths", 30)),
        powerBreathSeconds: Number(root.setting("powerBreathSeconds", 3)),
        powerRecoveryHold: Number(root.setting("powerRecoveryHold", 10)),
        powerRecoveryIncrease: Number(root.setting("powerRecoveryIncrease", 5)),
        phaseCuesEnabled: root.setting("phaseCues", true) !== false,
        savedProtocols: root.protocolLibrary.protocols.length
      })
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    tooltipText: "Breathwork — " + root.summary

    iconComponent: Component {
      Item {
        Canvas {
          anchors.centerIn: parent
          width: Style.space(14)
          height: Style.space(14)

          readonly property color glyph: root.barForeground
          onGlyphChanged: requestPaint()

          onPaint: {
            var c = width / 2
            var r = c - 1.25
            if (r <= 0) return
            var ctx = getContext("2d")
            ctx.reset()

            // Build a monochrome yin-yang from positive and transparent shapes
            // so the mark follows the active bar foreground and background.
            ctx.fillStyle = glyph
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2, false)
            ctx.fill()

            ctx.globalCompositeOperation = "destination-out"
            ctx.fillRect(c, c - r - 1, r + 2, r * 2 + 2)

            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = glyph
            ctx.beginPath()
            ctx.arc(c, c - r / 2, r / 2, 0, Math.PI * 2, false)
            ctx.fill()

            ctx.globalCompositeOperation = "destination-out"
            ctx.beginPath()
            ctx.arc(c, c + r / 2, r / 2, 0, Math.PI * 2, false)
            ctx.fill()
            ctx.beginPath()
            ctx.arc(c, c - r / 2, Math.max(0.9, r * 0.13), 0, Math.PI * 2, false)
            ctx.fill()

            ctx.globalCompositeOperation = "source-over"
            ctx.fillStyle = glyph
            ctx.beginPath()
            ctx.arc(c, c + r / 2, Math.max(0.9, r * 0.13), 0, Math.PI * 2, false)
            ctx.fill()

            ctx.strokeStyle = glyph
            ctx.lineWidth = 1.1
            ctx.beginPath()
            ctx.arc(c, c, r, 0, Math.PI * 2, false)
            ctx.stroke()
          }
        }
      }
    }

    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.startSession(root.chosenPattern, root.chosenMinutes)
      else if (b === Qt.RightButton) root.openSettings()
      else if (root.settingsOpened) root.closeSettings(false)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(mainColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onCloseRequested: root.close()
      onReturnRequested: root.startSession(root.chosenPattern, root.chosenMinutes)
      onTextKey: function(text) {
        var k = String(text || "").toLowerCase()
        var number = parseInt(k, 10)
        if (isFinite(number) && number >= 1 && number <= Math.min(9, root.protocolOptions.length))
          root.choose(root.protocolOptions[number - 1].key, root.chosenMinutes)
        else if (k === "s" || k === " ") root.startSession(root.chosenPattern, root.chosenMinutes)
      }

      Flickable {
        id: mainScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: mainColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: mainColumn
          width: mainScroll.width
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Breathwork"
            meta: root.summary
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            id: weekView
            width: parent.width
            spacing: Style.space(4)

            readonly property var series: Model.weekSeries(root.stats, root.todayKey)
            readonly property int weekMax: {
              var max = 0
              for (var i = 0; i < series.length; i++) max = Math.max(max, series[i].minutes)
              return max
            }

            Text {
              text: "This week · " + Model.weekTotal(weekView.series) + " min"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            Row {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: weekView.series

                Column {
                  required property var modelData
                  readonly property real share: weekView.weekMax > 0 ? modelData.minutes / weekView.weekMax : 0
                  spacing: Style.space(3)

                  Item {
                    width: Style.space(18)
                    height: Style.space(34)

                    Rectangle {
                      anchors.bottom: parent.bottom
                      anchors.horizontalCenter: parent.horizontalCenter
                      width: Style.space(10)
                      height: Math.max(Style.space(2), Math.round(parent.height * share))
                      radius: Style.space(2)
                      color: modelData.isToday ? Color.accent : root.foreground
                      opacity: modelData.minutes > 0 ? (modelData.isToday ? 0.9 : 0.45) : 0.15
                    }
                  }

                  Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label
                    color: modelData.isToday ? root.foreground : root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }
                }
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)

            Repeater {
              model: root.protocolOptions

              Button {
                required property var modelData
                text: modelData.name
                tooltipText: modelData.hint
                bordered: true
                selected: root.chosenPattern === modelData.key
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.choose(modelData.key, root.chosenMinutes)
              }
            }
          }

          Text {
            width: parent.width
            visible: root.chosenPattern === "power"
            text: Number(root.setting("powerRounds", 3)) + " rounds · "
              + Number(root.setting("powerBreaths", 30)) + " deep breaths · retention at your pace · "
              + "recovery holds " + root.powerHoldPlan(root.setting("powerRecoveryHold", 10),
                root.setting("powerRecoveryIncrease", 5), root.setting("powerRounds", 3)) + " sec"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Flow {
            width: parent.width
            spacing: Style.space(6)
            visible: root.chosenPattern !== "power"

            Repeater {
              model: root.minuteChoices

              Button {
                required property int modelData
                text: modelData + " min"
                bordered: true
                selected: root.chosenMinutes === modelData
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.choose(root.chosenPattern, modelData)
              }
            }
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.chosenPattern === "power"
                ? "Begin " + Number(root.setting("powerRounds", 3)) + " rounds" : "Begin"
              bordered: true
              foreground: Color.accent
              fontFamily: root.fontFamily
              onClicked: root.startSession(root.chosenPattern, root.chosenMinutes)
            }

            Button {
              text: "Protocol settings"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.openSettings()
            }
          }

          Text {
            width: parent.width
            text: "1-" + Math.min(9, root.protocolOptions.length) + " protocol · Enter begin · Esc close"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  KeyboardPanel {
    id: settingsPanel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.settingsOpened
    focusTarget: settingsKeyCatcher
    contentWidth: settingsPanel.fittedContentWidth(Style.space(460))
    contentHeight: settingsPanel.fittedContentHeight(settingsColumn.implicitHeight, Style.space(650))

    PanelKeyCatcher {
      id: settingsKeyCatcher
      anchors.fill: parent
      blocked: protocolNameField.activeFocus
        || readyField.field.activeFocus || readyField.field.contentItem.activeFocus
        || inhaleField.field.activeFocus || inhaleField.field.contentItem.activeFocus
        || holdInField.field.activeFocus || holdInField.field.contentItem.activeFocus
        || exhaleField.field.activeFocus || exhaleField.field.contentItem.activeFocus
        || holdOutField.field.activeFocus || holdOutField.field.contentItem.activeFocus
        || powerRoundsField.field.activeFocus || powerRoundsField.field.contentItem.activeFocus
        || powerBreathsField.field.activeFocus || powerBreathsField.field.contentItem.activeFocus
        || powerPaceField.field.activeFocus || powerPaceField.field.contentItem.activeFocus
        || powerRecoveryField.field.activeFocus || powerRecoveryField.field.contentItem.activeFocus
        || powerRecoveryIncreaseField.field.activeFocus || powerRecoveryIncreaseField.field.contentItem.activeFocus

      onCloseRequested: root.closeSettings(false)

      Flickable {
        id: settingsScroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: settingsColumn
          width: settingsScroll.width
          spacing: Style.space(14)

          PanelHero {
            width: parent.width
            title: "Protocol settings"
            meta: root.editingPowerProtocol ? "Power Breathe round sequence"
              : (root.editingProtocolId ? "Editing " + root.editorName : "Create a named breathing rhythm")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "Protocol editor"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Flow {
              width: parent.width
              spacing: Style.space(6)

              Button {
                text: "Power Breathe"
                bordered: true
                selected: root.editingPowerProtocol
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.loadEditorFromPattern("power")
              }

              Repeater {
                model: root.protocolLibrary.protocols

                Button {
                  required property var modelData
                  text: modelData.name
                  bordered: true
                  selected: !root.editingPowerProtocol && root.editingProtocolId === modelData.id
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.editSavedProtocol(Model.savedProtocolKey(modelData.id))
                }
              }

              Button {
                text: "+ New"
                bordered: true
                selected: !root.editingPowerProtocol && root.editingProtocolId === ""
                foreground: Color.accent
                fontFamily: root.fontFamily
                onClicked: root.newProtocol()
              }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)
            visible: !root.editingPowerProtocol

            Text {
              text: "Protocol name"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }

            TextField {
              id: protocolNameField
              width: parent.width
              text: root.editorName
              placeholderText: "Example: Morning calm"
              foreground: root.foreground
              accent: Color.accent
              font.family: root.fontFamily
              onTextChanged: if (activeFocus) root.editorName = text
              onAccepted: root.saveEditor()
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  focus = false
                  event.accepted = true
                }
              }
            }
          }

          Grid {
            columns: 2
            columnSpacing: Style.space(18)
            rowSpacing: Style.space(12)
            visible: !root.editingPowerProtocol

            NumberField {
              id: inhaleField
              label: "Inhale (seconds)"
              from: 1
              to: 30
              value: root.editorInhale
              fieldWidth: Style.space(110)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.editorInhale = v }
            }

            NumberField {
              id: holdInField
              label: "Hold after inhale"
              from: 0
              to: 30
              value: root.editorHoldIn
              fieldWidth: Style.space(110)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.editorHoldIn = v }
            }

            NumberField {
              id: exhaleField
              label: "Exhale (seconds)"
              from: 1
              to: 30
              value: root.editorExhale
              fieldWidth: Style.space(110)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.editorExhale = v }
            }

            NumberField {
              id: holdOutField
              label: "Hold after exhale"
              from: 0
              to: 30
              value: root.editorHoldOut
              fieldWidth: Style.space(110)
              foreground: root.foreground
              accent: Color.accent
              fontFamily: root.fontFamily
              onModified: function(v) { root.editorHoldOut = v }
            }
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.editingPowerProtocol

            Text {
              width: parent.width
              text: "1. Deep breathing · 2. Hold after the final exhale · 3. Full recovery inhale · 4. Hold the recovery breath"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "The exhale retention has no countdown. Continue with Space, Enter, or the on-screen button when you naturally need to breathe."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Grid {
              columns: 2
              columnSpacing: Style.space(18)
              rowSpacing: Style.space(12)

              NumberField {
                id: powerRoundsField
                label: "Rounds"
                from: 1
                to: 20
                value: root.editorPowerRounds
                fieldWidth: Style.space(110)
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.editorPowerRounds = v }
              }

              NumberField {
                id: powerBreathsField
                label: "Breaths per round"
                from: 30
                to: 40
                value: root.editorPowerBreaths
                fieldWidth: Style.space(110)
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.editorPowerBreaths = v }
              }

              NumberField {
                id: powerPaceField
                label: "Seconds per breath"
                from: 2
                to: 5
                value: root.editorPowerBreathSeconds
                fieldWidth: Style.space(110)
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.editorPowerBreathSeconds = v }
              }

              NumberField {
                id: powerRecoveryField
                label: "First recovery hold"
                from: 5
                to: 30
                value: root.editorPowerRecoveryHold
                fieldWidth: Style.space(110)
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.editorPowerRecoveryHold = v }
              }


              NumberField {
                id: powerRecoveryIncreaseField
                label: "Hold increase per round"
                from: 0
                to: 15
                value: root.editorPowerRecoveryIncrease
                fieldWidth: Style.space(110)
                foreground: root.foreground
                accent: Color.accent
                fontFamily: root.fontFamily
                onModified: function(v) { root.editorPowerRecoveryIncrease = v }
              }
            }

            Text {
              width: parent.width
              text: root.editorPowerRounds + " rounds · " + root.editorPowerBreaths
                + " breaths · " + root.editorPowerBreathSeconds + " sec each · manual retention · "
                + "recovery holds " + root.powerHoldPlan(root.editorPowerRecoveryHold,
                  root.editorPowerRecoveryIncrease, root.editorPowerRounds) + " sec"
              color: Color.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          NumberField {
            id: readyField
            label: "Get ready countdown (seconds)"
            from: 0
            to: 30
            value: root.getReadySeconds
            fieldWidth: Style.space(110)
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onModified: function(v) { root.setNumberSetting("getReadySeconds", v) }
          }

          Column {
            width: parent.width
            spacing: Style.space(7)

            Text {
              text: "Session visual"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Flow {
              width: parent.width
              spacing: Style.space(7)

              Repeater {
                model: root.visualChoices

                Button {
                  required property var modelData
                  text: modelData.name
                  bordered: true
                  selected: String(root.setting("visualStyle", "orb")) === modelData.key
                  foreground: selected ? Color.accent : root.foreground
                  fontFamily: root.fontFamily
                  onClicked: root.setStringSetting("visualStyle", modelData.key)
                }
              }
            }

            Text {
              width: parent.width
              text: "Choose how inhale, hold, and exhale are shown during a session."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
          }

          Toggle {
            width: parent.width
            label: "Audio cue at each phase"
            description: "Play a short cue when inhale, hold, or exhale begins."
            checked: root.setting("phaseCues", true) !== false
            foreground: root.foreground
            accent: Color.accent
            fontFamily: root.fontFamily
            onClicked: root.setBooleanSetting("phaseCues", !checked)
          }

          Text {
            width: parent.width
            visible: !root.editingPowerProtocol
            text: root.editorInhale + " in · " + root.editorHoldIn + " hold · "
              + root.editorExhale + " out · " + root.editorHoldOut + " hold"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Flow {
            width: parent.width
            spacing: Style.space(8)

            Button {
              text: root.editingPowerProtocol ? "Save Power settings & use"
                : (root.editingProtocolId ? "Save changes & use" : "Save & use")
              bordered: true
              foreground: Color.accent
              fontFamily: root.fontFamily
              onClicked: {
                if (root.editingPowerProtocol) root.savePowerEditor()
                else root.saveEditor()
              }
            }

            Button {
              visible: !root.editingPowerProtocol && root.editingProtocolId !== ""
              text: root.deleteArmed ? "Confirm delete" : "Delete"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.deleteEditor()
            }

            Button {
              text: "Back"
              bordered: true
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.closeSettings(true)
            }
          }

          Text {
            width: parent.width
            visible: root.settingsMessage !== ""
            text: root.settingsMessage
            color: root.settingsMessage.indexOf("Saved") === 0 ? Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            text: root.editingPowerProtocol
              ? "Power Breathe is a specialized round-based protocol. Its manual retention and recovery steps are preserved when you change these values."
              : "Built-in protocols stay unchanged. Saving creates a personal named protocol; reopening it here lets you change its timing."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
