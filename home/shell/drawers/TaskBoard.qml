import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.theme
import qs.config
import qs.services
import qs.components

// The dashboard's kanban (services/Tasks.qml): to do, doing, done. The field
// adds to "to do"; a click on a card moves it on, its arrows move it either
// way, the pencil writes it again where it is and the cross deletes it. A card
// dragged goes where it is dropped, in its column or another: a line shows where.
//
// A card is as tall as its text: a long task wraps instead of ending in
// "…". The board is as tall as its fullest column, up to `maxList` (the
// wheel scrolls the rest); with no tasks it is just the field and one
// line. The dashboard and its drawer follow `implicitHeight` (Frame.qml).
Item {
    id: root

    property bool active: false

    readonly property var titles: [Lang.tasksTodo, Lang.tasksDoing, Lang.tasksDone]

    readonly property real maxList: 210
    readonly property bool empty: Tasks.cards.length === 0
    // The cards of the fullest column, end to end (each column says how
    // tall its own are).
    readonly property real tallest: {
        let most = 30;
        for (let i = 0; i < columnsRow.children.length; i++) {
            const lane = columnsRow.children[i];
            if (lane.column !== undefined)
                most = Math.max(most, lane.needed);
        }
        return most;
    }

    implicitHeight: header.implicitHeight + 12 + (empty ? hint.implicitHeight
        : laneProbe.implicitHeight + 10 + Math.min(maxList, tallest) + (tallest > maxList + 1 ? 14 : 0))

    // A card being dragged: its id and text, the column under the pointer and
    // where in it the card would end up (counted without it), the line that
    // shows that place, and where the pointer is, in this item.
    property string dragId: ""
    property string dragText: ""
    property int dropColumn: -1
    property int dropIndex: -1
    property rect dropLine: Qt.rect(0, 0, 0, 0)
    property point dragAt: Qt.point(0, 0)
    // The card whose text the pencil is writing again, and its field.
    property string editingId: ""
    property Item editor: null

    onActiveChanged: if (!active) {
        field.text = "";
        field.focus = false;
        dragId = "";
        stopEditing();
    }

    // Ends the pencil keeping what was written: a click elsewhere, the drawer closing.
    function stopEditing(): void {
        if (editor) editor.finish();
        editingId = "";
    }

    // Ends a drag where it is aimed, if anywhere. Clears the drag first: the
    // move destroys the card whose handler calls this.
    function drop(): void {
        const id = dragId, to = dropColumn, at = dropIndex;
        dragId = "";
        dropColumn = -1;
        dropIndex = -1;
        if (id !== "" && to >= 0) Tasks.place(id, to, at >= 0 ? at : Tasks.inColumn(to).length);
    }

    // Where in the column under the pointer the dragged card would end up, and
    // the line between two cards that shows it.
    function aim(y: real): void {
        const lane = laneOf(dropColumn);
        const slot = lane ? lane.slot(y) : null;
        dropIndex = slot ? slot.index : -1;
        if (slot) dropLine = Qt.rect(slot.x, slot.y, slot.width, 2);
    }

    function laneOf(column: int): var {
        for (let i = 0; i < columnsRow.children.length; i++) {
            const lane = columnsRow.children[i];
            if (lane.column === column) return lane;
        }
        return null;
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

    // The height of a column's title, for implicitHeight.
    Label {
        id: laneProbe
        visible: false
        text: "0"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        // Title, count and the field for a new task.
        RowLayout {
            id: header
            Layout.fillWidth: true
            spacing: 12

            Label {
                text: Lang.tasks + " (" + Tasks.cards.filter(c => c.column < 2).length + ")"
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
                    radius: 8
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

        // With no tasks at all, how it works.
        Txt {
            id: hint
            Layout.fillWidth: true
            visible: root.empty
            text: Lang.tasksEmpty
            color: Tokens.muted
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            font.pixelSize: 12
            lineHeight: 1.2
        }

        RowLayout {
            id: columnsRow
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: !root.empty
            spacing: 18

            Repeater {
                model: Tasks.columns

                Item {
                    id: lane

                    required property int index
                    readonly property int column: index
                    readonly property var cards: Tasks.inColumn(index)
                    readonly property bool target: root.dragId !== "" && root.dropColumn === index
                    readonly property real needed: list.contentHeight

                    // Where a card dropped at [y] (in the board) ends up among this
                    // column's cards, counted without the one dragged, and the line
                    // for it, in the board: between two cards, or at an end.
                    function slot(y: real): var {
                        const at = list.contentItem.mapFromItem(root, 0, y).y;
                        let index = 0, line = 0, seen = false;
                        for (let i = 0; i < lane.shown.length; i++) {
                            if (lane.shown[i].id === root.dragId) continue;
                            const item = list.itemAtIndex(i);
                            if (!item) {
                                if (seen) break;
                                index++;
                                continue;
                            }
                            seen = true;
                            if (at < item.y + item.height / 2) {
                                line = item.y - list.spacing / 2;
                                break;
                            }
                            index++;
                            line = item.y + item.height + list.spacing / 2;
                        }
                        const top = list.mapToItem(root, 0, 0);
                        const y2 = list.contentItem.mapToItem(root, 0, line).y;
                        return { index: index, x: top.x, y: Math.min(Math.max(y2, top.y), top.y + list.height) - 1, width: list.width };
                    }

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
                            text: root.titles[lane.column] + " (" + lane.cards.length + ")"
                            color: lane.column === 1 && lane.cards.length > 0 ? Tokens.dim : Tokens.muted
                        }

                        Item { Layout.fillWidth: true }

                        // The done ones away, with the notifications' broom.
                        CircleButton {
                            visible: lane.column === 2 && lane.cards.length > 0
                            glyph: Icons.broom
                            label: Lang.tasksClear
                            size: 22
                            onClicked: Tasks.clearDone()
                        }
                    }

                    // As many cards as fit; the wheel scrolls the rest.
                    ListView {
                        id: list
                        anchors.top: laneHead.bottom
                        anchors.topMargin: 10
                        width: parent.width
                        height: Math.max(0, lane.height - laneHead.height - 10)
                        clip: true
                        spacing: 6
                        boundsBehavior: Flickable.StopAtBounds
                        snapMode: ListView.SnapToItem
                        model: lane.shown

                        delegate: Rectangle {
                            id: card

                            required property var modelData
                            readonly property bool done: modelData.column === 2
                            readonly property bool editing: root.editingId === modelData.id

                            width: ListView.view.width
                            height: Math.max(30, (editing ? editor.implicitHeight : label.implicitHeight) + 14)
                            radius: 10
                            color: hover.hovered ? Tokens.raised : Tokens.surface
                            border.width: 1
                            border.color: Tokens.line
                            opacity: root.dragId === modelData.id ? 0.3 : 1

                            HoverHandler { id: hover }

                            // A click moves it on; done ones go back to "to do".
                            MouseArea {
                                anchors.fill: parent
                                enabled: !card.editing
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Tasks.move(card.modelData.id, card.done ? 0 : card.modelData.column + 1)
                            }

                            DragHandler {
                                id: drag
                                target: null
                                enabled: !card.editing
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
                                    root.aim(p.y);
                                }
                            }

                            // With the first line of the text, however many it has.
                            Rectangle {
                                id: led
                                anchors.left: parent.left
                                anchors.leftMargin: 12
                                anchors.top: label.top
                                anchors.topMargin: (lineMetrics.height - height) / 2
                                width: 6
                                height: 6
                                radius: 3
                                color: card.modelData.column === 1 ? Tokens.ink : card.done ? Tokens.muted : "transparent"
                                border.width: card.modelData.column === 0 ? 1 : 0
                                border.color: Tokens.muted
                            }

                            Txt {
                                id: label
                                anchors.left: led.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.top: parent.top
                                anchors.topMargin: 7
                                visible: !card.editing
                                text: card.modelData.text
                                color: card.done ? Tokens.muted : Tokens.ink
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                                verticalAlignment: Text.AlignTop
                                font.pixelSize: 13
                                font.strikeout: card.done
                            }

                            FontMetrics {
                                id: lineMetrics
                                font: label.font
                            }

                            // The pencil: the text written again where it is. Enter keeps
                            // it, and so does a click anywhere else; Escape leaves it as it was.
                            QQC.TextArea {
                                id: editor
                                visible: card.editing
                                anchors.left: led.right
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.top: parent.top
                                anchors.topMargin: 7
                                padding: 0
                                background: null
                                wrapMode: TextEdit.Wrap
                                color: Tokens.ink
                                selectionColor: Tokens.ink
                                selectedTextColor: Tokens.black
                                font.family: Tokens.fontSans
                                font.pixelSize: 13

                                property bool keeping: true

                                onVisibleChanged: if (visible) {
                                    root.editor = editor;
                                    keeping = true;
                                    text = card.modelData.text;
                                    forceActiveFocus();
                                    cursorPosition = length;
                                }

                                // Clears the pencil first: the edit makes the card again.
                                function finish(): void {
                                    if (!card.editing) return;
                                    const id = card.modelData.id, typed = text;
                                    root.editor = null;
                                    root.editingId = "";
                                    if (keeping) Tasks.edit(id, typed);
                                }

                                Keys.onReturnPressed: event => { event.accepted = true; finish(); }
                                Keys.onEnterPressed: event => { event.accepted = true; finish(); }
                                Keys.onEscapePressed: event => { event.accepted = true; keeping = false; finish(); }
                                onActiveFocusChanged: if (!activeFocus) finish()
                            }

                            // Back, on, pencil, delete: on hover, over the end of the first
                            // line (moving the text aside would wrap it again under the pointer).
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 4
                                anchors.top: parent.top
                                anchors.topMargin: 4
                                width: tools.width + 8
                                height: tools.height
                                radius: 8
                                color: card.color
                                visible: hover.hovered && root.dragId === "" && !card.editing

                                Row {
                                    id: tools
                                    anchors.centerIn: parent
                                    spacing: 2

                                    Repeater {
                                        model: [
                                            { glyph: Icons.chevronLeft, show: card.modelData.column > 0, step: -1 },
                                            { glyph: Icons.chevron, show: card.modelData.column < 2, step: 1 },
                                            { glyph: Icons.pencil, show: true, step: 2 },
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
                                                    const step = parent.modelData.step;
                                                    if (step === 2) root.editingId = card.modelData.id;
                                                    else if (step === 0) Tasks.remove(card.modelData.id);
                                                    else Tasks.move(card.modelData.id, card.modelData.column + step);
                                                }
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

    // While a card is written again, a click anywhere else on the board keeps it and ends
    // there; one on the card's own text goes through, to the text.
    MouseArea {
        id: outside
        anchors.fill: parent
        z: 20
        visible: root.editingId !== ""
        onPressed: mouse => {
            const field = root.editor;
            if (field && field.contains(field.mapFromItem(outside, mouse.x, mouse.y))) {
                mouse.accepted = false;
                return;
            }
            root.stopEditing();
        }
    }

    // Where the dragged card would land: a line between two, in its column or another.
    Rectangle {
        visible: root.dragId !== "" && root.dropIndex >= 0
        x: root.dropLine.x
        y: root.dropLine.y
        width: root.dropLine.width
        height: 2
        radius: 1
        color: Tokens.ink
        z: 9
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
