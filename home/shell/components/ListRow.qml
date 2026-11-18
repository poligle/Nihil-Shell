import QtQuick
import QtQuick.Layouts
import qs.theme

// A row of a list that does one thing when pressed: a network, a device, an output.
Surface {
    id: item

    property string glyph: ""
    property string title: ""
    property string detail: ""
    property bool current: false
    property bool busy: false

    signal clicked()

    Layout.fillWidth: true
    implicitHeight: 40
    radius: 10
    color: area.containsMouse ? Tokens.raised : "transparent"
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: item.title
    Accessible.description: item.detail
    Accessible.onPressAction: item.clicked()
    Keys.onReturnPressed: event => { if (!event.isAutoRepeat) item.clicked(); }
    Keys.onEnterPressed: event => { if (!event.isAutoRepeat) item.clicked(); }
    Keys.onSpacePressed: event => { if (!event.isAutoRepeat) item.clicked(); }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 10

        Ico { glyph: item.glyph; color: item.current ? Tokens.ink : Tokens.muted }

        Txt {
            Layout.fillWidth: true
            text: item.title
            color: item.current ? Tokens.ink : Tokens.dim
            font.weight: item.current ? Font.Medium : Font.Normal
        }

        Label {
            visible: !item.busy
            text: item.detail
        }

        Rectangle {
            visible: item.busy
            width: 6
            height: 6
            radius: 3
            color: Tokens.ink

            SequentialAnimation on opacity {
                running: item.busy
                loops: Animation.Infinite
                NumberAnimation { from: 1; to: 0.2; duration: 600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.2; to: 1; duration: 600; easing.type: Easing.InOutSine }
            }
        }
    }

    FocusRing {
        round: item.radius
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: item.clicked()
    }
}
