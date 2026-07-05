import QtQuick
import org.kde.plasma.plasma5support as P5Support

P5Support.DataSource {
    id: root
    engine: "executable"
    connectedSources: []

    property var callbacks: ({})
    property int seq: 0

    function exec(cmd, callback) {
        var tagged = cmd + "\n: #gm" + seq++
        callbacks[tagged] = callback
        connectSource(tagged)
    }

    onNewData: function (source, data) {
        var callback = callbacks[source]
        // Clean up before invoking the callback so a throwing callback can
        // never leak a map entry or leave the source connected.
        delete callbacks[source]
        disconnectSource(source)
        if (callback) {
            var exitCode = typeof data["exit code"] !== "undefined" ? data["exit code"]
                         : data["exitCode"]
            callback(data["stdout"] || "", data["stderr"] || "", exitCode)
        }
    }
}
