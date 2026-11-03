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

    implicitHeight: 56

    function go(): void {
        if (password.text === "" && !Machine.get("fingerprint", false)) {
            password.grab();
            return;
        }
        Machine.apply(password.text);
        password.clear();
        root.asking = false;
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Tokens.line
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 4
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

        Field {
            id: password
            visible: root.asking
            Layout.preferredWidth: 220
            password: true
            placeholder: Lang.cfgApplyPassword
            onAccepted: root.go()
        }

        PillButton {
            visible: Machine.changes > 0 && !Machine.busy
            text: root.asking ? Lang.cfgCancel : Lang.cfgDiscard
            onClicked: {
                if (root.asking)
                    root.asking = false;
                else
                    Machine.discard();
            }
        }

        PillButton {
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
