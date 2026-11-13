import QtQuick
import qs.theme
import qs.config
import qs.services
import qs.components
import "Markdown.js" as Markdown

// What Nilo did while the launcher was closed, in a drawer that comes out of
// the bar next to its eyes (Frame.qml): the question, then the answer, the
// error, or what it is waiting to be confirmed. A click anywhere opens the
// conversation; it goes back into the bar on its own (services/Nilo.qml).
Item {
    id: root

    property bool shown: false      // this is the screen it is out on

    readonly property bool confirming: Nilo.peekKind === "confirm"
    readonly property bool failed: Nilo.peekKind === "error"
    readonly property bool risky: confirming && (Nilo.peekFacts.danger ?? []).length > 0
    readonly property real maxAnswer: 280

    readonly property var voices: ({ ink: String(Tokens.ink), dim: String(Tokens.dim), code: "#E6E6E6",
                                     surface: String(Tokens.surface), mono: Tokens.fontMono })

    implicitHeight: content.implicitHeight + 40

    // Moving over it keeps it out a moment longer.
    HoverHandler {
        onPointChanged: if (root.shown) Nilo.peekTouch()
    }

    Column {
        id: content
        x: 24
        y: 20
        width: root.width - 48
        spacing: 10

        Row {
            width: parent.width
            height: 18
            spacing: 10

            Eyes {
                anchors.verticalCenter: parent.verticalCenter
                eyeWidth: 4
                eyeHeight: 11
                gap: 5
                mood: root.confirming ? "alert" : root.failed ? "error" : "happy"
                live: Nilo.peeking
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 60
                text: (root.confirming ? Lang.niloPeekWaiting : root.failed ? Lang.niloPeekFailed : Lang.niloPeekDone)
                    + ((Nilo.peekFacts.model ?? "") !== "" ? " (" + Nilo.peekFacts.model + ")" : "")
                color: Tokens.dim
            }
        }

        Txt {
            width: parent.width
            visible: Nilo.peekQuestion !== ""
            text: "› " + Nilo.peekQuestion.replace(/\s+/g, " ")
            textFormat: Text.PlainText
            color: Tokens.muted
            font.pixelSize: 13
        }

        // The answer, as far as it fits; the rest is in the conversation.
        Item {
            id: answerBox
            width: parent.width
            height: Math.min(answer.implicitHeight, root.maxAnswer)
            visible: !root.confirming && Nilo.peekText !== ""
            clip: true

            readonly property bool cut: answer.implicitHeight > root.maxAnswer

            Text {
                id: answer
                width: parent.width
                text: Markdown.html(Nilo.peekText, root.voices)
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                color: root.failed ? Tokens.dim : Tokens.ink
                font.family: Tokens.fontSans
                font.pixelSize: 14
                lineHeight: 1.25
            }

            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 48
                visible: answerBox.cut
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Tokens.black }
                }
            }
        }

        // What it wants to do, as on its card in the conversation.
        Surface {
            visible: root.confirming
            width: parent.width
            height: visible ? waiting.implicitHeight + 20 : 0
            radius: 12
            color: Tokens.surface
            border.width: 1
            border.color: root.risky ? Tokens.interrupt : Tokens.line

            Txt {
                id: waiting
                x: 12
                y: 10
                width: parent.width - 24
                text: Nilo.peekText
                textFormat: Text.PlainText
                color: Tokens.ink
                font.family: Tokens.fontMono
                font.pixelSize: 12
                wrapMode: Text.WrapAnywhere
                elide: Text.ElideNone
                maximumLineCount: 6
            }
        }

        Label {
            topPadding: 2
            text: root.confirming ? Lang.niloPeekConfirm : answerBox.cut ? Lang.niloPeekMore : Lang.niloPeekOpen
            color: area.containsMouse ? Tokens.dim : Tokens.muted
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: Nilo.open()
    }

    // Back into the bar now.
    Ico {
        anchors.right: parent.right
        anchors.rightMargin: 18
        y: 20
        glyph: Icons.close
        font.pixelSize: 14
        color: closeArea.containsMouse ? Tokens.ink : Tokens.muted

        MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -8
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: Nilo.unpeek()
        }
    }
}
