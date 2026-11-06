import QtQuick
import QtQuick.Controls as QQC
import qs.theme

// A text field: a hairline box with the corners of a key (KeyButton), mono
// text. `value` is shown while the field does not have the focus; what is
// typed goes out through edited(), and finished() says when it is done
// (Enter, or the focus gone elsewhere).
Rectangle {
    id: root

    property string value: ""
    property string placeholder: ""
    property bool password: false
    property bool invalid: false
    // Escape goes to escaped() and stops there, rather than on to what
    // holds the field (the panel would close).
    property bool catchEscape: false
    property alias text: input.text

    signal edited(string text)
    signal accepted()
    signal escaped()
    signal finished()

    function grab(): void { input.forceActiveFocus(); }
    function clear(): void { input.text = ""; }

    onValueChanged: {
        if (!input.activeFocus && input.text !== value)
            input.text = value;
    }
    Component.onCompleted: input.text = value

    implicitWidth: 300
    implicitHeight: 36
    radius: 8
    color: Tokens.surface
    border.width: 1
    border.color: invalid ? Tokens.interrupt : input.activeFocus ? Tokens.muted : Tokens.line

    QQC.TextField {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
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
        onEditingFinished: root.finished()
        Keys.onEscapePressed: event => {
            root.escaped();
            event.accepted = root.catchEscape;
        }
    }
}
