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
        }

        Setting {
            title: Lang.cfgHost

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

            Toggle {
                on: Machine.get("nilo.enable", false)
                onToggled: Machine.set("nilo.enable", !on)
            }
        }

        Setting {
            visible: Machine.get("nilo.enable", false)
            title: Lang.cfgAcceleration

            Choice {
                options: [{ value: "cpu", label: "CPU" }, { value: "vulkan", label: "Vulkan" }, { value: "rocm", label: "ROCm" }, { value: "cuda", label: "CUDA" }]
                value: Machine.get("nilo.acceleration", "cpu")
                onPicked: value => Machine.set("nilo.acceleration", value)
            }
        }

        // How many copies the clipboard history keeps (home/clipboard.nix);
        // forgetting them is at once.
        Setting {
            title: Lang.cfgClipboard

            Row {
                spacing: 12

                Choice {
                    anchors.verticalCenter: parent.verticalCenter
                    options: [{ value: 0, label: Lang.cfgClipboardOff }, { value: 5, label: "5" }, { value: 8, label: "8" },
                              { value: 15, label: "15" }, { value: 30, label: "30" }]
                    value: Machine.get("clipboard", 8)
                    onPicked: value => Machine.set("clipboard", value)
                }

                KeyButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: Clipboard.enabled
                    text: Lang.cfgClipboardWipe
                    onClicked: Clipboard.wipe()
                }
            }
        }

        Setting {
            title: Lang.cfgBootSound

            Toggle {
                on: Machine.get("bootSound", true)
                onToggled: Machine.set("bootSound", !on)
            }
        }

        Setting {
            title: Lang.cfgFingerprint

            Toggle {
                on: Machine.get("fingerprint", false)
                onToggled: Machine.set("fingerprint", !on)
            }
        }

        Setting {
            title: "SSH"

            Toggle {
                on: Machine.get("ssh", false)
                onToggled: Machine.set("ssh", !on)
            }
        }
    }
}
