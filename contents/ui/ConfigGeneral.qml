import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    property alias cfg_pollIntervalMs: pollInterval.value
    property alias cfg_widgetModeContinuousSensors: widgetModeContinuousSensors.checked
    property alias cfg_showSensors: showSensors.checked
    property alias cfg_confirmBeforeApply: confirmBeforeApply.checked
    property alias cfg_deviceOverrides: deviceOverridesArea.text

    QQC2.SpinBox {
        id: pollInterval
        Layout.fillWidth: true
        from: 500
        to: 10000
        stepSize: 250
        editable: true

        Kirigami.FormData.label: i18n("Sensor poll interval:")
    }

    QQC2.CheckBox {
        id: showSensors
        text: i18n("Show GPU sensors")
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.smallSpacing / 2

        QQC2.CheckBox {
            id: widgetModeContinuousSensors
            text: i18n("Keep sensors active in desktop-widget mode")
            enabled: showSensors.checked
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("When this plasmoid is placed on the desktop its full view is always visible, so sensors keep polling continuously, causing extra wakeups/power draw; leave off to pause sensors on the desktop.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.neutralTextColor
            opacity: widgetModeContinuousSensors.enabled ? 0.72 : 0.45
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }

    QQC2.CheckBox {
        id: confirmBeforeApply
        text: i18n("Confirm before switching the compositing GPU")
    }

    QQC2.Label {
        Layout.fillWidth: true
        Kirigami.FormData.isSection: true
        text: i18n("Advanced")
        font.bold: true
    }

    QQC2.TextArea {
        id: deviceOverridesArea
        Layout.fillWidth: true
        Layout.preferredHeight: Kirigami.Units.gridUnit * 7
        wrapMode: TextEdit.Wrap
        font.family: "monospace"
        placeholderText: i18n("One 'pciSlot=devicePath' per line, e.g. '0000:01:00.0=/dev/dri/my-gpu-link'; paths must not contain ':' and override the auto-managed symlink for that GPU.")

        Kirigami.FormData.label: i18n("Device overrides:")
    }

    QQC2.Label {
        Layout.fillWidth: true
        text: i18n("Paths must not contain ':'; each override replaces the auto-managed symlink for that GPU.")
        wrapMode: Text.WordWrap
        color: Kirigami.Theme.neutralTextColor
        font.pointSize: Kirigami.Theme.smallFont.pointSize
    }
}
