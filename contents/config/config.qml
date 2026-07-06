import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }

    ConfigCategory {
        name: i18n("GPUs")
        icon: "video-card"
        source: "ConfigGpus.qml"
    }
}
