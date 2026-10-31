import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.theme
import qs.config
import qs.services
import qs.components

// The dashboard's kanban (services/Tasks.qml): to do, doing, done. The field
// adds to "to do"; a click on a card moves it on, its arrows move it either
// way and the cross deletes it; a card can also be dragged to a column.
Item {
    id: root

    property bool active: false

    readonly property var titles: [Lang.tasksTodo, Lang.tasksDoing, Lang.tasksDone]

    // A card being dragged: its id and text, the column under the pointer and
    // where the pointer is, in this item.
    property string dragId: ""
    property string dragText: ""
    property int dropColumn: -1
    property point dragAt: Qt.point(0, 0)

    onActiveChanged: if (!active) {
        field.text = "";
        field.focus = false;
        dragId = "";
    }

    // Ends a drag on the column under the pointer, if any. Clears the drag
    // first: the move destroys the card whose handler calls this.
    function drop(): void {
        const id = dragId, to = dropColumn;
        dragId = "";
        dropColumn = -1;
        if (id !== "" && to >= 0) Tasks.move(id, to);
    }

    function columnAt(x: real): int {
        for (let i = 0; i < columnsRow.children.length; i++) {
            const c = columnsRow.children[i];
            if (c.column === undefined) continue;
            const p = c.mapToItem(root, 0, 0);
            if (x >= p.x - 10 && x <= p.x + c.width + 10) return c.column;
        }
        return -1;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Title, count and the field for a new task.
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: Lang.tasks + " · " + Tasks.cards.filter(c => c.column < 2).length
            }

            Item { Layout.fillWidth: true }

            QQC.TextField {
                id: field
                Layout.preferredWidth: 300
                Layout.preferredHeight: 30
                placeholderText: "+ " + Lang.tasksAdd
                placeholderTextColor: Tokens.muted
                color: Tokens.ink
                selectionColor: Tokens.ink
                selectedTextColor: Tokens.black
                font.family: Tokens.fontSans
                font.pixelSize: 13
                leftPadding: 14
                rightPadding: 14
                maximumLength: Tasks.maxLength
                background: Rectangle {
                    radius: 15
                    color: field.activeFocus ? Tokens.surface : "transparent"
                    border.width: 1
                    border.color: field.activeFocus ? Tokens.muted : Tokens.line
                }
                onAccepted: {
                    Tasks.add(text);
                    text = "";
                }
                Keys.onEscapePressed: {
                    if (text !== "") text = "";
                    else Drawers.close();
                }
            }
        }

        RowLayout {
            id: columnsRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 18

            Repeater {
                model: Tasks.columns

                Item {
                    id: lane

                    required property int index
                    readonly property int column: index
                    readonly property var cards: Tasks.inColumn(index)
                    readonly property bool target: root.dragId !== "" && root.dropColumn === index

                    // What the list shows: replaced only when this column changes,
                    // so the others keep their scroll; a card added or moved here
                    // scrolls into view.
                    property var shown: []
                    Component.onCompleted: shown = cards
                    onCardsChanged: {
                        if (JSON.stringify(cards) === JSON.stringify(shown)) return;
                        const before = shown.map(c => c.id);
                        let fresh = -1;
                        for (let i = cards.length - 1; i >= 0 && fresh < 0; i--)
                            if (before.indexOf(cards[i].id) < 0) fresh = i;
                        shown = cards;
                        if (fresh >= 0 && root.active) Qt.callLater(() => list.positionViewAtIndex(fresh, ListView.Contain));
                    }

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 100

                    // Where a dragged card would land.
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -6
                        radius: 14
                        color: lane.target ? Tokens.surface : "transparent"
                        border.width: lane.target ? 1 : 0
                        border.color: Tokens.muted
                    }

                    RowLayout {
                        id: laneHead
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            implicitWidth: 6
                            implicitHeight: 6
                            radius: 3
                            color: lane.column === 1 ? Tokens.ink : lane.column === 2 ? Tokens.dim : "transparent"
                            border.width: lane.column === 0 ? 1 : 0
                            border.color: Tokens.muted
                        }

                        Label {
                            text: root.titles[lane.column] + " · " + lane.cards.length
                            color: lane.column === 1 && lane.cards.length > 0 ? Tokens.dim : Tokens.muted
                        }

                        Item { Layout.fillWidth: true }

                        Label {
                            visible: lane.column === 2 && lane.cards.length > 0
                            text: Lang.tasksClear
                            color: clearArea.containsMouse ? Tokens.ink : Tokens.muted

                            MouseArea {
                                id: clearArea
                                anchors.fill: parent
                                anchors.margins: -6
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Tasks.clearDone()
                            }
                        }
                    }

                    // With no tasks at all, how it works.
                    Txt {
                        anchors.top: laneHead.bottom
                        anchors.topMargin: 12
                        width: parent.width
                        visible: lane.column === 0 && Tasks.cards.length === 0
                        text: Lang.tasksEmpty
                        color: Tokens.muted
                        wrapMode: Text.Wrap
                        elide: Text.ElideNone
                        font.pixelSize: 12
                        lineHeight: 1.2
                    }

                    // As many whole cards as fit; the wheel scrolls the rest.
                    ListView {
                        id: list
                        readonly property real pitch: 30 + spacing
                        anchors.top: laneHead.bottom
                        anchors.topMargin: 10
                        width: parent.width
                        height: Math.max(0, Math.floor((lane.height - laneHead.height - 10 + spacing) / pitch) * pitch - spacing)
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        snapMode: ListView.SnapToItem
                        model: lane.shown

                        delegate: Rectangle {
                            id: card

                            required property var modelData
                            readonly property bool done: modelData.column === 2

                            width: ListView.view.width
                            height: 30
                            radius: 10
                            color: hover.hovered ? Tokens.raised : Tokens.surface
                            border.width: 1
                            border.color: Tokens.line
                            opacity: root.dragId === modelData.id ? 0.3 : 1

                            HoverHandler { id: hover }

                            // A click moves it on; done ones go back to "to do".
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Tasks.move(card.modelData.id, card.done ? 0 : card.modelData.column + 1)
                            }

                            DragHandler {
                                id: drag
                                target: null
                                onActiveChanged: {
                                    if (active) {
                                        root.dragId = card.modelData.id;
                                        root.dragText = card.modelData.text;
                                    } else {
                                        root.drop();
                                    }
                                }
                                onCentroidChanged: {
                                    if (!active) return;
                                    const p = card.mapToItem(root, centroid.position.x, centroid.position.y);
                                    root.dragAt = p;
                                    root.dropColumn = root.columnAt(p.x);
                                }
                            }

                            Rectangle {
                                id: led
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: card.modelData.column === 1 ? Tokens.ink : card.done ? Tokens.muted : "transparent"
                                border.width: card.modelData.column === 0 ? 1 : 0
                                border.color: Tokens.muted
                            }

                            Txt {
                                anchors.left: led.right
                                anchors.leftMargin: 10
                                anchors.right: tools.visible ? tools.left : parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                text: card.modelData.text
                                color: card.done ? Tokens.muted : Tokens.ink
                                font.pixelSize: 13
                                font.strikeout: card.done
                            }

                            // Back, on, delete: on hover.
                            Row {
                                id: tools
                                anchors.right: parent.right
                                anchors.rightMargin: 8
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                visible: hover.hovered && root.dragId === ""

                                Repeater {
                                    model: [
                                        { glyph: Icons.chevronLeft, show: card.modelData.column > 0, step: -1 },
                                        { glyph: Icons.chevron, show: card.modelData.column < 2, step: 1 },
                                        { glyph: Icons.close, show: true, step: 0 }
                                    ].filter(t => t.show)

                                    Ico {
                                        required property var modelData
                                        width: 22
                                        height: 22
                                        glyph: modelData.glyph
                                        font.pixelSize: 14
                                        color: toolArea.containsMouse ? (modelData.step === 0 ? Tokens.interrupt : Tokens.ink) : Tokens.dim

                                        MouseArea {
                                            id: toolArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (parent.modelData.step === 0) Tasks.remove(card.modelData.id);
                                                else Tasks.move(card.modelData.id, card.modelData.column + parent.modelData.step);
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // More cards below than fit: three dots under the column.
                    Row {
                        anchors.top: list.bottom
                        anchors.topMargin: 7
                        anchors.horizontalCenter: list.horizontalCenter
                        spacing: 4
                        visible: list.contentHeight > list.height + 1 && !list.atYEnd

                        Repeater {
                            model: 3

                            Rectangle {
                                width: 3
                                height: 3
                                radius: 1.5
                                color: Tokens.muted
                            }
                        }
                    }
                }
            }
        }
    }

    // The card under the pointer while it is dragged.
    Rectangle {
        visible: root.dragId !== ""
        x: root.dragAt.x - width / 2
        y: root.dragAt.y - height / 2
        width: Math.min(260, columnsRow.width / 3)
        height: 30
        radius: 10
        color: Tokens.raised
        border.width: 1
        border.color: Tokens.muted
        z: 10

        Txt {
            anchors.fill: parent
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            text: root.dragText
            font.pixelSize: 13
        }
    }
}
