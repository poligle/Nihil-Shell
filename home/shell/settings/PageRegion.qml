import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// Language, keyboard and time zone.
Flickable {
    id: page

    readonly property var layouts: ["es", "us", "gb", "latam", "fr", "de", "it", "pt"]
    readonly property string layout: Machine.get("keyboard.layout", "us")
    property string search: ""
    readonly property var matches: {
        const wanted = page.search.trim().toLowerCase().replace(/ /g, "_");
        if (wanted.length < 2)
            return [];
        return Machine.timeZones.filter(zone => zone.toLowerCase().indexOf(wanted) >= 0).slice(0, 8);
    }

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    // The locale follows the language while it is one of the two defaults.
    function language(value: string): void {
        Machine.set("language", value);
        const locale = Machine.get("locale", "");
        if (locale === "" || locale === "es_ES.UTF-8" || locale === "en_US.UTF-8")
            Machine.set("locale", value === "es" ? "es_ES.UTF-8" : "en_US.UTF-8");
    }

    ColumnLayout {
        id: column
        width: page.width
        spacing: 14

        Heading {
            title: Lang.cfgRegion
            sub: Lang.cfgRegionSub
        }

        Setting {
            title: Lang.cfgLanguage
            sub: Lang.cfgLanguageSub

            Choice {
                options: [{ value: "es", label: "Español" }, { value: "en", label: "English" }]
                value: Machine.get("language", "en")
                onPicked: value => page.language(value)
            }
        }

        Setting {
            title: Lang.cfgKeyboard
            sub: Lang.cfgKeyboardSub

            Column {
                spacing: 8

                Choice {
                    width: 330
                    options: page.layouts.map(name => ({ value: name, label: name }))
                    value: page.layout
                    onPicked: value => Machine.set("keyboard.layout", value)
                }

                Row {
                    spacing: 8

                    Field {
                        width: 150
                        placeholder: Lang.cfgOther
                        value: page.layouts.indexOf(page.layout) < 0 ? page.layout : ""
                        invalid: text !== "" && !/^[a-z]{2,8}$/.test(text)
                        onEdited: text => {
                            if (/^[a-z]{2,8}$/.test(text))
                                Machine.set("keyboard.layout", text);
                        }
                    }

                    Field {
                        width: 172
                        placeholder: Lang.cfgVariant
                        value: Machine.get("keyboard.variant", "")
                        onEdited: text => Machine.set("keyboard.variant", text.trim())
                    }
                }
            }
        }

        Setting {
            title: Lang.cfgTimeZone
            sub: Machine.get("timeZone", "UTC")

            Field {
                id: zoneField
                width: 280
                placeholder: Lang.cfgTimeZoneSub
                onEdited: text => page.search = text
                onAccepted: {
                    if (page.matches.length > 0) {
                        Machine.set("timeZone", page.matches[0]);
                        page.search = "";
                        zoneField.clear();
                    }
                }
            }
        }

        Repeater {
            model: page.matches

            Rectangle {
                required property string modelData

                Layout.fillWidth: true
                implicitHeight: 32
                radius: 16
                color: zoneArea.containsMouse ? Tokens.raised : "transparent"

                Txt {
                    anchors.verticalCenter: parent.verticalCenter
                    x: 16
                    text: modelData.replace(/_/g, " ")
                    font.family: Tokens.fontMono
                    font.pixelSize: 13
                    color: zoneArea.containsMouse ? Tokens.ink : Tokens.dim
                }

                MouseArea {
                    id: zoneArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Machine.set("timeZone", modelData);
                        page.search = "";
                        zoneField.clear();
                    }
                }
            }
        }
    }
}
