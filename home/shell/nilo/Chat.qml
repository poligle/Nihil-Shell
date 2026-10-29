import QtQuick
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components
import "Markdown.js" as Markdown

// The conversation: your questions after "›", Nilo's answers in Markdown,
// what its tools do as small lines with an LED, and the git confirmation
// as a card. Empty, it suggests a few questions.
Item {
    id: root

    property string armed: ""       // the confirmation armed by a first enter
    property bool follow: true      // stick to the end while it writes

    signal suggest(string text)

    readonly property var voices: ({ ink: String(Tokens.ink), dim: String(Tokens.dim), code: "#E6E6E6",
                                     surface: String(Tokens.surface), mono: Tokens.fontMono })

    function scroll(step: real): void {
        follow = false;
        list.contentY = Math.max(list.originY, Math.min(list.contentY + step, list.originY + list.contentHeight - list.height));
        if (list.atYEnd) follow = true;
    }

    function toEnd(): void {
        follow = true;
        list.positionViewAtEnd();
    }

    function host(url: string): string {
        const m = String(url ?? "").match(/^[a-z]+:\/\/([^\/?#]+)/i);
        return m ? m[1].replace(/^www\./, "") : String(url ?? "");
    }

    function toolText(name: string, status: string, info: string): string {
        let data = {};
        try { data = JSON.parse(info || "{}"); } catch (e) {}
        const args = data.args ?? data;
        if (status === "failed") return Lang.toolFailed.arg(String(data.error ?? "").slice(0, 80));
        const running = status === "running";
        switch (name) {
        case "web_search":
            return running ? Lang.toolSearching.arg(args.query ?? "") : Lang.toolSearched.arg(data.count ?? 0).arg(args.query ?? "");
        case "open_url":
            return running ? Lang.toolReading.arg(host(args.url)) : Lang.toolRead.arg(data.title || data.host || host(args.url));
        case "system_info":
            return running ? Lang.toolSystem : Lang.toolSystemDone;
        case "git_status":
            return running ? Lang.toolGitStatus : Lang.toolGitStatusDone.arg(data.changes ?? 0).arg(data.branch ?? "");
        case "git_commit":
            if (running) return Lang.toolGitCommit;
            if (data.declined) return Lang.toolDeclined;
            if (data.pushed) return data.commit ? Lang.toolGitPushed.arg(data.commit) : Lang.toolGitPushedOnly;
            return Lang.toolGitCommitted.arg(data.commit ?? "");
        }
        return name;
    }

    function errorText(code: string, detail: string): string {
        const model = Nilo.settings.model ?? "";
        switch (code) {
        case "ollama-down": return Lang.niloErrOllama;
        case "model-missing": return Lang.niloErrModel.arg(model);
        case "memory": return Lang.niloErrMemory.arg(model);
        case "no-model": return Lang.niloErrNoModel;
        case "bad-repo": return Lang.niloErrRepo.arg(detail);
        }
        return Lang.niloErrOther.arg((detail || code).slice(0, 160));
    }

    // Empty: a line and some questions to start with.
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.max(0, parent.height * 0.5 - 10)
        width: Math.min(620, parent.width - 48)
        spacing: 18
        visible: Nilo.messages.count === 0
        opacity: visible ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

        readonly property bool downloading: Nilo.pull !== null && Nilo.pull.status !== "error"
            && Nilo.pull.model === (Nilo.settings.model ?? "")

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Nilo.installed ? (Nilo.settings.web ? Lang.niloEmpty : Lang.niloEmptyOffline)
                : parent.downloading ? Lang.niloDownloadingModel.arg(Nilo.settings.model).arg(Math.floor(Nilo.pull.progress * 100))
                : Lang.niloErrModel.arg(Nilo.settings.model ?? "")
            color: Tokens.dim
            font.pixelSize: 15
        }

        // Without its model, Nilo can't answer yet: the download instead of the questions.
        DotMeter {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Nilo.installed && parent.downloading
            count: 24
            dot: 6
            gap: 4
            value: Nilo.pull?.progress ?? 0
        }

        PillButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Nilo.installed && !parent.downloading && Nilo.known
            text: Lang.niloDownload
            accent: true
            onClicked: Nilo.download(Nilo.settings.model)
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 8
            visible: Nilo.installed

            Repeater {
                model: [
                    { text: Lang.niloTryFlake, on: true },
                    { text: Lang.niloTryNews, on: Nilo.settings.web === true },
                    { text: Lang.niloTryDisk, on: Nilo.settings.system === true },
                    { text: Lang.niloTryPush, on: Nilo.settings.git === true }
                ].filter(s => s.on)

                Rectangle {
                    required property var modelData

                    anchors.horizontalCenter: parent.horizontalCenter
                    width: label.implicitWidth + 28
                    height: 32
                    radius: 16
                    color: area.containsMouse ? Tokens.raised : "transparent"
                    border.width: 1
                    border.color: Tokens.line

                    Txt {
                        id: label
                        anchors.centerIn: parent
                        text: parent.modelData.text
                        color: area.containsMouse ? Tokens.ink : Tokens.dim
                        font.pixelSize: 13
                    }

                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.suggest(parent.modelData.text)
                    }
                }
            }
        }
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        model: Nilo.messages
        boundsBehavior: Flickable.StopAtBounds
        visible: Nilo.messages.count > 0
        bottomMargin: 8

        onCountChanged: if (root.follow) Qt.callLater(positionViewAtEnd)
        onContentHeightChanged: if (root.follow) Qt.callLater(positionViewAtEnd)
        onMovementStarted: root.follow = false
        onMovementEnded: root.follow = atYEnd

        delegate: Item {
            id: entry

            required property int index
            required property string kind
            required property string text
            required property bool done
            required property string name
            required property string status
            required property string info
            required property string cid

            readonly property real gapAbove: index === 0 ? 0 : kind === "user" ? 26 : kind === "nilo" ? 12 : 8

            width: ListView.view.width
            height: gapAbove + body.height

            Loader {
                id: body
                y: entry.gapAbove
                width: parent.width
                sourceComponent: entry.kind === "user" ? userView
                    : entry.kind === "nilo" ? niloView
                    : entry.kind === "tool" ? toolView
                    : entry.kind === "confirm" ? confirmView
                    : entry.kind === "error" ? errorView : noteView
            }

            Component {
                id: userView

                Row {
                    spacing: 10

                    Txt {
                        text: "›"
                        color: Tokens.muted
                        font.family: Tokens.fontMono
                        font.pixelSize: 15
                    }

                    Txt {
                        width: entry.width - 24
                        text: entry.text
                        color: Tokens.dim
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 14
                    }
                }
            }

            Component {
                id: niloView

                Column {
                    spacing: 8

                    Text {
                        id: reply
                        width: entry.width
                        text: Markdown.html(entry.text, root.voices)
                        textFormat: Text.RichText
                        wrapMode: Text.Wrap
                        color: Tokens.ink
                        font.family: Tokens.fontSans
                        font.pixelSize: 15
                        lineHeight: 1.3
                        onLinkActivated: link => {
                            Drawers.close();
                            Qt.openUrlExternally(link);
                        }

                        HoverHandler {
                            cursorShape: reply.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }

                    Row {
                        id: meta
                        visible: entry.done && entry.text !== ""
                        spacing: 14

                        property bool copied: false
                        readonly property var stats: { try { return JSON.parse(entry.info || "{}"); } catch (e) { return {}; } }

                        Label {
                            visible: (meta.stats.tokens ?? 0) > 0 && (meta.stats.seconds ?? 0) > 0
                            text: Lang.niloRate.arg(Math.round(meta.stats.tokens / meta.stats.seconds))
                            color: Tokens.muted
                        }

                        Label {
                            text: meta.copied ? Lang.niloCopied : Lang.niloCopy
                            color: copyArea.containsMouse ? Tokens.ink : Tokens.muted

                            MouseArea {
                                id: copyArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Quickshell.execDetached([Config.cmd.wlCopy, entry.text]);
                                    meta.copied = true;
                                }
                            }
                        }
                    }
                }
            }

            Component {
                id: toolView

                Row {
                    spacing: 10
                    height: 18

                    Rectangle {
                        id: dot
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6
                        height: 6
                        radius: 3
                        color: entry.status === "failed" ? Tokens.interrupt : entry.status === "running" ? Tokens.ink : Tokens.muted

                        SequentialAnimation on opacity {
                            running: entry.status === "running"
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) dot.opacity = 1
                            NumberAnimation { to: 0.2; duration: 420 }
                            NumberAnimation { to: 1; duration: 420 }
                        }
                    }

                    Txt {
                        anchors.verticalCenter: parent.verticalCenter
                        width: entry.width - 16
                        text: root.toolText(entry.name, entry.status, entry.info)
                        color: entry.status === "running" ? Tokens.dim : Tokens.muted
                        font.family: Tokens.fontMono
                        font.pixelSize: 11
                    }
                }
            }

            Component {
                id: confirmView

                Rectangle {
                    id: card

                    readonly property var facts: { try { return JSON.parse(entry.info || "{}"); } catch (e) { return {}; } }
                    readonly property bool open: entry.status === "asking"
                    readonly property bool isArmed: open && root.armed === entry.cid

                    width: Math.min(entry.width, 620)
                    height: content.implicitHeight + 32
                    radius: 18
                    color: Tokens.surface
                    border.width: 1
                    border.color: isArmed ? Tokens.interrupt : Tokens.line
                    opacity: open ? 1 : 0.55

                    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

                    Column {
                        id: content
                        x: 18
                        y: 16
                        width: card.width - 36
                        spacing: 8

                        Label {
                            text: "git · " + (card.facts.action === "commit-push" ? Lang.confirmCommitPush
                                : card.facts.action === "push" ? Lang.confirmPush : Lang.confirmCommit)
                            color: Tokens.ink
                        }

                        Txt {
                            width: parent.width
                            text: (card.facts.repo ?? "") + " · " + (card.facts.branch ?? "") + (card.facts.remote ? "  →  " + card.facts.remote : "")
                            color: Tokens.dim
                            font.family: Tokens.fontMono
                            font.pixelSize: 12
                        }

                        Column {
                            width: parent.width
                            spacing: 2

                            Repeater {
                                model: (card.facts.files ?? []).slice(0, 8)

                                Txt {
                                    required property string modelData
                                    width: parent.width
                                    text: modelData
                                    color: Tokens.muted
                                    font.family: Tokens.fontMono
                                    font.pixelSize: 12
                                }
                            }

                            Txt {
                                readonly property int rest: Math.max(0, (card.facts.files ?? []).length - 8) + (card.facts.more ?? 0)
                                visible: rest > 0
                                text: Lang.confirmMore.arg(rest)
                                color: Tokens.muted
                                font.family: Tokens.fontMono
                                font.pixelSize: 12
                            }

                            Txt {
                                visible: card.facts.action === "push" && (card.facts.ahead ?? 0) > 0
                                text: Lang.confirmAhead.arg(card.facts.ahead ?? 0)
                                color: Tokens.muted
                                font.family: Tokens.fontMono
                                font.pixelSize: 12
                            }
                        }

                        Txt {
                            width: parent.width
                            visible: (card.facts.message ?? "") !== ""
                            text: Lang.quoted.arg(card.facts.message ?? "")
                            color: Tokens.ink
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                            font.pixelSize: 14
                            topPadding: 4
                        }

                        Item { width: 1; height: 4 }

                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            visible: card.open

                            PillButton {
                                text: Lang.confirmCancel
                                onClicked: Nilo.answer(false)
                            }

                            Rectangle {
                                implicitWidth: okLabel.implicitWidth + 24
                                implicitHeight: 26
                                radius: 13
                                color: card.isArmed ? Tokens.interrupt : Tokens.ink

                                Label {
                                    id: okLabel
                                    anchors.centerIn: parent
                                    text: card.isArmed ? Lang.enterAgain : Lang.confirmOk
                                    color: card.isArmed ? Tokens.ink : Tokens.black
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Nilo.answer(true)
                                }
                            }
                        }

                        Label {
                            anchors.right: parent.right
                            visible: !card.open
                            text: entry.status === "ok" ? Lang.confirmDone : Lang.confirmDeclined
                        }
                    }
                }
            }

            Component {
                id: errorView

                Row {
                    spacing: 10

                    Rectangle {
                        y: 6
                        width: 6
                        height: 6
                        radius: 3
                        color: Tokens.interrupt
                    }

                    Txt {
                        width: entry.width - (download.visible ? download.width + 30 : 16)
                        text: root.errorText(entry.name, entry.text)
                        color: Tokens.dim
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 13
                    }

                    PillButton {
                        id: download
                        visible: entry.name === "model-missing" && !Nilo.installed && Nilo.pull === null
                        text: Lang.niloDownload
                        accent: true
                        onClicked: Nilo.download(Nilo.settings.model)
                    }
                }
            }

            Component {
                id: noteView

                Label {
                    text: Lang.niloStopped
                }
            }
        }

        // Nilo is on it and has not written yet: three LEDs taking turns.
        footer: Item {
            width: ListView.view.width
            height: typing.visible ? 34 : 0

            Row {
                id: typing
                y: 18
                spacing: 6
                visible: Nilo.busy && Nilo.phase !== "writing" && Nilo.phase !== "confirm"

                property int lit: 0

                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 6
                        height: 6
                        radius: 3
                        color: typing.lit === index ? Tokens.ink : Tokens.off
                    }
                }

                Timer {
                    running: typing.visible
                    interval: 260
                    repeat: true
                    onTriggered: typing.lit = (typing.lit + 1) % 3
                }
            }
        }
    }

    // Older lines fade out under the header instead of being cut.
    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 22
        visible: list.visible && !list.atYBeginning
        gradient: Gradient {
            GradientStop { position: 0; color: Tokens.black }
            GradientStop { position: 1; color: "transparent" }
        }
    }
}
