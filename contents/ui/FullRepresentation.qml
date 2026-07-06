import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PC3
import org.kde.plasma.extras as PlasmaExtras

PlasmaExtras.Representation {
    id: root

    property var plasmoidRoot: null

    collapseMarginsHint: true
    implicitWidth: Kirigami.Units.gridUnit * 18
    implicitHeight: Kirigami.Units.gridUnit * 13

    function gpuAt(slot) {
        if (!root.plasmoidRoot || !root.plasmoidRoot.gpuBySlot) {
            return null
        }
        return root.plasmoidRoot.gpuBySlot(slot)
    }

    function gpuName(slot) {
        var gpu = root.gpuAt(slot)
        return gpu && gpu.name ? gpu.name : i18n("Unknown GPU")
    }

    function currentSummary() {
        if (!root.plasmoidRoot) {
            return i18n("Reading current mode...")
        }
        if (!root.plasmoidRoot.currentLoaded) {
            return i18n("Reading current mode...")
        }
        if (root.plasmoidRoot.currentSlot === "") {
            return i18n("Current: Auto (system default)")
        }
        return i18n("Current: %1", root.gpuName(root.plasmoidRoot.currentSlot))
    }

    function accentAlpha(alpha) {
        var accent = Kirigami.Theme.highlightColor
        return Qt.rgba(accent.r, accent.g, accent.b, alpha)
    }

    function ribbonAlignment() {
        if (!root.plasmoidRoot || root.plasmoidRoot.ribbonTextAlignment === "center") {
            return Text.AlignHCenter
        }
        if (root.plasmoidRoot.ribbonTextAlignment === "left") {
            return Text.AlignLeft
        }
        if (root.plasmoidRoot.ribbonTextAlignment === "right") {
            return Text.AlignRight
        }
        return Text.AlignHCenter
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Kirigami.Units.smallSpacing

        Item {
            Layout.fillWidth: true
            implicitHeight: currentColumn.implicitHeight + Kirigami.Units.smallSpacing * 3

            Rectangle {
                id: currentBar
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing * 1.5
                color: root.accentAlpha(0.12)
                border.width: 1
                border.color: root.accentAlpha(0.4)
            }

            ColumnLayout {
                id: currentColumn
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 1.5
                spacing: Kirigami.Units.smallSpacing / 2

                Kirigami.Heading {
                    Layout.fillWidth: true
                    level: 3
                    text: i18n("Desktop compositing GPU")
                    horizontalAlignment: root.ribbonAlignment()
                    wrapMode: Text.WordWrap
                }

                PC3.Label {
                    Layout.fillWidth: true
                    text: root.currentSummary()
                    horizontalAlignment: root.ribbonAlignment()
                    wrapMode: Text.WordWrap
                }
            }
        }

        PC3.ScrollView {
            id: scrollView
            Layout.fillWidth: true
            Layout.fillHeight: true

            contentItem: Flickable {
                width: scrollView.width
                contentWidth: width
                contentHeight: contentColumn.implicitHeight
                clip: true

                ColumnLayout {
                    id: contentColumn
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    Item {
                        Layout.fillWidth: true
                        visible: root.plasmoidRoot && root.plasmoidRoot.visibleGpus.length === 0
                        implicitHeight: emptyState.implicitHeight

                        PlasmaExtras.PlaceholderMessage {
                            id: emptyState
                            anchors.centerIn: parent
                            width: parent.width - Kirigami.Units.gridUnit * 2
                            iconName: "video-display"
                            text: root.plasmoidRoot && root.plasmoidRoot.gpus.length > 0
                                ? i18n("All GPUs are hidden in the dashboard")
                                : i18n("GPU detection failed or no GPUs were found")
                        }
                    }

                    Item {
                        Layout.fillWidth: true
                        implicitHeight: gpuSection.implicitHeight

                        ColumnLayout {
                            id: gpuSection
                            width: parent.width
                            spacing: Kirigami.Units.smallSpacing

                            Item {
                                Layout.fillWidth: true
                                implicitHeight: autoBody.implicitHeight + Kirigami.Units.smallSpacing * 3

                                Rectangle {
                                    id: autoCard
                                    anchors.fill: parent
                                    radius: Kirigami.Units.smallSpacing * 1.5
                                    color: root.plasmoidRoot && root.plasmoidRoot.currentSlot === ""
                                        ? Kirigami.Theme.alternateBackgroundColor
                                        : Kirigami.Theme.backgroundColor
                                    border.width: 1
                                    border.color: root.plasmoidRoot && root.plasmoidRoot.currentSlot === ""
                                        ? root.accentAlpha(0.7)
                                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
                                }

                                MouseArea {
                                    id: autoArea
                                    anchors.fill: parent
                                    z: 1
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.plasmoidRoot) {
                                            root.plasmoidRoot.pendingApplySlot = ""
                                            root.plasmoidRoot.applyErrorText = ""
                                            root.plasmoidRoot.applyAuto()
                                        }
                                    }
                                }

                                ColumnLayout {
                                    id: autoBody
                                    anchors.fill: parent
                                    anchors.margins: Kirigami.Units.smallSpacing * 1.5
                                    spacing: Kirigami.Units.smallSpacing

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Kirigami.Units.smallSpacing

                                        Kirigami.Icon {
                                            id: autoIcon
                                            Layout.preferredWidth: Kirigami.Units.iconSizes.large
                                            Layout.preferredHeight: Kirigami.Units.iconSizes.large
                                            source: "view-refresh"
                                            active: autoArea.containsMouse
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: Kirigami.Units.smallSpacing / 2

                                            PC3.Label {
                                                Layout.fillWidth: true
                                                text: i18n("Auto (system default)")
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            PC3.Label {
                                                Layout.fillWidth: true
                                                text: i18n("Follow KWin's default device order.")
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                                color: Kirigami.Theme.textColor
                                                wrapMode: Text.WordWrap
                                            }
                                        }

                                        Rectangle {
                                            visible: root.plasmoidRoot && root.plasmoidRoot.currentSlot === ""
                                            radius: height / 2
                                            color: root.accentAlpha(0.18)
                                            border.width: 1
                                            border.color: root.accentAlpha(0.45)
                                            implicitHeight: currentAutoLabel.implicitHeight + Kirigami.Units.smallSpacing
                                            implicitWidth: currentAutoLabel.implicitWidth + Kirigami.Units.smallSpacing * 2

                                            PC3.Label {
                                                id: currentAutoLabel
                                                anchors.centerIn: parent
                                                text: i18n("Current")
                                                color: Kirigami.Theme.highlightColor
                                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            }
                                        }
                                    }

                                }
                            }

                            Repeater {
                                visible: root.plasmoidRoot && root.plasmoidRoot.visibleGpus.length > 0
                                model: root.plasmoidRoot ? root.plasmoidRoot.visibleGpus : []

                                delegate: GpuCard {
                                    Layout.fillWidth: true
                                    slot: modelData.slot
                                    icon: modelData.icon
                                    name: modelData.name
                                    present: modelData.present
                                    statsCapability: modelData.statsCapability
                                    stats: root.plasmoidRoot ? root.plasmoidRoot.statsForSlot(modelData.slot) : null
                                    showSensors: root.plasmoidRoot ? root.plasmoidRoot.showSensors : true
                                    selected: root.plasmoidRoot ? root.plasmoidRoot.currentSlot === modelData.slot : false
                                    onActivated: {
                                        if (root.plasmoidRoot) {
                                            if (root.plasmoidRoot.confirmBeforeApply) {
                                                root.plasmoidRoot.pendingApplySlot = modelData.slot
                                                root.plasmoidRoot.applyErrorText = ""
                                            } else {
                                                root.plasmoidRoot.pendingApplySlot = ""
                                                root.plasmoidRoot.applyErrorText = ""
                                                root.plasmoidRoot.applyGpu(modelData.slot)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: bottomRibbon.implicitHeight + Kirigami.Units.smallSpacing * 3

            Rectangle {
                id: bottomRibbon
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing * 1.5
                color: root.accentAlpha(0.08)
                border.width: 1
                border.color: root.accentAlpha(0.25)
            }

            PC3.Label {
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 1.5
                text: i18n("Changes apply at next login.")
                horizontalAlignment: root.ribbonAlignment()
                verticalAlignment: Text.AlignVCenter
                wrapMode: Text.WordWrap
                color: Kirigami.Theme.textColor
                opacity: 0.8
                font.pointSize: Kirigami.Theme.smallFont.pointSize
            }
        }

        Item {
            Layout.fillWidth: true
            visible: root.plasmoidRoot && (root.plasmoidRoot.pendingApplySlot !== "" || root.plasmoidRoot.applyErrorText !== "")
            implicitHeight: applyRow.implicitHeight + Kirigami.Units.smallSpacing * 3

            Rectangle {
                id: applyBar
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing * 1.5
                color: Kirigami.Theme.alternateBackgroundColor
                border.width: 1
                border.color: root.accentAlpha(0.4)
            }

            RowLayout {
                id: applyRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                PC3.Label {
                    Layout.fillWidth: true
                    text: root.plasmoidRoot && root.plasmoidRoot.applyErrorText
                        ? root.plasmoidRoot.applyErrorText
                        : root.plasmoidRoot
                            ? i18n("Set %1 as compositing GPU at next login?", root.gpuName(root.plasmoidRoot.pendingApplySlot))
                            : ""
                    color: root.plasmoidRoot && root.plasmoidRoot.applyErrorText ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                    wrapMode: Text.WordWrap
                }

                PC3.Button {
                    visible: root.plasmoidRoot && root.plasmoidRoot.applyErrorText === ""
                    text: i18n("Confirm")
                    onClicked: {
                        if (root.plasmoidRoot) {
                            root.plasmoidRoot.applyErrorText = ""
                            root.plasmoidRoot.applyGpu(root.plasmoidRoot.pendingApplySlot)
                            root.plasmoidRoot.pendingApplySlot = ""
                        }
                    }
                }

                PC3.Button {
                    visible: root.plasmoidRoot && root.plasmoidRoot.applyErrorText === ""
                    text: i18n("Cancel")
                    onClicked: {
                        if (root.plasmoidRoot) {
                            root.plasmoidRoot.pendingApplySlot = ""
                            root.plasmoidRoot.applyErrorText = ""
                        }
                    }
                }

                PC3.Button {
                    visible: root.plasmoidRoot && root.plasmoidRoot.applyErrorText !== ""
                    text: i18n("Dismiss")
                    onClicked: {
                        if (root.plasmoidRoot) {
                            root.plasmoidRoot.applyErrorText = ""
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: logoutRow.implicitHeight + Kirigami.Units.smallSpacing * 3

            Rectangle {
                anchors.fill: parent
                radius: Kirigami.Units.smallSpacing * 1.5
                color: Kirigami.Theme.alternateBackgroundColor
                border.width: 1
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)
            }

            RowLayout {
                id: logoutRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.smallSpacing * 1.5
                spacing: Kirigami.Units.smallSpacing

                PC3.Button {
                    Layout.fillWidth: true
                    icon.name: root.plasmoidRoot && root.plasmoidRoot.logoutPending ? "dialog-ok" : "system-log-out"
                    text: root.plasmoidRoot && root.plasmoidRoot.logoutPending
                        ? i18n("Confirm log out")
                        : i18n("Apply now - log out")
                    onClicked: {
                        if (!root.plasmoidRoot) {
                            return
                        }
                        if (root.plasmoidRoot.logoutPending) {
                            root.plasmoidRoot.logout()
                        } else {
                            root.plasmoidRoot.logoutPending = true
                        }
                    }
                }

                PC3.Button {
                    visible: root.plasmoidRoot && root.plasmoidRoot.logoutPending
                    text: i18n("Cancel")
                    onClicked: {
                        if (root.plasmoidRoot) {
                            root.plasmoidRoot.logoutPending = false
                        }
                    }
                }
            }
        }
    }
}
