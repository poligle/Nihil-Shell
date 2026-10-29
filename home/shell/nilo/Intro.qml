import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// The first time Nilo opens: hello, how to call it, its model and what it
// may do. Enter moves on; the settings (the gear) change all of it later.
Item {
    id: root

    property int page: 0
    readonly property int pages: 5
    readonly property real column: Math.min(580, width - 64)

    signal finished()

    function next(): void {
        if (page === 2) {
            // Leaving the models page: the chosen one starts downloading.
            if (models.current >= 0) models.choose(models.current);
            if (!Nilo.installed && Nilo.current && !(Nilo.pull && Nilo.pull.status !== "error"))
                Nilo.download(Nilo.current.tag);
        }
        if (page < pages - 1) {
            page++;
            models.current = -1;
            access.current = -1;
        } else {
            Nilo.set("onboarded", true);
            finished();
        }
    }

    function move(step: int): bool {
        if (page === 2) { models.move(step); return true; }
        if (page === 3) { access.move(step); return true; }
        return false;
    }

    function toggle(): bool {
        if (page === 2 && models.current >= 0) { models.choose(models.current); return true; }
        if (page === 3 && access.current >= 0) { access.toggle(access.current); return true; }
        return false;
    }

    // One page at a time, fading in from a little lower.
    component Page: Item {
        property bool here: false

        anchors.fill: parent
        opacity: here ? 1 : 0
        visible: opacity > 0
        transform: Translate { y: here ? 0 : 12; Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } } }

        Behavior on opacity { NumberAnimation { duration: 220 } }
    }

    // A way to call Nilo: its keys on the left, what they mean on the right.
    component Way: Row {
        id: way
        property alias keys: caps.model
        property string text: ""
        spacing: 18

        Item {
            width: 170
            height: 30

            Row {
                anchors.right: parent.right
                spacing: 6

                Repeater {
                    id: caps
                    Keycap { required property string modelData; text: modelData }
                }
            }
        }

        Txt {
            anchors.verticalCenter: parent.verticalCenter
            text: way.text
            color: Tokens.dim
        }
    }

    Item {
        id: stage
        anchors.top: parent.top
        anchors.bottom: footer.top
        anchors.left: parent.left
        anchors.right: parent.right

        Page {
            here: root.page === 0

            Column {
                anchors.centerIn: parent
                width: root.column
                spacing: 16

                DotText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introHello
                    font.pixelSize: 34
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    text: Lang.introLocal
                    color: Tokens.dim
                    font.pixelSize: 15
                    lineHeight: 1.3
                }
            }
        }

        Page {
            here: root.page === 1

            Column {
                anchors.centerIn: parent
                width: root.column
                spacing: 18

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introCall
                    font.pixelSize: 20
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 12

                    Way { keys: ["SUPER", "I"]; text: Lang.introBind }
                    Way { keys: ["COPILOT"]; text: Lang.introCopilot }
                    Way { keys: ["SUPER", Lang.keySpace, "?"]; text: Lang.introLauncher }
                }

                Txt {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    text: Lang.introSleep.arg(Nilo.settings.keepAlive ?? 5)
                    color: Tokens.muted
                    font.pixelSize: 13
                    lineHeight: 1.3
                }
            }
        }

        Page {
            here: root.page === 2

            Column {
                anchors.centerIn: parent
                width: root.column
                spacing: 6

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introModel
                    font.pixelSize: 20
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introModelSub.arg(Math.round(Nilo.ramGB))
                    color: Tokens.muted
                    font.pixelSize: 13
                }

                Item { width: 1; height: 8 }

                ModelList {
                    id: models
                    width: parent.width
                }

                Label {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: Nilo.pull !== null && Nilo.pull.status !== "error"
                    text: Lang.introKeepsDownloading
                    topPadding: 6
                }
            }
        }

        Page {
            here: root.page === 3

            Column {
                anchors.centerIn: parent
                width: root.column
                spacing: 6

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introAccess
                    font.pixelSize: 20
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introAccessSub
                    color: Tokens.muted
                    font.pixelSize: 13
                }

                Item { width: 1; height: 8 }

                AccessList {
                    id: access
                    width: parent.width
                }
            }
        }

        Page {
            here: root.page === 4

            Column {
                anchors.centerIn: parent
                width: root.column
                spacing: 14

                DotText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introDone
                    font.pixelSize: 34
                }

                Txt {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Lang.introDoneSub
                    color: Tokens.dim
                    font.pixelSize: 15
                }
            }
        }
    }

    // Where we are, as LEDs, and the way on.
    Item {
        id: footer
        anchors.bottom: parent.bottom
        anchors.horizontalCenter: parent.horizontalCenter
        width: root.column
        height: 40

        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Repeater {
                model: root.pages

                Rectangle {
                    required property int index
                    width: index === root.page ? 18 : 6
                    height: 6
                    radius: 3
                    color: index === root.page ? Tokens.ink : index < root.page ? Tokens.dim : Tokens.off

                    Behavior on width { NumberAnimation { duration: Tokens.animNormal; easing.type: Easing.OutCubic } }
                    Behavior on color { ColorAnimation { duration: Tokens.animNormal } }

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: index < root.page
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.page = index
                    }
                }
            }
        }

        PillButton {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.page === root.pages - 1 ? Lang.introStart : Lang.introNext
            accent: true
            onClicked: root.next()
        }
    }
}
