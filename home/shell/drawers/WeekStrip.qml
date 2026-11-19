import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.theme
import qs.config
import qs.services
import qs.components

// The week ahead in the Dashboard: today and the six days after, a column each, with what the
// calendars subscribed to in Preferences hold for them.
RowLayout {
    id: root

    readonly property date today: clock.date
    // Those a day shows before saying how many more.
    readonly property int shown: 3

    spacing: 16

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Repeater {
        model: 7

        ColumnLayout {
            id: day

            required property int index
            readonly property date date: new Date(root.today.getFullYear(), root.today.getMonth(), root.today.getDate() + day.index)
            readonly property var events: Calendar.onDay(day.date.getFullYear(), day.date.getMonth(), day.date.getDate())

            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.alignment: Qt.AlignTop
            spacing: 6

            Label {
                text: day.index === 0 ? Lang.calToday : day.index === 1 ? Lang.calTomorrow : Calendar.dayName(day.date)
                color: day.index === 0 ? Tokens.ink : Tokens.muted
            }

            Repeater {
                model: day.events.slice(0, root.shown)

                RowLayout {
                    id: event

                    required property var modelData

                    Layout.fillWidth: true
                    spacing: 6

                    Txt {
                        visible: !event.modelData.allDay
                        text: Qt.formatTime(new Date(event.modelData.start * 1000), "HH:mm")
                        color: Tokens.dim
                        font.family: Tokens.fontMono
                        font.pixelSize: 11
                    }

                    Txt {
                        Layout.fillWidth: true
                        text: Calendar.title(event.modelData)
                        font.pixelSize: 12
                    }
                }
            }

            Txt {
                visible: day.events.length > root.shown
                text: Lang.calMore.arg(day.events.length - root.shown)
                color: Tokens.muted
                font.pixelSize: 11
            }

            // A day with nothing: one dot, unlit.
            Rectangle {
                Layout.topMargin: 6
                visible: day.events.length === 0
                implicitWidth: 4
                implicitHeight: 4
                radius: 2
                color: Tokens.off
            }
        }
    }
}
