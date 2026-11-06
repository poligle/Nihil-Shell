import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// What is waiting to be applied, and applying it: the password goes to sudo
// (services/Machine.qml); with a fingerprint reader, a finger works too.
Item {
    id: root

    property bool asking: false
    property bool showLog: false
    readonly property bool hasLog: Machine.log !== "" && (Machine.busy || Machine.phase === "failed" || Machine.phase === "warning")

    implicitHeight: 56 + (showLog && hasLog ? logBox.height + 12 : 0)

    function go(): void {
        if (password.text === "" && !Machine.get("fingerprint", false)) {
            password.grab();
            return;
        }
        Machine.apply(password.text);
        password.clear();
        root.asking = false;
    }

    // The end of /run/nihil/apply.log, following it while it applies.
    Rectangle {
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

            Txt {
                width: parent.width
                text: Machine.statusTitle
                color: Machine.phase === "failed" ? Tokens.interrupt : Tokens.ink
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
            visible: root.asking
            Layout.preferredWidth: 220
            password: true
            placeholder: Lang.cfgApplyPassword
            onAccepted: root.go()
        }

        KeyButton {
            visible: Machine.changes > 0 && !Machine.busy
            text: root.asking ? Lang.cfgCancel : Lang.cfgDiscard
            onClicked: {
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
                    password.grab();
                }
            }
        }
    }
}
