import QtQuick
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components
import "Markdown.js" as Markdown

// The conversation: your questions after "›", Nilo's answers in Markdown,
// what its tools do as small lines with an LED (a command with its last lines
// under it), and the confirmations (git, a change to a file with its diff, a
// command exactly as it will run) as cards. Empty, it suggests a few
// questions; without Ollama, it says what systemd knows and offers to start it.
Item {
    id: root

    property string armed: ""       // the confirmation armed by a first enter
    property bool follow: true      // stick to the end while it writes
    // Empty, Nilo's face sits above what it says (NiloView.qml): this much
    // room is left for it, and the two are centred together.
    property real faceRoom: 0

    signal suggest(string text)

    // Where the empty conversation (or what Ollama is up to) starts.
    readonly property real emptyTop: Math.max(faceRoom,
        (height - faceRoom - (empty.visible ? empty.implicitHeight : down.implicitHeight)) / 2 + faceRoom)

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
        case "list_files":
            return running ? Lang.toolListing : Lang.toolListed.arg(data.count ?? 0);
        case "read_file":
            return running ? Lang.toolOpening.arg(args.path ?? "") : Lang.toolOpened.arg(data.path ?? args.path ?? "").arg(data.lines ?? 0);
        case "edit_file":
        case "write_file":
            if (running) return Lang.toolChanging.arg(args.path ?? "");
            if (data.declined) return Lang.toolDeclined;
            return data.created ? Lang.toolCreated.arg(data.path ?? "").arg(data.added ?? 0)
                : Lang.toolChanged.arg(data.path ?? "").arg(data.added ?? 0).arg(data.removed ?? 0);
        case "run_command": {
            const line = String(args.command ?? "").split("\n")[0];
            const command = line.length > 48 ? line.slice(0, 47) + "…" : line;
            if (running) return Lang.toolRunning.arg(command);
            if (data.declined) return Lang.toolDeclined;
            if (data.terminal) return Lang.toolInTerminal.arg(command);
            return data.exit === 0 ? Lang.toolRanOk.arg(command) : Lang.toolRanFail.arg(command).arg(data.exit ?? "?");
        }
        case "open_app":
            return running ? Lang.toolLaunching.arg(args.target ?? "") : Lang.toolLaunched.arg(data.opened || args.target || "");
        }
        return name;
    }

    // Why a command's card is red (agent.py, RISKS).
    function dangerText(code: string): string {
        switch (code) {
        case "root": return Lang.dangerRoot;
        case "delete": return Lang.dangerDelete;
        case "disk": return Lang.dangerDisk;
        case "git": return Lang.dangerGit;
        case "power": return Lang.dangerPower;
        case "system": return Lang.dangerSystem;
        case "permissions": return Lang.dangerPermissions;
        case "internet": return Lang.dangerInternet;
        }
        return code;
    }

    // What systemd says about Ollama, in one line: "ollama.service: failed (exit-code)".
    function unitLine(): string {
        const s = Nilo.service;
        if (!s.activeState) return "";
        const why = s.result && s.result !== "success" ? s.result : s.subState;
        return (s.unit ? s.unit + ": " : "") + (s.activeState ?? "") + (why ? " (" + why + ")" : "");
    }

    function errorText(code: string, detail: string): string {
        return Nilo.errorText(code, detail);
    }

    // Empty: a greeting, a line and some questions to start with.
    Column {
        id: empty
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.emptyTop
        width: Math.min(620, parent.width - 48)
        spacing: 10
        visible: Nilo.messages.count === 0 && (Nilo.ollama || !Nilo.known)
        opacity: visible ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

        readonly property bool downloading: Nilo.pull !== null && Nilo.pull.status !== "error"
            && Nilo.pull.model === (Nilo.settings.model ?? "")

        // For the time of day, with the user's first name (settings.json's
        // fullName): one of a few, chosen each time the conversation is
        // empty again. Without a name, the greeting goes without it.
        property string greeting: ""

        function greet(): void {
            const hour = new Date().getHours();
            const options = (hour < 6 ? Lang.niloGreetNight : hour < 13 ? Lang.niloGreetMorning
                : hour < 20 ? Lang.niloGreetAfternoon : Lang.niloGreetEvening).split("|");
            const pick = options[Math.floor(Math.random() * options.length)];
            greeting = Config.greeting !== "" ? pick.arg(Config.greeting) : pick.replace(/[,\s]*%1/, "");
        }

        onVisibleChanged: if (visible) greet()
        Component.onCompleted: greet()

        DotText {
            id: hello
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.min(implicitWidth, parent.width)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: empty.greeting
            font.pixelSize: 30
        }

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Nilo.installed ? (Nilo.settings.web ? Lang.niloEmpty : Lang.niloEmptyOffline)
                : parent.downloading ? Lang.niloDownloadingModel.arg(Nilo.settings.model).arg(Math.floor(Nilo.pull.progress * 100))
                : Lang.niloErrModel.arg(Nilo.settings.model ?? "")
            color: Tokens.dim
            font.pixelSize: 15
        }

        // A pause between what Nilo says and what can be done.
        Item {
            width: 1
            height: 16
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

        KeyButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Nilo.installed && !parent.downloading && Nilo.known
            text: Lang.niloDownload
            accent: true
            onClicked: Nilo.download(Nilo.settings.model)
        }

        // Questions to start with: plain lines, lit on hover.
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Nilo.installed

            Repeater {
                model: [
                    { text: Lang.niloTryFlake, on: true },
                    { text: Lang.niloTryNews, on: Nilo.settings.web === true },
                    { text: Lang.niloTryDisk, on: Nilo.settings.system === true },
                    { text: Lang.niloTryShell, on: Nilo.settings.shell === true },
                    { text: Lang.niloTryApps, on: Nilo.settings.apps === true },
                    { text: Lang.niloTryFiles, on: Nilo.settings.write === true },
                    { text: Lang.niloTryPush, on: Nilo.settings.git === true }
                ].filter(s => s.on).slice(0, 5)

                Txt {
                    required property var modelData

                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 28
                    text: modelData.text
                    color: tryArea.containsMouse ? Tokens.ink : Tokens.dim
                    font.pixelSize: 13

                    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

                    MouseArea {
                        id: tryArea
                        anchors.fill: parent
                        anchors.leftMargin: -10
                        anchors.rightMargin: -10
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.suggest(parent.modelData.text)
                    }
                }
            }
        }
    }

    // Without Ollama nothing works: what systemd and the journal say, and a
    // button to start it (the agent has already tried once on its own).
    Column {
        id: down
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.emptyTop
        width: Math.min(620, parent.width - 48)
        spacing: 12
        visible: Nilo.messages.count === 0 && !Nilo.ollama && Nilo.known

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Nilo.startingOllama ? Lang.niloOllamaStarting : Lang.niloOllamaDown
            color: Tokens.dim
            font.pixelSize: 15
        }

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== "" && !Nilo.startingOllama
            text: root.unitLine()
            color: Tokens.muted
            font.family: Tokens.fontMono
            font.pixelSize: 12
        }

        Column {
            width: parent.width
            spacing: 3
            visible: !Nilo.startingOllama && (Nilo.service.log ?? []).length > 0
            topPadding: 2

            Repeater {
                model: (Nilo.service.log ?? []).slice(-4)

                Txt {
                    required property string modelData
                    width: parent.width
                    text: modelData
                    horizontalAlignment: Text.AlignHCenter
                    color: Tokens.muted
                    font.family: Tokens.fontMono
                    font.pixelSize: 11
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 2
                }
            }
        }

        Txt {
            width: parent.width
            visible: !Nilo.startingOllama && (Nilo.service.error ?? "") !== ""
            text: Nilo.service.error ?? ""
            horizontalAlignment: Text.AlignHCenter
            color: Tokens.dim
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 13
        }

        Item { width: 1; height: 2 }

        KeyButton {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: !Nilo.startingOllama
            text: Lang.niloStartOllama
            accent: true
            onClicked: Nilo.startOllama()
        }

        Txt {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Lang.niloOllamaHelp
            color: Tokens.muted
            font.family: Tokens.fontMono
            font.pixelSize: 11
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

                    // The answer in its parts (Markdown.segments): the prose as
                    // rich text, each block of code on its own (CodeBlock.qml).
                    // While it writes, a part keeps its item and only its text
                    // changes; an item is made only for a new part.
                    Column {
                        id: reply
                        width: entry.width
                        spacing: 6

                        readonly property var parts: Markdown.segments(entry.text)

                        Repeater {
                            model: reply.parts.length

                            Item {
                                id: part

                                required property int index
                                readonly property var segment: reply.parts[index] ?? ({ kind: "text", text: "" })
                                readonly property bool isCode: segment.kind === "code"

                                width: reply.width
                                height: isCode ? block.height + 4 : prose.height

                                Text {
                                    id: prose
                                    visible: !part.isCode
                                    width: parent.width
                                    text: part.isCode ? "" : Markdown.html(part.segment.text, root.voices)
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
                                        cursorShape: prose.hoveredLink ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    }
                                }

                                CodeBlock {
                                    id: block
                                    visible: part.isCode
                                    width: parent.width
                                    code: part.isCode ? part.segment.text : ""
                                    language: part.isCode ? part.segment.language : ""
                                }
                            }
                        }
                    }

                    Row {
                        id: meta
                        visible: entry.done && entry.text !== ""
                        spacing: 14

                        readonly property var stats: { try { return JSON.parse(entry.info || "{}"); } catch (e) { return {}; } }

                        // Which model answered, when Nilo picks it.
                        Label {
                            visible: Nilo.settings.auto === true && (meta.stats.model ?? "") !== ""
                            text: meta.stats.model ?? ""
                            color: Tokens.muted
                        }

                        Label {
                            visible: (meta.stats.tokens ?? 0) > 0 && (meta.stats.seconds ?? 0) > 0
                            text: Lang.niloRate.arg(Math.round(meta.stats.tokens / meta.stats.seconds))
                            color: Tokens.muted
                        }

                        // The whole answer, as it was written.
                        CopyButton {
                            text: entry.text
                        }
                    }
                }
            }

            Component {
                id: toolView

                Column {
                    spacing: 6

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

                    // A command's last lines: live while it runs, then the end.
                    Rectangle {
                        x: 16
                        visible: entry.name === "run_command" && entry.text !== ""
                        width: Math.min(entry.width - 16, 620)
                        height: visible ? output.implicitHeight + 16 : 0
                        radius: 10
                        color: Tokens.black
                        border.width: 1
                        border.color: Tokens.line

                        Txt {
                            id: output
                            x: 12
                            y: 8
                            width: parent.width - 24
                            text: entry.text
                            textFormat: Text.PlainText
                            color: entry.status === "running" ? Tokens.dim : Tokens.muted
                            font.family: Tokens.fontMono
                            font.pixelSize: 11
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideNone
                            maximumLineCount: 8
                        }
                    }
                }
            }

            Component {
                id: confirmView

                Rectangle {
                    id: card

                    readonly property var facts: { try { return JSON.parse(entry.info || "{}"); } catch (e) { return {}; } }
                    readonly property bool file: facts.action === "edit" || facts.action === "create"
                    readonly property bool command: facts.action === "run" || facts.action === "terminal"
                    readonly property bool risky: command && (facts.danger ?? []).length > 0
                    readonly property bool open: entry.status === "asking"
                    readonly property bool isArmed: open && root.armed === entry.cid

                    width: Math.min(entry.width, 620)
                    height: content.implicitHeight + 32
                    radius: 18
                    color: Tokens.surface
                    border.width: 1
                    border.color: isArmed || (open && risky) ? Tokens.interrupt : Tokens.line
                    opacity: open ? 1 : 0.55

                    Behavior on opacity { NumberAnimation { duration: Tokens.animNormal } }

                    Column {
                        id: content
                        x: 18
                        y: 16
                        width: card.width - 36
                        spacing: 8

                        Label {
                            text: card.file ? (card.facts.action === "create" ? Lang.confirmCreate : Lang.confirmEdit) + " " + Lang.confirmFile
                                : card.command ? Lang.confirmRun + (card.facts.action === "terminal" ? " " + Lang.confirmTerminal : "")
                                : "git " + (card.facts.action === "commit-push" ? Lang.confirmCommitPush
                                    : card.facts.action === "push" ? Lang.confirmPush : Lang.confirmCommit)
                            color: Tokens.ink
                        }

                        Txt {
                            width: parent.width
                            text: card.file
                                ? (card.facts.repo ?? "") + "/" + (card.facts.path ?? "") + "   +" + (card.facts.added ?? 0)
                                    + ((card.facts.removed ?? 0) > 0 ? " −" + card.facts.removed : "")
                                : card.command ? (card.facts.cwd ?? "")
                                : (card.facts.repo ?? "") + " (" + (card.facts.branch ?? "") + ")" + (card.facts.remote ? "  →  " + card.facts.remote : "")
                            color: Tokens.dim
                            font.family: Tokens.fontMono
                            font.pixelSize: 12
                        }

                        // The command, exactly as it will run.
                        Rectangle {
                            visible: card.command
                            width: parent.width
                            height: visible ? commandText.implicitHeight + 20 : 0
                            radius: 12
                            color: Tokens.black
                            border.width: 1
                            border.color: Tokens.line

                            Txt {
                                id: commandText
                                x: 12
                                y: 10
                                width: parent.width - 24
                                text: "$ " + (card.facts.command ?? "")
                                textFormat: Text.PlainText
                                color: Tokens.ink
                                font.family: Tokens.fontMono
                                font.pixelSize: 12
                                wrapMode: Text.WrapAnywhere
                                elide: Text.ElideNone
                            }
                        }

                        // What for, in Nilo's words.
                        Txt {
                            width: parent.width
                            visible: card.command && (card.facts.reason ?? "") !== ""
                            text: card.facts.reason ?? ""
                            textFormat: Text.PlainText
                            color: Tokens.dim
                            wrapMode: Text.Wrap
                            elide: Text.ElideNone
                            font.pixelSize: 13
                        }

                        // And what deserves a second look.
                        Row {
                            visible: card.risky
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: Tokens.interrupt
                            }

                            Label {
                                text: (card.facts.danger ?? []).map(code => root.dangerText(code)).join(", ")
                                color: Tokens.dim
                            }
                        }

                        // The change itself, as a diff: what goes in, what goes out.
                        Rectangle {
                            visible: card.file
                            width: parent.width
                            height: visible ? lines.implicitHeight + 20 : 0
                            radius: 12
                            color: Tokens.black
                            border.width: 1
                            border.color: Tokens.line

                            Column {
                                id: lines
                                x: 12
                                y: 10
                                width: parent.width - 24
                                spacing: 1

                                Repeater {
                                    // "···" between the parts of the file that change, not before the first.
                                    model: card.file ? (card.facts.diff ?? []).filter((d, i) => i > 0 || d.t !== "@") : []

                                    Txt {
                                        required property var modelData
                                        width: parent.width
                                        text: modelData.t === "@" ? "···"
                                            : (modelData.t === "+" ? "+ " : modelData.t === "-" ? "− " : "  ") + modelData.s.replace(/\t/g, "    ")
                                        color: modelData.t === "+" ? Tokens.ink : modelData.t === "-" ? Tokens.dim : Tokens.muted
                                        font.family: Tokens.fontMono
                                        font.pixelSize: 12
                                        font.strikeout: modelData.t === "-"
                                        wrapMode: Text.WrapAnywhere
                                        elide: Text.ElideNone
                                    }
                                }

                                Txt {
                                    visible: (card.facts.more ?? 0) > 0
                                    text: Lang.confirmMoreLines.arg(card.facts.more ?? 0)
                                    color: Tokens.muted
                                    font.family: Tokens.fontMono
                                    font.pixelSize: 12
                                    topPadding: 4
                                }
                            }
                        }

                        Column {
                            width: parent.width
                            spacing: 2
                            visible: !card.file && !card.command

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

                        // Nilo signs it too (nihil.nilo.coauthor).
                        Txt {
                            width: parent.width
                            visible: (card.facts.trailer ?? "") !== ""
                            text: card.facts.trailer ?? ""
                            textFormat: Text.PlainText
                            color: Tokens.muted
                            font.family: Tokens.fontMono
                            font.pixelSize: 11
                        }

                        Item { width: 1; height: 4 }

                        Row {
                            anchors.right: parent.right
                            spacing: 8
                            visible: card.open

                            KeyButton {
                                text: Lang.confirmCancel
                                onClicked: Nilo.answer(false)
                            }

                            KeyButton {
                                accent: !card.isArmed
                                danger: card.isArmed
                                text: card.isArmed ? Lang.enterAgain : Lang.confirmOk
                                onClicked: Nilo.answer(true)
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
                        width: entry.width - (download.visible ? download.width + 30 : start.visible ? start.width + 30 : 16)
                        text: root.errorText(entry.name, entry.text)
                        color: Tokens.dim
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 13
                    }

                    KeyButton {
                        id: download
                        visible: entry.name === "model-missing" && !Nilo.installed && Nilo.pull === null
                        text: Lang.niloDownload
                        accent: true
                        onClicked: Nilo.download(Nilo.settings.model)
                    }

                    KeyButton {
                        id: start
                        visible: entry.name === "ollama-down" && !Nilo.ollama && !Nilo.startingOllama
                        text: Lang.niloStartOllama
                        accent: true
                        onClicked: Nilo.startOllama()
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
