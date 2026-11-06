import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// Top drawer: the clipboard history (services/Clipboard.qml), newest first.
// While it is out it has the keyboard: its key again, Tab or the arrows go
// through the copies, letting go of the modifier, Enter or a click paste
// the one chosen, Escape leaves the clipboard as it was, Delete forgets
// one. The one chosen is lit: its LED on, its picture in colour, as the
// launcher's apps.
Item {
    id: root

    property bool active: false

    readonly property real rowHeight: 52

    // As deep as its copies (Frame.qml): one row at least, for "nothing yet".
    implicitHeight: 46 + Math.max(1, Clipboard.items.length) * rowHeight + 12

    onActiveChanged: if (active) keys.forceActiveFocus()

    Item {
        id: keys
        anchors.fill: parent
        focus: root.active

        Keys.onPressed: event => {
            const back = (event.modifiers & Qt.ShiftModifier) !== 0;
            if (event.key === Clipboard.keyCode || event.key === Qt.Key_Tab || event.key === Qt.Key_Down)
                Clipboard.step(back ? -1 : 1);
            else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up)
                Clipboard.step(-1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                Clipboard.paste();
            else if (event.key === Qt.Key_Escape)
                Clipboard.cancel();
            else if (event.key === Qt.Key_Delete)
                Clipboard.forgetChosen();
            else
                return;
            event.accepted = true;
        }

        // The modifier went down in the window that had the keyboard: its
        // release may come here or not. Hyprland says so either way.
        Keys.onReleased: event => {
            if (Clipboard.isModifier(event.key)) {
                Clipboard.released("view");
                event.accepted = true;
            }
        }
    }

    Label {
        x: 26
        y: 18
        text: Lang.bindClipboard
    }

    Txt {
        x: 26
        y: 46
        height: root.rowHeight
        visible: Clipboard.items.length === 0
        text: Lang.clipEmpty
        color: Tokens.muted
        font.pixelSize: 13
    }

    ListView {
        id: list
        anchors.fill: parent
        anchors.topMargin: 46
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.bottomMargin: 12
        clip: true
        interactive: contentHeight > height
        model: Clipboard.items
        currentIndex: Clipboard.index
        highlightMoveDuration: 0
        boundsBehavior: Flickable.StopAtBounds
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Item {
            id: row

            required property var modelData
            required property int index

            readonly property bool chosen: row.index === Clipboard.index
            readonly property string kind: modelData.kind
            readonly property bool hovered: area.containsMouse || forgetArea.containsMouse

            width: ListView.view.width
            height: root.rowHeight

            // The one chosen, raised: its corners follow the drawer's.
            Rectangle {
                anchors.fill: parent
                radius: Tokens.drawerRadius - 12
                color: row.chosen ? Tokens.raised : row.hovered ? Tokens.surface : "transparent"
            }

            MouseArea {
                id: area
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: Clipboard.pick(row.index)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 14

                // Lit for the one chosen.
                Rectangle {
                    Layout.preferredWidth: 6
                    Layout.preferredHeight: 6
                    radius: 3
                    color: row.chosen ? Tokens.ink : Tokens.off
                }

                // A picture: grey, and in colour once chosen.
                Item {
                    visible: row.kind === "image"
                    Layout.preferredWidth: 58
                    Layout.preferredHeight: 36

                    Rectangle {
                        anchors.fill: parent
                        radius: 6
                        color: Tokens.surface
                    }

                    Image {
                        id: picture
                        anchors.fill: parent
                        source: row.kind === "image" ? "file://" + row.modelData.file : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                        sourceSize.width: 116
                        sourceSize.height: 72
                    }

                    MultiEffect {
                        anchors.fill: parent
                        source: picture
                        visible: picture.status === Image.Ready
                        saturation: row.chosen ? 0 : -1
                        opacity: row.chosen ? 1 : 0.55
                        maskEnabled: true
                        maskSource: corners

                        Behavior on saturation { NumberAnimation { duration: Tokens.animFast } }
                        Behavior on opacity { NumberAnimation { duration: Tokens.animFast } }
                    }

                    Rectangle {
                        id: corners
                        anchors.fill: parent
                        radius: 6
                        visible: false
                        layer.enabled: true
                    }
                }

                // A colour: an LED of it.
                Rectangle {
                    visible: row.kind === "colour"
                    Layout.preferredWidth: 14
                    Layout.preferredHeight: 14
                    radius: 7
                    color: row.kind === "colour" ? row.modelData.text.trim() : "transparent"
                }

                Txt {
                    Layout.fillWidth: true
                    text: row.kind !== "image" ? row.modelData.text
                        : row.modelData.width > 0 ? Lang.clipPictureSize.arg(row.modelData.width).arg(row.modelData.height)
                        : row.modelData.format.toUpperCase()
                    color: row.chosen ? Tokens.ink : row.kind === "image" ? Tokens.muted : Tokens.dim
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    lineHeight: 1.15
                    font.family: row.kind === "colour" || row.kind === "image" ? Tokens.fontMono : Tokens.fontSans
                    font.pixelSize: row.kind === "colour" || row.kind === "image" ? 12 : 13
                }

                // Forgets it; there on hover, without moving the text.
                Ico {
                    glyph: Icons.close
                    font.pixelSize: 14
                    opacity: row.hovered ? 1 : 0
                    color: forgetArea.containsMouse ? Tokens.interrupt : Tokens.muted

                    MouseArea {
                        id: forgetArea
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: row.hovered
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Clipboard.forget(row.modelData.id)
                    }
                }
            }
        }
    }
}
