import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // "egpu" | "igpu" | "auto" (no conf file) | "unknown" (not read yet)
    property string mode: "unknown"
    property string confPath: "$HOME/.config/environment.d/kwin-gpu.conf"

    toolTipMainText: "Desktop GPU"
    toolTipSubText: mode === "egpu" ? "Compositing on 7900 XT (gaming)"
                  : mode === "igpu" ? "Compositing on Intel (LLM / travel)"
                  : mode === "auto" ? "No override — KWin auto-picks"
                  : "Reading…"

    P5Support.DataSource {
        id: shell
        engine: "executable"
        connectedSources: []
        onNewData: function (source, data) {
            // Only parse commands that end by cat-ing the conf file
            if (source.indexOf("kwin-gpu.conf") !== -1 && source.indexOf("cat ") !== -1) {
                var out = data["stdout"] || ""
                if (out.indexOf("amd_egpu") !== -1) {
                    root.mode = "egpu"
                } else if (out.indexOf("intel_igpu") !== -1) {
                    root.mode = "igpu"
                } else {
                    root.mode = "auto"
                }
            }
            disconnectSource(source)
        }
        function exec(cmd) { connectSource(cmd) }
    }

    function refresh() {
        shell.exec("cat " + confPath + " 2>/dev/null")
    }

    function setEgpu() {
        shell.exec("mkdir -p $HOME/.config/environment.d && " +
                   "printf 'KWIN_DRM_DEVICES=/dev/dri/amd_egpu:/dev/dri/intel_igpu\\n' > " + confPath +
                   " && cat " + confPath)
    }

    function setIgpu() {
        shell.exec("mkdir -p $HOME/.config/environment.d && " +
                   "printf 'KWIN_DRM_DEVICES=/dev/dri/intel_igpu\\n' > " + confPath +
                   " && cat " + confPath)
    }

    function logout() {
        shell.exec("gdbus call --session --dest org.kde.Shutdown " +
                   "--object-path /Shutdown --method org.kde.Shutdown.logout")
    }

    Component.onCompleted: refresh()
    onExpandedChanged: if (expanded) refresh()

    compactRepresentation: MouseArea {
        onClicked: root.expanded = !root.expanded

        Kirigami.Icon {
            anchors.fill: parent
            source: root.mode === "egpu" ? "video-display"
                  : root.mode === "igpu" ? "computer-laptop"
                  : "video-display-symbolic"
            active: parent.containsMouse
        }

        // Small colored dot indicating mode at a glance
        Rectangle {
            width: Math.max(6, parent.width / 5)
            height: width
            radius: width / 2
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            color: root.mode === "egpu" ? Kirigami.Theme.positiveTextColor
                 : root.mode === "igpu" ? Kirigami.Theme.neutralTextColor
                 : Kirigami.Theme.disabledTextColor
            border.width: 1
            border.color: Kirigami.Theme.backgroundColor
        }
    }

    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 16
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        spacing: Kirigami.Units.smallSpacing

        Kirigami.Heading {
            level: 3
            text: "Desktop compositing GPU"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        PC3.Label {
            text: root.mode === "egpu" ? "Current: 7900 XT — gaming mode"
                : root.mode === "igpu" ? "Current: Intel iGPU — LLM / travel mode"
                : root.mode === "auto" ? "Current: no override (KWin auto-picks)"
                : "Reading current mode…"
            opacity: 0.7
            Layout.alignment: Qt.AlignHCenter
            wrapMode: Text.WordWrap
        }

        Item { Layout.preferredHeight: Kirigami.Units.smallSpacing }

        PC3.Button {
            Layout.fillWidth: true
            icon.name: "video-display"
            text: "eGPU mode  (7900 XT)"
            checkable: true
            checked: root.mode === "egpu"
            onClicked: root.setEgpu()
            PC3.ToolTip.text: "Desktop composited on the 7900 XT. Best gaming performance."
            PC3.ToolTip.visible: hovered
            PC3.ToolTip.delay: 600
        }

        PC3.Button {
            Layout.fillWidth: true
            icon.name: "computer-laptop"
            text: "iGPU mode  (Intel — free VRAM)"
            checkable: true
            checked: root.mode === "igpu"
            onClicked: root.setIgpu()
            PC3.ToolTip.text: "Desktop composited on Intel. Full 20GB VRAM free for LLMs; also safe without the eGPU."
            PC3.ToolTip.visible: hovered
            PC3.ToolTip.delay: 600
        }

        PC3.Label {
            text: "Changes apply at next login."
            opacity: 0.6
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.fillHeight: true }

        PC3.Button {
            Layout.fillWidth: true
            icon.name: "system-log-out"
            text: "Apply now — log out"
            onClicked: root.logout()
        }
    }
}
