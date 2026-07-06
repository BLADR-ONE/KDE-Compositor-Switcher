import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PC3
import org.kde.kirigami as Kirigami
import "gpuUtils.js" as GpuUtils

Item {
    id: root

    signal activated()

    property string slot: ""
    property string icon: "video-display"
    property string name: ""
    property bool present: true
    property string statsCapability: "none"
    property var stats: null
    property bool showSensors: true
    property bool selected: false
    property bool statsReady: root.stats !== null && typeof root.stats !== "undefined"
    property var vramUsed: root.stats && root.stats.vramUsedBytes !== null ? root.stats.vramUsedBytes : null
    property var vramTotal: root.stats && root.stats.vramTotalBytes !== null ? root.stats.vramTotalBytes : null
    property var utilization: root.stats && root.stats.utilization !== null ? root.stats.utilization : null
    property var temperature: root.stats && root.stats.tempC !== null ? root.stats.tempC : null

    implicitWidth: Kirigami.Units.gridUnit * 16
    implicitHeight: cardBody.implicitHeight + Kirigami.Units.smallSpacing * 2
    opacity: root.present ? 1 : 0.55

    function isValidNumber(value) {
        return typeof value === "number" && isFinite(value)
    }

    function canShowStats() {
        return root.statsReady && root.statsCapability !== "none"
    }

    function formatGiB(value) {
        if (!root.canShowStats() || !root.isValidNumber(value) || value < 0) {
            return "—"
        }
        return GpuUtils.formatGiB(value)
    }

    function formatPercent(value) {
        if (!root.canShowStats() || !root.isValidNumber(value)) {
            return "—"
        }
        return Math.round(value) + "%"
    }

    function formatTemperature(value) {
        if (!root.canShowStats() || !root.isValidNumber(value)) {
            return "—"
        }
        return i18n("%1 °C", Math.round(value))
    }

    function accentAlpha(alpha) {
        var accent = Kirigami.Theme.highlightColor
        return Qt.rgba(accent.r, accent.g, accent.b, alpha)
    }

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.smallSpacing * 1.5
        color: root.present ? Kirigami.Theme.alternateBackgroundColor : Kirigami.Theme.backgroundColor
        border.width: 1
        border.color: root.selected
            ? root.accentAlpha(0.7)
            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, root.present ? 0.12 : 0.08)
    }

    MouseArea {
        id: cardArea
        anchors.fill: parent
        z: 0
        hoverEnabled: true
        enabled: root.present
        acceptedButtons: Qt.LeftButton
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.activated()
    }

    ColumnLayout {
        id: cardBody
        anchors.fill: parent
        anchors.margins: Kirigami.Units.smallSpacing * 1.5
        z: 1
        spacing: Kirigami.Units.smallSpacing

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                Layout.preferredWidth: Kirigami.Units.iconSizes.large
                Layout.preferredHeight: Kirigami.Units.iconSizes.large
                Layout.alignment: Qt.AlignTop
                source: root.icon
                active: cardArea.containsMouse
                opacity: root.present ? 1 : 0.7
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing / 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.smallSpacing

                    PC3.Label {
                        Layout.fillWidth: true
                        text: root.name || i18n("Unknown GPU")
                        elide: Text.ElideRight
                        font.bold: true
                        PC3.ToolTip.text: root.name || i18n("Unknown GPU")
                        PC3.ToolTip.visible: cardArea.containsMouse && truncated
                    }

                    Rectangle {
                        visible: root.selected
                        radius: height / 2
                        color: root.accentAlpha(0.18)
                        border.width: 1
                        border.color: root.accentAlpha(0.45)
                        implicitHeight: currentLabel.implicitHeight + Kirigami.Units.smallSpacing
                        implicitWidth: currentLabel.implicitWidth + Kirigami.Units.smallSpacing * 2

                        PC3.Label {
                            id: currentLabel
                            anchors.centerIn: parent
                            text: i18n("Current")
                            color: Kirigami.Theme.highlightColor
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                    }
                }

                PC3.Label {
                    visible: !root.present
                    text: i18n("Disconnected")
                    color: Kirigami.Theme.textColor
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            visible: root.showSensors

            PC3.Label {
                text: i18n("Utilization")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.textColor
            }

            PC3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 100
                visible: root.showSensors && root.statsCapability !== "none"
                value: root.canShowStats() && root.isValidNumber(root.utilization)
                    ? Math.max(0, Math.min(100, root.utilization))
                    : 0
                enabled: root.canShowStats()
                opacity: root.canShowStats() ? 1 : 0.45
            }

            PC3.Label {
                text: root.formatPercent(root.utilization)
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2
            visible: root.showSensors

            PC3.Label {
                text: i18n("VRAM")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.textColor
            }

            PC3.ProgressBar {
                Layout.fillWidth: true
                from: 0
                to: 1
                visible: root.showSensors && root.statsCapability !== "none"
                value: root.canShowStats() && root.isValidNumber(root.vramTotal) && root.vramTotal > 0
                    ? Math.max(0, Math.min(1, root.vramUsed / root.vramTotal))
                    : 0
                enabled: root.canShowStats()
                opacity: root.canShowStats() ? 1 : 0.45
            }

            PC3.Label {
                text: root.canShowStats()
                    ? i18n("%1 used / %2 total", root.formatGiB(root.vramUsed), root.formatGiB(root.vramTotal))
                    : "—"
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Kirigami.Units.smallSpacing
            rowSpacing: Kirigami.Units.smallSpacing / 2
            visible: root.showSensors

            PC3.Label {
                text: i18n("Temperature")
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: Kirigami.Theme.textColor
            }

            PC3.Label {
                Layout.alignment: Qt.AlignRight
                text: root.formatTemperature(root.temperature)
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
