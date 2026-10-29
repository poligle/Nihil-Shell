import QtQuick
import QtQuick.Controls as QQC
import qs.theme
import qs.config
import qs.services
import qs.components

// Behind the gear. Everything here applies at once, without a rebuild:
// the agent keeps it in ~/.local/state/nihil/nilo.json.
Item {
    id: root

    property int cursor: -1     // keyboard: models, then access, then "think"

    readonly property int modelCount: models.count
    readonly property int total: modelCount + access.count + 1
    readonly property var sleepChoices: [1, 5, 15, 30]

    signal done()

    function gb(value: real): string {
        return Number(value).toLocaleString(Qt.locale(Lang.locale), "f", 1);
    }

    function sync(): void {
        models.current = cursor >= 0 && cursor < modelCount ? cursor : -1;
        access.current = cursor >= modelCount && cursor < modelCount + access.count ? cursor - modelCount : -1;
        const item = models.current >= 0 ? models : access.current >= 0 ? access : think;
        const y = item.mapToItem(content, 0, 0).y;
        if (y < flick.contentY) flick.contentY = Math.max(0, y - 40);
        else if (y + item.height > flick.contentY + flick.height)
            flick.contentY = Math.min(flick.contentHeight - flick.height, y + item.height - flick.height + 20);
    }

    function move(step: int): void {
        cursor = Math.max(0, Math.min(total - 1, cursor < 0 ? 0 : cursor + step));
        sync();
    }

    function activate(): void {
        if (cursor < 0) return;
        if (cursor < modelCount) models.choose(cursor);
        else if (cursor < modelCount + access.count) access.toggle(cursor - modelCount);
        else Nilo.set("think", !(Nilo.settings.think === true));
    }

    function sleepStep(step: int): void {
        const i = sleepChoices.indexOf(Nilo.settings.keepAlive ?? 5);
        Nilo.set("keepAlive", sleepChoices[Math.max(0, Math.min(sleepChoices.length - 1, (i < 0 ? 1 : i) + step))]);
    }

    component Section: Column {
        property alias title: heading.text
        width: parent ? parent.width : 0
        spacing: 8
        topPadding: 18

        Rectangle { width: parent.width; height: 1; color: Tokens.line }
        Label { id: heading; topPadding: 8 }
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: content.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: content
            x: Math.max(0, (parent.width - width) / 2)
            width: Math.min(640, flick.width)
            spacing: 4

            Section { title: Lang.setModel; topPadding: 0 }

            ModelList {
                id: models
                width: content.width
                manage: true
            }

            Section { title: Lang.setAccess }

            AccessList {
                id: access
                width: content.width
            }

            Row {
                width: content.width
                height: 44
                spacing: 12
                leftPadding: 16

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.setRepo
                }

                QQC.TextField {
                    id: repo
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(320, content.width - 160)
                    text: Nilo.settings.repo ?? ""
                    color: Tokens.ink
                    selectionColor: Tokens.ink
                    selectedTextColor: Tokens.black
                    font.family: Tokens.fontMono
                    font.pixelSize: 12
                    background: Rectangle {
                        radius: 12
                        color: Tokens.surface
                        border.width: 1
                        border.color: repo.activeFocus ? Tokens.muted : Tokens.line
                    }
                    leftPadding: 12
                    rightPadding: 12
                    onEditingFinished: if (text.trim() !== (Nilo.settings.repo ?? "")) Nilo.set("repo", text.trim())
                    Keys.onEscapePressed: root.done()
                    onAccepted: root.done()
                }
            }

            Section { title: Lang.setMemory }

            Txt {
                width: content.width
                leftPadding: 16
                text: Nilo.loaded
                    ? Lang.setAwakeUntil.arg(root.gb(Nilo.sizeGB)).arg(Nilo.gpu)
                        .arg(Nilo.expires > 0 ? Qt.formatTime(new Date(Nilo.expires * 1000), "HH:mm") : "—")
                    : Lang.setAsleep
                color: Tokens.dim
                font.pixelSize: 13
            }

            Row {
                height: 44
                spacing: 8
                leftPadding: 16

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.setSleepAfter
                    rightPadding: 4
                }

                Repeater {
                    model: root.sleepChoices

                    PillButton {
                        required property int modelData
                        anchors.verticalCenter: parent.verticalCenter
                        text: Lang.setMinutes.arg(modelData)
                        accent: (Nilo.settings.keepAlive ?? 5) === modelData
                        onClicked: Nilo.set("keepAlive", modelData)
                    }
                }

                Item { width: 12; height: 1 }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Nilo.loaded
                    text: Lang.setSleepNow
                    onClicked: Nilo.sleep()
                }
            }

            Section { title: Lang.niloThinking }

            Rectangle {
                id: think
                width: content.width
                height: 56
                radius: 14
                color: root.cursor === root.total - 1 || thinkArea.containsMouse ? Tokens.raised : "transparent"

                MouseArea {
                    id: thinkArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Nilo.set("think", !(Nilo.settings.think === true))
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3

                    Txt {
                        text: Lang.setThink
                        color: Nilo.settings.think ? Tokens.ink : Tokens.dim
                        font.pixelSize: 15
                    }

                    Txt {
                        text: Lang.setThinkSub
                        color: Tokens.muted
                        font.pixelSize: 12
                    }
                }

                Led {
                    anchors.right: parent.right
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    on: Nilo.settings.think === true
                }
            }

            Item { width: 1; height: 18 }

            Rectangle { width: content.width; height: 1; color: Tokens.line }

            Item { width: 1; height: 10 }

            Row {
                width: content.width
                spacing: 16
                leftPadding: 16

                PillButton {
                    id: again
                    anchors.verticalCenter: parent.verticalCenter
                    text: Lang.setIntro
                    onClicked: {
                        Nilo.set("onboarded", false);
                        root.done();
                    }
                }

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    width: content.width - again.width - 48
                    text: Lang.setRebuild
                    color: Tokens.muted
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    font.pixelSize: 12
                }
            }
        }
    }
}
