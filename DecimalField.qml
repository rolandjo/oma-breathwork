import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Ui

Column {
  id: root

  property string label: ""
  property real value: 0
  property real from: 0
  property real to: 100
  property real stepSize: 0.1
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real fieldWidth: Style.spacing.numberFieldWidth
  property bool hasCursor: false
  property bool _hovered: false
  property alias field: spin

  signal modified(real value)
  signal hovered(bool on)

  spacing: Style.spacing.md

  Text {
    textFormat: Text.PlainText
    visible: root.label !== ""
    text: root.label
    color: Qt.darker(root.foreground, 1.4)
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  QQC.SpinBox {
    id: spin
    width: root.fieldWidth
    implicitHeight: Math.max(Style.spacing.controlHeight, root.fontSize + Style.spacing.controlPaddingY * 2)
    from: Math.round(root.from * 10)
    to: Math.round(root.to * 10)
    stepSize: Math.round(root.stepSize * 10)
    value: Math.round(root.value * 10)
    editable: true
    font.family: root.fontFamily
    font.pixelSize: root.fontSize

    readonly property bool _focused: spin.activeFocus
    readonly property bool _hot: root._hovered || root.hasCursor
    readonly property var _borderSpec: Border.controlSpec(_focused ? "focus" : (_hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

    leftPadding: Border.left(_borderSpec) + Style.spacing.controlPaddingX
    rightPadding: Border.right(_borderSpec) + Style.spacing.controlPaddingX
    topPadding: Border.top(_borderSpec)
    bottomPadding: Border.bottom(_borderSpec)

    textFromValue: function(value, locale) { return Number(value / 10).toLocaleString(locale, 'f', 1) }
    valueFromText: function(text, locale) { return Math.round(Number.fromLocaleString(locale, text) * 10) }
    validator: DoubleValidator { bottom: root.from; top: root.to; decimals: 1; locale: spin.locale.name }
    onValueModified: root.modified(value / 10)

    background: BorderSurface {
      color: Style.controlFill(spin._focused, spin._hot, root.foreground, root.accent)
      borderSpec: spin._borderSpec
      radius: Style.cornerRadius

      HoverHandler {
        onHoveredChanged: {
          root._hovered = hovered
          root.hovered(hovered)
        }
      }
    }

    contentItem: TextInput {
      text: spin.displayText
      font: spin.font
      color: root.foreground
      selectionColor: Style.selectionFillFor(root.foreground, root.accent)
      selectedTextColor: root.foreground
      horizontalAlignment: Qt.AlignHCenter
      verticalAlignment: Qt.AlignVCenter
      readOnly: !spin.editable
      validator: spin.validator
      inputMethodHints: Qt.ImhFormattedNumbersOnly
    }
  }
}
