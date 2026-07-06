import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kcmutils as KCM
import org.kde.kirigami as Kirigami
import "gpuUtils.js" as GpuUtils

KCM.SimpleKCM {
    id: root

    // Same symmetric inset as ConfigGeneral: SimpleKCM's built-in 6px margin
    // (and the ~8px largeSpacing tried before) read as "no margin", so use a
    // full gridUnit horizontally. The manual-GPU editor and override area then
    // keep a visible gap from the window edge in both config hosts.
    topPadding: Kirigami.Units.largeSpacing
    bottomPadding: Kirigami.Units.largeSpacing
    leftPadding: Kirigami.Units.gridUnit
    rightPadding: Kirigami.Units.gridUnit

    property string cfg_manualGpus: ""
    property string cfg_detectedGpusCache: ""
    property string cfg_hiddenGpuSlots: ""
    property alias cfg_deviceOverrides: deviceOverridesArea.text

    property bool loadingManualModel: false
    property bool loadingDetectedModel: false
    property bool manualSyncInProgress: false
    property bool hiddenSyncInProgress: false

    ListModel {
        id: manualModel
    }

    ListModel {
        id: detectedModel
    }

    function loadManualGpus() {
        if (root.loadingManualModel) {
            return
        }
        root.loadingManualModel = true
        manualModel.clear()
        var entries = GpuUtils.parseManualGpus(root.cfg_manualGpus)
        for (var i = 0; i < entries.length; ++i) {
            manualModel.append({
                name: entries[i].name,
                slot: entries[i].slot,
                byPath: entries[i].byPath
            })
        }
        root.loadingManualModel = false
    }

    function syncManualGpus() {
        if (root.loadingManualModel) {
            return
        }
        root.manualSyncInProgress = true
        var entries = []
        for (var i = 0; i < manualModel.count; ++i) {
            var row = manualModel.get(i)
            entries.push({
                name: row.name,
                slot: row.slot,
                byPath: row.byPath
            })
        }
        root.cfg_manualGpus = GpuUtils.serializeManualGpus(entries)
        root.manualSyncInProgress = false
    }

    function loadDetectedGpus() {
        if (root.loadingDetectedModel) {
            return
        }
        root.loadingDetectedModel = true
        detectedModel.clear()
        var entries = GpuUtils.parseDetectedGpusCache(root.cfg_detectedGpusCache)
        var hidden = GpuUtils.parseHiddenGpuSlots(root.cfg_hiddenGpuSlots)
        for (var i = 0; i < entries.length; ++i) {
            detectedModel.append({
                slot: entries[i].slot,
                name: entries[i].name,
                shown: !hidden[entries[i].slot]
            })
        }
        root.loadingDetectedModel = false
    }

    function applyHiddenSelectionToDetectedModel() {
        if (root.loadingDetectedModel) {
            return
        }
        var hidden = GpuUtils.parseHiddenGpuSlots(root.cfg_hiddenGpuSlots)
        for (var i = 0; i < detectedModel.count; ++i) {
            var row = detectedModel.get(i)
            detectedModel.setProperty(i, "shown", !hidden[row.slot])
        }
    }

    function syncHiddenGpuSlots() {
        if (root.loadingDetectedModel) {
            return
        }
        root.hiddenSyncInProgress = true
        var hidden = []
        for (var i = 0; i < detectedModel.count; ++i) {
            var row = detectedModel.get(i)
            if (!row.shown && row.slot) {
                hidden.push(row.slot)
            }
        }
        root.cfg_hiddenGpuSlots = GpuUtils.serializeHiddenGpuSlots(hidden)
        root.hiddenSyncInProgress = false
    }

    function isValidManualSlot(slot) {
        return /^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(String(slot || ""))
    }

    Component.onCompleted: {
        loadManualGpus()
        loadDetectedGpus()
    }

    onCfg_manualGpusChanged: {
        if (!root.manualSyncInProgress) {
            loadManualGpus()
        }
    }

    onCfg_detectedGpusCacheChanged: loadDetectedGpus()

    onCfg_hiddenGpuSlotsChanged: {
        if (!root.hiddenSyncInProgress) {
            applyHiddenSelectionToDetectedModel()
        }
    }

    // Plain ColumnLayout content (not FormLayout): the manual-GPU table, the
    // dashboard checklist and the overrides area are full-width blocks, not
    // label:field pairs. As the single visual child the ScrollablePage binds
    // its width, so every fillWidth control shrinks with the window instead of
    // pinning a wide minimum from long placeholder text (the old cause of
    // horizontal overflow that clipped the right edge and blocked resizing).
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            text: i18n("Manual GPUs")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Name")
                wrapMode: Text.WordWrap
                font.bold: true
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("PCI slot")
                wrapMode: Text.WordWrap
                font.bold: true
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: i18n("Device path")
                wrapMode: Text.WordWrap
                font.bold: true
            }

            QQC2.Label {
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                text: ""
            }
        }

        Repeater {
            model: manualModel

            delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing

                QQC2.TextField {
                    id: nameField
                    Layout.fillWidth: true
                    text: name
                    placeholderText: i18n("Name")
                    property bool invalid: String(text || "").trim().length === 0
                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing
                        border.width: 1
                        border.color: nameField.invalid
                            ? Kirigami.Theme.negativeTextColor
                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                        color: Kirigami.Theme.backgroundColor
                    }
                    QQC2.ToolTip.text: i18n("Name is required.")
                    QQC2.ToolTip.visible: nameField.invalid && (hovered || activeFocus)
                    onTextEdited: {
                        manualModel.setProperty(index, "name", text)
                        root.syncManualGpus()
                    }
                }

                QQC2.TextField {
                    id: slotField
                    Layout.fillWidth: true
                    text: slot
                    placeholderText: i18n("0000:01:00.0")
                    property bool invalid: !root.isValidManualSlot(text)
                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing
                        border.width: 1
                        border.color: slotField.invalid
                            ? Kirigami.Theme.negativeTextColor
                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                        color: Kirigami.Theme.backgroundColor
                    }
                    QQC2.ToolTip.text: i18n("Use a PCI slot like 0000:01:00.0.")
                    QQC2.ToolTip.visible: slotField.invalid && (hovered || activeFocus)
                    onTextEdited: {
                        manualModel.setProperty(index, "slot", text)
                        root.syncManualGpus()
                    }
                }

                QQC2.TextField {
                    id: pathField
                    Layout.fillWidth: true
                    text: byPath
                    placeholderText: i18n("/dev/dri/by-path/... or a stable path")
                    property bool invalid: String(text || "").trim().length === 0
                    background: Rectangle {
                        radius: Kirigami.Units.smallSpacing
                        border.width: 1
                        border.color: pathField.invalid
                            ? Kirigami.Theme.negativeTextColor
                            : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.18)
                        color: Kirigami.Theme.backgroundColor
                    }
                    QQC2.ToolTip.text: i18n("Device path is required.")
                    QQC2.ToolTip.visible: pathField.invalid && (hovered || activeFocus)
                    onTextEdited: {
                        manualModel.setProperty(index, "byPath", text)
                        root.syncManualGpus()
                    }
                }

                QQC2.Button {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 6
                    text: i18n("Remove")
                    onClicked: {
                        manualModel.remove(index)
                        root.syncManualGpus()
                    }
                }
            }
        }

        QQC2.Button {
            Layout.alignment: Qt.AlignLeft
            text: i18n("Add")
            onClicked: {
                manualModel.append({ name: "", slot: "", byPath: "" })
                root.syncManualGpus()
            }
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            text: i18n("Dashboard")
        }

        Repeater {
            model: detectedModel

            delegate: QQC2.CheckBox {
                Layout.fillWidth: true
                text: name ? i18n("%1 (%2)", name, slot) : slot
                checked: shown
                onToggled: {
                    detectedModel.setProperty(index, "shown", checked)
                    root.syncHiddenGpuSlots()
                }
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Unchecked GPUs are hidden from the popup dashboard.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.textColor
            opacity: 0.72
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }

        Kirigami.Heading {
            Layout.fillWidth: true
            level: 2
            text: i18n("Advanced")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Device overrides")
            wrapMode: Text.WordWrap
            font.bold: true
        }

        QQC2.TextArea {
            id: deviceOverridesArea
            Layout.fillWidth: true
            Layout.preferredHeight: Kirigami.Units.gridUnit * 7
            wrapMode: TextEdit.Wrap
            font.family: "monospace"
            placeholderText: i18n("One 'pciSlot=devicePath' per line, e.g. '0000:01:00.0=/dev/dri/my-gpu-link'; paths must not contain ':' and override the auto-managed symlink for that GPU.")
        }

        QQC2.Label {
            Layout.fillWidth: true
            text: i18n("Paths must not contain ':'; each override replaces the auto-managed symlink for that GPU.")
            wrapMode: Text.WordWrap
            color: Kirigami.Theme.textColor
            opacity: 0.72
            font.pointSize: Kirigami.Theme.smallFont.pointSize
        }
    }
}
