import QtQuick
import qs.theme

// A switch as a single LED: lit when on, like the launcher on the phone.
Rectangle {
    property bool on: false

    implicitWidth: 10
    implicitHeight: 10
    radius: width / 2
    color: on ? Tokens.ink : Tokens.off
    border.width: on ? 0 : 1
    border.color: Tokens.line

    Behavior on color { ColorAnimation { duration: Tokens.animFast } }
}
