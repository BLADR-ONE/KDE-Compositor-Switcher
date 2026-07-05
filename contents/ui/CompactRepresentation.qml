import QtQuick
import org.kde.kirigami as Kirigami

MouseArea {
    id: root
    property string mode: "unknown"

    Kirigami.Icon {
        anchors.fill: parent
        source: root.mode === "egpu" ? "video-display"
              : root.mode === "igpu" ? "computer-laptop"
              : "video-display-symbolic"
        active: root.containsMouse
    }

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
