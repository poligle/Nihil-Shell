import QtQuick
import qs.theme
import qs.services
import qs.components

// Battery as a column of ten LEDs. While charging a light scans upwards;
// below 15 % the LEDs turn red.
Item {
    id: root

    property int scan: -1

    implicitWidth: 18
    implicitHeight: meter.implicitHeight + 6 + percent.implicitHeight

    DotMeter {
        id: meter
        anchors.horizontalCenter: parent.horizontalCenter
        vertical: true
        count: 10
        dot: 5
        gap: 3
        value: Battery.level
        litColor: Battery.low ? Tokens.interrupt : Tokens.ink
        head: root.scan
    }

    Label {
        id: percent
        anchors.top: meter.bottom
        anchors.topMargin: 6
        anchors.horizontalCenter: parent.horizontalCenter
        text: String(Math.round(Battery.level * 100))
        font.letterSpacing: 0
        color: Battery.low ? Tokens.interrupt : Tokens.muted
    }

    Timer {
        running: Battery.charging && !Battery.full
        interval: 160
        repeat: true
        onTriggered: root.scan = root.scan >= 9 ? meter.lit : root.scan + 1
        onRunningChanged: if (!running) root.scan = -1
    }
}
