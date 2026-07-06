import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami

KCM.SimpleKCM {
    id: root

    // SimpleKCM is a Kirigami.ScrollablePage whose built-in "margins" is a hard
    // 6px (Breeze child margin); largeSpacing (~8px) is barely bigger and still
    // reads as "no margin". Use a full gridUnit horizontally for a clearly
    // visible, SYMMETRIC inset in both config hosts (desktop shell and
    // plasmoidviewershell), with largeSpacing vertically for KDE rhythm. The
    // ScrollablePage flickable applies these paddings, so content can never
    // collide with the window edge.
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.largeSpacing
    leftPadding: Kirigami.Units.gridUnit
    rightPadding: Kirigami.Units.gridUnit

    property int cfg_pollIntervalMs: 2000
    property alias cfg_widgetModeContinuousSensors: widgetModeContinuousSensors.checked
    property alias cfg_showSensors: showSensors.checked
    property alias cfg_confirmBeforeApply: confirmBeforeApply.checked
    property string cfg_ribbonTextAlignment: "center"

    function syncRibbonAlignment() {
        leftRibbonButton.checked = root.cfg_ribbonTextAlignment === "left"
        centerRibbonButton.checked = root.cfg_ribbonTextAlignment === "center" || root.cfg_ribbonTextAlignment === ""
        rightRibbonButton.checked = root.cfg_ribbonTextAlignment === "right"
    }

    Component.onCompleted: syncRibbonAlignment()
    onCfg_ribbonTextAlignmentChanged: syncRibbonAlignment()

    // A FormLayout is the idiomatic content for label:field config. It is the
    // single visual child, so the ScrollablePage binds its width and drives the
    // (single) vertical scrollbar from implicitHeight: the page reflows and
    // resizes smoothly with no hardcoded width.
    Kirigami.FormLayout {
        QQC2.Label {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            text: i18n("Sensors")
        }

        QQC2.ComboBox {
            id: pollInterval
            Layout.fillWidth: false
            Layout.preferredWidth: Kirigami.Units.gridUnit * 7
            editable: true
            // Presets are milliseconds to match how pollIntervalMs is stored;
            // the editable field also accepts any custom value in range.
            model: ["500", "1000", "2000", "5000", "10000"]
            validator: IntValidator { bottom: 500; top: 60000 }

            Kirigami.FormData.label: i18n("Sensor poll interval (ms)")

            function commitInterval() {
                var parsed = parseInt(pollInterval.editText, 10)
                if (isNaN(parsed)) {
                    parsed = root.cfg_pollIntervalMs
                }
                parsed = Math.max(500, Math.min(60000, parsed))
                root.cfg_pollIntervalMs = parsed
                pollInterval.editText = String(parsed)
            }

            Component.onCompleted: pollInterval.editText = String(root.cfg_pollIntervalMs)
            onActivated: pollInterval.commitInterval()
            onAccepted: pollInterval.commitInterval()
            onActiveFocusChanged: {
                if (!activeFocus && !pollInterval.popup.visible) {
                    pollInterval.commitInterval()
                }
            }

            Connections {
                target: root
                function onCfg_pollIntervalMsChanged() {
                    if (!pollInterval.activeFocus) {
                        pollInterval.editText = String(root.cfg_pollIntervalMs)
                    }
                }
            }
        }

        QQC2.CheckBox {
            id: showSensors
            Layout.fillWidth: true
            text: i18n("Show GPU sensors")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.CheckBox {
                id: widgetModeContinuousSensors
                Layout.fillWidth: true
                text: i18n("Keep sensors active in desktop-widget mode")
                enabled: showSensors.checked
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("When this plasmoid is placed on the desktop its full view is always visible, so sensors keep polling continuously, causing extra wakeups and power draw.")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: widgetModeContinuousSensors.enabled ? 0.72 : 0.45
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            text: i18n("Behavior")
        }

        QQC2.CheckBox {
            id: confirmBeforeApply
            Layout.fillWidth: true
            text: i18n("Confirm before switching the compositing GPU")
        }

        QQC2.Label {
            Kirigami.FormData.isSection: true
            Layout.fillWidth: true
            text: i18n("Appearance")
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing / 2

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Ribbon text alignment")
                wrapMode: Text.WordWrap
                font.bold: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.Button {
                    id: leftRibbonButton
                    Layout.fillWidth: true
                    text: i18n("Left")
                    checkable: true
                    autoExclusive: true
                    checked: root.cfg_ribbonTextAlignment === "left"
                    onClicked: root.cfg_ribbonTextAlignment = "left"
                }

                QQC2.Button {
                    id: centerRibbonButton
                    Layout.fillWidth: true
                    text: i18n("Center")
                    checkable: true
                    autoExclusive: true
                    checked: root.cfg_ribbonTextAlignment === "center" || root.cfg_ribbonTextAlignment === ""
                    onClicked: root.cfg_ribbonTextAlignment = "center"
                }

                QQC2.Button {
                    id: rightRibbonButton
                    Layout.fillWidth: true
                    text: i18n("Right")
                    checkable: true
                    autoExclusive: true
                    checked: root.cfg_ribbonTextAlignment === "right"
                    onClicked: root.cfg_ribbonTextAlignment = "right"
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Controls the default alignment for the top and bottom ribbons.")
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: 0.72
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }
    }
}
