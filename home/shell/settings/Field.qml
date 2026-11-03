import QtQuick
import QtQuick.Controls as QQC
import qs.theme

// A text field: hairline pill, mono text. `value` is shown while the field
// does not have the focus; what is typed goes out through edited().
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool password: false
    property bool invalid: false
    property alias text: input.text

    signal edited(string text)
    signal accepted()

    function grab(): void { input.forceActiveFocus(); }
    function clear(): void { input.text = ""; }

    onValueChanged: {
        if (!input.activeFocus && input.text !== value)
            input.text = value;
    }
    Component.onCompleted: input.text = value

    implicitWidth: 300
    implicitHeight: 40
    radius: height / 2
    color: Tokens.surface
    border.width: 1
    border.color: invalid ? Tokens.interrupt : input.activeFocus ? Tokens.muted : Tokens.line

    QQC.TextField {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        background: null
        color: Tokens.ink
        placeholderText: root.placeholder
        placeholderTextColor: Tokens.muted
        font.family: Tokens.fontMono
        font.pixelSize: 13
        verticalAlignment: TextInput.AlignVCenter
        echoMode: root.password ? TextInput.Password : TextInput.Normal
        selectByMouse: true
        onTextEdited: root.edited(text)
        onAccepted: root.accepted()
    }
}
