import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC
import qs.theme
import qs.config
import qs.services
import qs.components

Item {
    id: root

    property bool active: false

    readonly property var titles: [Lang.tasksTodo, Lang.tasksDoing, Lang.tasksDone]

    readonly property real maxList: 210
    readonly property bool empty: Tasks.cards.length === 0
    readonly property real tallest: {
        let most = 30;
        for (let i = 0; i < columnsRow.children.length; i++) {
            const lane = columnsRow.children[i];
            if (lane.column !== undefined)
                most = Math.max(most, lane.needed);
        }
        return most;
    }

    implicitHeight: header.implicitHeight + 12 + (empty ? 0
        : laneProbe.implicitHeight + 10 + Math.min(maxList, tallest) + (tallest > maxList + 1 ? 14 : 0))

    property string dragId: ""
    property string dragText: ""
    property int dropColumn: -1
    property int dropIndex: -1
    property rect dropLine: Qt.rect(0, 0, 0, 0)
    property point dragAt: Qt.point(0, 0)
    property string editingId: ""
    property Item editor: null

    onActiveChanged: if (!active) {
        field.text = "";
        field.focus = false;
        dragId = "";
        stopEditing();
    }

    function stopEditing(): void {
        if (editor) editor.finish();
        editingId = "";
    }

    function drop(): void {
        const id = dragId, to = dropColumn, at = dropIndex;
        dragId = "";
        dropColumn = -1;
        dropIndex = -1;
        if (id !== "" && to >= 0) Tasks.place(id, to, at >= 0 ? at : Tasks.inColumn(to).length);
    }

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

    Label {
        id: laneProbe
        visible: false
        text: "0"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

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
                background: Surface {
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

                    Surface {
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

                        CircleButton {
                            visible: lane.column === 2 && lane.cards.length > 0
                            glyph: Icons.broom
                            label: Lang.tasksClear
                            size: 22
                            onClicked: Tasks.clearDone()
                        }
                    }

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

                        delegate: Surface {
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

    Surface {
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
