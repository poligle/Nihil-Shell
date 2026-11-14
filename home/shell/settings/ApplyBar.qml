import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

Item {
    id: root

    property bool asking: false
    property bool showLog: false
    readonly property bool hasLog: Machine.log !== "" && (Machine.busy || Machine.phase === "failed" || Machine.phase === "warning")

    implicitHeight: 56 + (showLog && hasLog ? logBox.height + 12 : 0)

    readonly property bool fingerWait: Machine.phase === "auth" && Machine.auth === "finger"

    function go(): void {
        if (password.text === "" && !Machine.fingerprint) {
            password.grab();
            return;
        }
        Machine.apply(password.text);
        password.clear();
    }

    Connections {
        target: Machine
        function onFailureChanged(): void {
            if (Machine.kind === "settings" && (Machine.failure === "finger" || Machine.failure === "password")) {
                root.asking = true;
                password.grab();
            }
        }
        function onPhaseChanged(): void {
            if (Machine.phase === "applying")
                root.asking = false;
        }
    }

    Surface {
        id: logBox
        visible: root.showLog && root.hasLog
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 170
        radius: 12
        color: Tokens.surface
        border.width: 1
        border.color: Tokens.line

        Flickable {
            id: logView
            anchors.fill: parent
            anchors.margins: 12
            clip: true
            contentHeight: logText.implicitHeight
            contentY: Math.max(0, contentHeight - height)
            boundsBehavior: Flickable.StopAtBounds

            Text {
                id: logText
                width: logView.width
                text: Machine.log
                color: Tokens.dim
                font.family: Tokens.fontMono
                font.pixelSize: 11
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: row.top
        anchors.bottomMargin: 6
        height: 1
        color: Tokens.line
    }

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 50
        spacing: 12

        Column {
            Layout.fillWidth: true
            spacing: 3

            Alert {
                width: parent.width
                text: Machine.statusTitle
                wrong: Machine.phase === "failed"
                color: Tokens.ink
                font.family: Tokens.fontSans
                font.pixelSize: 14
            }

            Label {
                width: parent.width
                visible: text !== ""
                text: Machine.statusSub
            }
        }

        KeyButton {
            visible: root.hasLog
            text: root.showLog ? Lang.cfgHideLog : Lang.cfgShowLog
            onClicked: root.showLog = !root.showLog
        }

        Field {
            id: password
            visible: root.asking && (!Machine.busy || root.fingerWait)
            Layout.preferredWidth: 220
            password: true
            placeholder: Lang.cfgApplyPassword
            onAccepted: root.go()
        }

        KeyButton {
            visible: Machine.changes > 0 && (!Machine.busy || root.fingerWait)
            text: root.asking ? Lang.cfgCancel : Lang.cfgDiscard
            onClicked: {
                if (root.fingerWait)
                    Machine.cancelFinger();
                if (root.asking)
                    root.asking = false;
                else
                    Machine.discard();
            }
        }

        KeyButton {
            visible: Machine.changes > 0 && !Machine.busy
            accent: true
            text: Lang.cfgApply
            onClicked: {
                if (root.asking) {
                    root.go();
                } else {
                    root.asking = true;
                    if (Machine.fingerprint)
                        Machine.apply("");
                    password.grab();
                }
            }
        }
    }
}
