import QtQuick
import qs.theme

Surface {
    id: root

    property string glyph: ""
    // What it does, in words: its name for a screen reader, and shown beside it after a moment
    // under the pointer, or while it has the keyboard's focus. A glyph alone says too little.
    required property string label
    property int size: 36
    property bool danger: false
    property bool filled: false
    readonly property alias hovered: area.containsMouse
    property bool lingered: false

    signal clicked()

    function press(event: var): void {
        if (!event.isAutoRepeat)
            root.clicked();
    }

    implicitWidth: size
    implicitHeight: size
    activeFocusOnTab: true
    radius: size / 2
    color: filled ? Tokens.ink : (area.containsMouse ? Tokens.raised : "transparent")
    border.width: filled ? 0 : 1
    border.color: danger ? Tokens.interrupt : Tokens.line

    Accessible.role: Accessible.Button
    Accessible.name: root.label
    Accessible.onPressAction: root.clicked()
    Keys.onReturnPressed: event => root.press(event)
    Keys.onEnterPressed: event => root.press(event)
    Keys.onSpacePressed: event => root.press(event)

    Behavior on color { ColorAnimation { duration: Tokens.animFast } }

    Ico {
        anchors.centerIn: parent
        glyph: root.glyph
        font.pixelSize: Math.round(root.size * 0.45)
        color: root.filled ? Tokens.black : (root.danger ? Tokens.interrupt : (area.containsMouse ? Tokens.ink : Tokens.dim))
    }

    FocusRing {
        round: root.radius
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        onExited: root.lingered = false
    }

    Timer {
        interval: 600
        running: area.containsMouse && !root.lingered
        onTriggered: root.lingered = true
    }

    Surface {
        id: tip

        // Above, unless the window ends there.
        property bool below: false

        visible: root.label !== "" && (root.lingered || root.activeFocus)
        onVisibleChanged: {
            if (visible)
                below = root.mapToItem(null, 0, 0).y < height + 12;
        }
        z: 10
        anchors.horizontalCenter: parent.horizontalCenter
        y: below ? parent.height + 8 : -height - 8
        width: words.implicitWidth + 16
        height: words.implicitHeight + 8
        radius: 6
        color: Tokens.raised
        border.width: 1
        border.color: Tokens.line

        Label {
            id: words
            anchors.centerIn: parent
            text: root.label
            color: Tokens.ink
        }
    }
}
