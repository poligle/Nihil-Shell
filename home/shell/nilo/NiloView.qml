import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components

// Nilo inside the launcher ("?"): its face, and under it the conversation,
// the introduction (the first time) or the settings (the gear). The
// launcher's field stays the input and hands its keys here: accept(),
// key() and back() (escape).
Item {
    id: root

    property bool active: false
    property string question: ""    // what follows the "?"
    property real caret: 0.5        // where the caret is in the field, 0..1
    property string page: "chat"    // or "settings"
    property string armed: ""       // a confirmation waiting for its second enter

    signal cleared()                // the question went out: empty the field
    signal refocus()                // give the keyboard back to the field

    readonly property string view: !Nilo.enabled ? "off" : !Nilo.known ? "starting" : !Nilo.onboarded ? "intro" : page
    readonly property bool hero: view === "off" || view === "starting" || view === "intro"
        || (view === "chat" && Nilo.messages.count === 0)

    readonly property string hint: view === "off" || view === "starting" ? Lang.niloHintOff
        : view === "intro" ? Lang.niloHintIntro
        : view === "settings" ? Lang.niloHintSettings
        : Nilo.confirm ? Lang.niloHintConfirm
        : Nilo.busy ? Lang.niloHintBusy : Lang.niloHint

    property bool greeting: false

    readonly property string mood: {
        if (!Nilo.enabled) return "off";
        if (Nilo.mood === "error") return "error";
        if (Nilo.mood === "happy") return "happy";
        if (view === "starting") return "asleep";
        if (view === "intro") return greeting || intro.page === intro.pages - 1 ? "happy" : "idle";
        if (Nilo.phase === "confirm") return "alert";
        if (Nilo.busy && (Nilo.loading || !Nilo.loaded)) return "waking";
        if (Nilo.phase === "tool") return Nilo.tool === "web_search" || Nilo.tool === "open_url" ? "searching" : "thinking";
        if (Nilo.busy) return Nilo.phase === "writing" ? "writing" : "thinking";
        if (Nilo.loading) return "waking";
        if (!Nilo.loaded) return "asleep";
        return question.length > 0 ? "listening" : "idle";
    }

    readonly property string status: {
        if (!Nilo.ollama) return Lang.niloNoOllama;
        if (Nilo.pull && Nilo.pull.status !== "error") return Lang.niloDownloading.arg(Math.floor(Nilo.pull.progress * 100));
        if (Nilo.phase === "confirm") return Lang.niloWaitingYou;
        if (Nilo.busy && (Nilo.loading || !Nilo.loaded)) return Lang.niloWaking;
        if (Nilo.phase === "tool") return Lang.niloWorking;
        if (Nilo.busy) return Nilo.phase === "writing" ? Lang.niloWriting : Lang.niloThinking;
        if (Nilo.loading) return Lang.niloWaking;
        if (Nilo.loaded) return Lang.niloAwake.arg(Number(Nilo.sizeGB).toLocaleString(Qt.locale(Lang.locale), "f", 1));
        return Lang.niloAsleep;
    }

    // The first page of the introduction opens with a smile.
    function hello(): void {
        if (active && view === "intro" && intro.page === 0) {
            greeting = true;
            greet.restart();
        }
    }

    onActiveChanged: {
        if (active) {
            hello();
        } else {
            page = "chat";
            armed = "";
        }
    }
    onViewChanged: {
        if (view === "intro") intro.page = 0;
        hello();
    }

    Timer {
        id: greet
        interval: 1500
        onTriggered: root.greeting = false
    }

    Connections {
        target: Nilo
        function onConfirmChanged() { root.armed = ""; }
    }

    // --- From the launcher's field ---------------------------------------------

    function accept(text: string): void {
        if (view === "intro") return intro.next();
        if (view === "settings") return settings.activate();
        if (view !== "chat") return;
        if (Nilo.confirm) {
            if (text.trim() !== "") return;
            if (armed === Nilo.confirm.id) Nilo.answer(true);
            else armed = Nilo.confirm.id;
            return;
        }
        if (text.trim() === "" || Nilo.busy || !Nilo.installed) return;
        chat.toEnd();
        Nilo.ask(text);
        cleared();
    }

    function key(event: var): bool {
        const k = event.key;
        const up = k === Qt.Key_Up || k === Qt.Key_Backtab;
        const down = k === Qt.Key_Down || k === Qt.Key_Tab;
        if (view === "intro") {
            if (up || down) return intro.move(up ? -1 : 1);
            if (k === Qt.Key_Space) { intro.toggle(); return true; }
            return false;
        }
        if (view === "settings") {
            if (up || down) { settings.move(up ? -1 : 1); return true; }
            if (k === Qt.Key_Space) { settings.activate(); return true; }
            if (k === Qt.Key_Left || k === Qt.Key_Right) {
                if (root.question.length > 0) return false;
                settings.sleepStep(k === Qt.Key_Left ? -1 : 1);
                return true;
            }
            return false;
        }
        if (view === "chat") {
            if ((event.modifiers & Qt.ControlModifier) && k === Qt.Key_N) { Nilo.reset(); return true; }
            if (k === Qt.Key_PageUp || k === Qt.Key_PageDown) { chat.scroll((k === Qt.Key_PageUp ? -0.8 : 0.8) * chat.height); return true; }
            if (k === Qt.Key_Up || k === Qt.Key_Down) { chat.scroll(k === Qt.Key_Up ? -60 : 60); return true; }
        }
        return false;
    }

    // true when it was for Nilo; false lets the launcher close.
    function back(): bool {
        if (view === "settings") { page = "chat"; return true; }
        if (Nilo.confirm) { Nilo.answer(false); return true; }
        if (Nilo.busy) { Nilo.stop(); return true; }
        return false;
    }

    // --- Header -----------------------------------------------------------------

    Column {
        x: 4
        y: 12
        spacing: 4
        visible: root.view === "chat" || root.view === "settings"

        DotText {
            text: "NILO"
            font.pixelSize: 20
        }

        Label {
            text: (Nilo.settings.model ?? "") + " · " + root.status
        }
    }

    Row {
        anchors.right: parent.right
        y: 12
        spacing: 8

        CircleButton {
            glyph: Icons.plus
            size: 32
            visible: root.view === "chat" && Nilo.messages.count > 0
            onClicked: Nilo.reset()
        }

        CircleButton {
            glyph: Icons.cog
            size: 32
            visible: root.view === "chat" || root.view === "settings"
            filled: root.view === "settings"
            onClicked: root.page = root.page === "settings" ? "chat" : "settings"
        }
    }

    // --- The face ---------------------------------------------------------------

    HoverHandler { id: pointer }

    Eyes {
        id: face

        readonly property real centerX: x + width / 2
        readonly property real centerY: y + height / 2
        readonly property real heroY: root.view === "intro" ? 6
            : root.view === "chat" ? body.y + body.height * 0.5 - 10 - 34 - 76
            : root.height * 0.5 - 76

        mood: root.mood
        pulse: Nilo.pulse
        eyeWidth: root.hero ? 30 : 13
        eyeHeight: root.hero ? 76 : 32
        gap: root.hero ? 46 : 20
        x: (root.width - width) / 2
        y: root.hero ? heroY : 16
        looking: pointer.hovered && root.question.length === 0
        lookX: root.question.length > 0 ? root.caret * 1.2 - 0.6
            : (pointer.point.position.x - centerX) / Math.max(1, root.width / 2)
        lookY: (pointer.point.position.y - centerY) / Math.max(1, root.height / 2)

        Behavior on eyeWidth { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on eyeHeight { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on gap { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 380; easing.type: Easing.OutCubic } }
    }

    // --- Below it ---------------------------------------------------------------

    Item {
        id: body
        width: parent.width
        y: root.view === "intro" ? 96 : 64
        height: Math.max(0, parent.height - y)

        Chat {
            id: chat
            anchors.fill: parent
            visible: root.view === "chat"
            armed: root.armed
            onSuggest: text => {
                chat.toEnd();
                Nilo.ask(text);
            }
        }

        Intro {
            id: intro
            anchors.fill: parent
            visible: root.view === "intro"
        }

        Settings {
            id: settings
            anchors.fill: parent
            visible: root.view === "settings"
            onDone: {
                root.page = "chat";
                root.refocus();
            }
        }

        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            y: face.y + face.height + 34 - body.y
            spacing: 10
            visible: root.view === "off"

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.niloOff
                font.pixelSize: 20
            }

            Txt {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Lang.niloOffHow
                color: Tokens.muted
                font.family: Tokens.fontMono
                font.pixelSize: 12
            }
        }
    }
}
