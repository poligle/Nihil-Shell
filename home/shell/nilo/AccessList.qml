import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// What Nilo may do: one LED switch per kind of tool. Files and git touch
// the repository, so turning them on takes a second step: the row says
// what it allows and waits for "authorize" (or the same key again). Even
// then, every change to a file and every commit or push asks first, and
// choosing another repository turns both off again (agent.py).
Column {
    id: root

    property int current: -1
    property string asking: ""      // the switch waiting for its authorization

    readonly property string repo: Nilo.settings.repo ?? "~/nixos-config"
    readonly property var items: [
        { key: "web", title: Lang.accessWeb, sub: Lang.accessWebSub, guard: "" },
        { key: "system", title: Lang.accessSystem, sub: Lang.accessSystemSub, guard: "" },
        { key: "write", title: Lang.accessWrite, sub: Lang.accessWriteSub.arg(repo), guard: Lang.accessWriteGuard.arg(repo) },
        { key: "git", title: Lang.accessGit, sub: Lang.accessGitSub.arg(repo), guard: Lang.accessGitGuard.arg(repo) }
    ]
    readonly property int count: items.length

    signal grew(Item row)       // an authorization opened under its switch

    spacing: 2

    onVisibleChanged: if (!visible) asking = ""

    // Off goes at once; on asks first when the switch has a guard.
    function toggle(index: int): void {
        const item = items[index];
        if (!item) return;
        const on = Nilo.settings[item.key] === true;
        if (on || item.guard === "" || asking === item.key) {
            Nilo.set(item.key, !on);
            asking = "";
        } else {
            asking = item.key;
        }
    }

    function authorize(): void {
        const index = items.findIndex(item => item.key === asking);
        if (index >= 0) toggle(index);
    }

    function move(step: int): void {
        current = current < 0 ? 0 : Math.max(0, Math.min(count - 1, current + step));
        if (asking !== "" && items[current].key !== asking) asking = "";
    }

    Repeater {
        model: root.items

        Rectangle {
            id: row

            required property var modelData
            required property int index

            readonly property bool on: Nilo.settings[modelData.key] === true
            readonly property bool asking: root.asking === modelData.key

            width: root.width
            height: 56 + (asking ? guard.height : 0)
            radius: 14
            color: asking || root.current === index || area.containsMouse ? Tokens.raised : "transparent"
            border.width: asking ? 1 : 0
            border.color: Tokens.interrupt
            clip: true

            Behavior on height { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }

            onHeightChanged: if (asking) root.grew(row)

            MouseArea {
                id: area
                width: parent.width
                height: 56
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.current = row.index;
                    root.toggle(row.index);
                }
            }

            Column {
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.right: led.left
                anchors.rightMargin: 16
                y: (56 - height) / 2
                spacing: 3

                Txt {
                    width: parent.width
                    text: row.modelData.title
                    color: row.on || row.asking ? Tokens.ink : Tokens.dim
                    font.pixelSize: 15
                }

                Txt {
                    width: parent.width
                    text: row.modelData.sub
                    color: Tokens.muted
                    font.pixelSize: 12
                }
            }

            Led {
                id: led
                anchors.right: parent.right
                anchors.rightMargin: 18
                y: (56 - height) / 2
                on: row.on
                color: row.asking ? Tokens.interrupt : on ? Tokens.ink : Tokens.off
            }

            // The authorization: what it allows, then yes or no.
            Column {
                id: guard
                x: 16
                y: 52
                width: parent.width - 32
                spacing: 12
                bottomPadding: 16
                visible: row.asking

                Txt {
                    width: parent.width
                    text: row.modelData.guard
                    color: Tokens.dim
                    wrapMode: Text.Wrap
                    elide: Text.ElideNone
                    font.pixelSize: 13
                    lineHeight: 1.2
                }

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    PillButton {
                        text: Lang.confirmCancel
                        onClicked: root.asking = ""
                    }

                    Rectangle {
                        implicitWidth: yes.implicitWidth + 24
                        implicitHeight: 26
                        radius: 13
                        color: Tokens.interrupt

                        Label {
                            id: yes
                            anchors.centerIn: parent
                            text: Lang.accessAuthorize
                            color: Tokens.ink
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.authorize()
                        }
                    }
                }
            }
        }
    }
}
