import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// The models Nilo can use (nihil.nilo.models, plus any other one Ollama
// has). The lit LED is the one in use; choosing one that isn't downloaded
// starts the download. Downloads need Ollama: when it is down, a line on
// top says so and starts it.
Column {
    id: root

    property int current: -1        // highlighted with the keyboard
    property bool manage: false     // settings: offer to delete downloaded ones

    readonly property int count: Nilo.models.length

    spacing: 2

    function gb(value: real): string {
        return Number(value).toLocaleString(Qt.locale(Lang.locale), "f", Number.isInteger(value) || value >= 10 ? 0 : 1);
    }

    // The first choice selects a model; choosing it again while it is not
    // downloaded starts the download (so does its "download" button).
    function choose(index: int): void {
        const model = Nilo.models[index];
        if (!model) return;
        if (Nilo.settings.model !== model.tag) Nilo.set("model", model.tag);
        else if (!model.installed && !(Nilo.pull && Nilo.pull.model === model.tag && Nilo.pull.status !== "error"))
            Nilo.download(model.tag);
    }

    // The first press shows where the selection is; the next ones move it.
    function move(step: int): void {
        if (current < 0) current = Math.max(0, Nilo.models.findIndex(m => m.tag === Nilo.settings.model));
        else current = Math.max(0, Math.min(count - 1, current + step));
    }

    Item {
        width: root.width
        height: visible ? 44 : 0
        visible: Nilo.known && !Nilo.ollama

        Rectangle {
            id: warn
            anchors.left: parent.left
            anchors.leftMargin: 18
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: Nilo.startingOllama ? Tokens.ink : Tokens.interrupt

            SequentialAnimation on opacity {
                running: Nilo.startingOllama
                loops: Animation.Infinite
                onRunningChanged: if (!running) warn.opacity = 1
                NumberAnimation { to: 0.2; duration: 420 }
                NumberAnimation { to: 1; duration: 420 }
            }
        }

        Txt {
            anchors.left: warn.right
            anchors.leftMargin: 14
            anchors.right: startButton.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Nilo.startingOllama ? Lang.niloOllamaStarting : Lang.niloOllamaDown
            color: Tokens.dim
            font.pixelSize: 13
        }

        PillButton {
            id: startButton
            anchors.right: parent.right
            anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            visible: !Nilo.startingOllama
            text: Lang.niloStartOllama
            accent: true
            onClicked: Nilo.startOllama()
        }
    }

    Repeater {
        model: Nilo.models

        Rectangle {
            id: row

            required property var modelData
            required property int index

            readonly property bool selected: Nilo.settings.model === modelData.tag
            readonly property bool pulling: Nilo.pull !== null && Nilo.pull.model === modelData.tag && Nilo.pull.status !== "error"
            readonly property bool failed: Nilo.pull !== null && Nilo.pull.model === modelData.tag && Nilo.pull.status === "error"
            readonly property bool tight: modelData.ram > 0 && Nilo.ramGB > 0 && modelData.ram > Nilo.ramGB * 0.7

            width: root.width
            height: 54
            radius: 14
            color: root.current === index || area.containsMouse ? Tokens.raised : "transparent"

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    root.current = row.index;
                    root.choose(row.index);
                }
            }

            Led {
                id: led
                anchors.left: parent.left
                anchors.leftMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                on: row.selected
            }

            Column {
                anchors.left: led.right
                anchors.leftMargin: 14
                anchors.right: side.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Txt {
                    width: parent.width
                    text: row.modelData.label
                    color: row.selected ? Tokens.ink : Tokens.dim
                    font.pixelSize: 15
                }

                Label {
                    width: parent.width
                    text: row.modelData.ram > 0
                        ? Lang.modelSize.arg(root.gb(row.modelData.size)) + " · " + Lang.modelRam.arg(root.gb(row.modelData.ram))
                        : row.modelData.size > 0 ? Lang.modelSize.arg(root.gb(row.modelData.size)) : row.modelData.tag
                }
            }

            Row {
                id: side
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                DotMeter {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.pulling
                    count: 10
                    dot: 5
                    gap: 3
                    value: Nilo.pull?.progress ?? 0
                    head: row.pulling ? Math.min(9, Math.floor((Nilo.pull?.progress ?? 0) * 10)) : -1
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: text !== ""
                    text: row.pulling ? Lang.niloDownloading.arg(Math.floor((Nilo.pull?.progress ?? 0) * 100))
                        : row.failed ? (Nilo.pull.code === "ollama-down" ? Lang.modelFailedOllama : Lang.modelFailed.arg(Nilo.pull.error.slice(0, 40)))
                        : Nilo.recommended === row.modelData.tag ? Lang.modelRecommended
                        : row.selected && row.modelData.installed ? Lang.modelSelected
                        : row.modelData.installed ? Lang.modelInstalled
                        : row.tight ? Lang.modelTight : ""
                    color: row.failed ? Tokens.dim : Nilo.recommended === row.modelData.tag && !row.pulling ? Tokens.ink : Tokens.muted
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.manage && row.modelData.installed && !row.selected
                    text: Lang.niloDelete
                    onClicked: Nilo.remove(row.modelData.tag)
                }

                PillButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: row.selected && !row.modelData.installed && !row.pulling
                    text: Lang.niloDownload
                    accent: true
                    onClicked: Nilo.download(row.modelData.tag)
                }
            }
        }
    }
}
