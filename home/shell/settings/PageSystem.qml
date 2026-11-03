import QtQuick
import QtQuick.Layouts
import qs.theme
import qs.config
import qs.services
import qs.components

// The computer's name, and what runs on it.
Flickable {
    id: page

    readonly property var hostName: /^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$/

    contentHeight: column.implicitHeight + 24
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column
        width: page.width
        spacing: 14

        Heading {
            title: Lang.cfgSystem
            sub: Lang.cfgSystemSub
        }

        Setting {
            title: Lang.cfgHost
            sub: Lang.cfgHostSub

            Field {
                width: 240
                value: Machine.get("host.name", "")
                invalid: !page.hostName.test(text)
                onEdited: text => {
                    if (page.hostName.test(text))
                        Machine.set("host.name", text);
                }
            }
        }

        Setting {
            title: "Nilo"
            sub: Lang.cfgNiloSub

            Toggle {
                on: Machine.get("nilo.enable", false)
                onToggled: Machine.set("nilo.enable", !on)
            }
        }

        Setting {
            visible: Machine.get("nilo.enable", false)
            title: Lang.cfgAcceleration
            sub: Lang.cfgAccelerationSub

            Choice {
                options: [{ value: "cpu", label: "cpu" }, { value: "vulkan", label: "vulkan" }, { value: "rocm", label: "rocm" }, { value: "cuda", label: "cuda" }]
                value: Machine.get("nilo.acceleration", "cpu")
                onPicked: value => Machine.set("nilo.acceleration", value)
            }
        }

        Setting {
            title: Lang.cfgFingerprint
            sub: Lang.cfgFingerprintSub

            Toggle {
                on: Machine.get("fingerprint", false)
                onToggled: Machine.set("fingerprint", !on)
            }
        }

        Setting {
            title: "SSH"
            sub: Lang.cfgSshSub

            Toggle {
                on: Machine.get("ssh", false)
                onToggled: Machine.set("ssh", !on)
            }
        }
    }
}
