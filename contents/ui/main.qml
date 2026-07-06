import QtQuick
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import "gpuUtils.js" as GpuUtils

PlasmoidItem {
    id: root

    property var gpus: []
    property var detectedGpus: []
    property var statsBySlot: ({})
    readonly property string confPath: "$HOME/.config/environment.d/kwin-gpu.conf"
    readonly property string farmDir: "$HOME/.local/share/gpumode/dev"
    property string applyErrorText: ""

    // Applied compositing GPU: "" = auto / not yet read, otherwise a PCI slot.
    property string currentSlot: ""
    property bool currentLoaded: false
    property string pendingApplySlot: ""
    property bool logoutPending: false
    property bool statsInFlight: false
    property bool refreshInFlight: false

    readonly property bool desktopMode: Plasmoid.formFactor === PlasmaCore.Types.Planar
    readonly property bool showSensors: Plasmoid.configuration.showSensors !== false
    readonly property bool confirmBeforeApply: Plasmoid.configuration.confirmBeforeApply !== false
    readonly property string ribbonTextAlignment: Plasmoid.configuration.ribbonTextAlignment || "center"
    readonly property var visibleGpus: {
        var hidden = GpuUtils.parseHiddenGpuSlots(Plasmoid.configuration.hiddenGpuSlots)
        var visible = []
        for (var i = 0; i < root.gpus.length; ++i) {
            var gpu = root.gpus[i]
            if (gpu && (!hidden[gpu.slot] || gpu.slot === root.currentSlot)) {
                visible.push(gpu)
            }
        }
        return visible
    }

    // Derived compatibility mode string for the existing UI labels + compact rep.
    readonly property string mode: {
        if (!root.currentLoaded) {
            return "unknown"
        }
        if (root.currentSlot === "") {
            return "auto"
        }
        var g = root.gpuBySlot(root.currentSlot)
        return (g && g.vendor === "0x8086") ? "igpu" : "egpu"
    }

    toolTipMainText: i18n("Desktop GPU")
    toolTipSubText: !root.currentLoaded ? i18n("Reading...")
                  : root.currentSlot === "" ? i18n("No override - KWin auto-picks")
                  : root.mode === "egpu" ? i18n("Compositing on the external GPU")
                  : i18n("Compositing on the integrated GPU")

    Exec {
        id: shell
    }

    function enumerationCommand() {
        return [
            "for card in /sys/class/drm/card[0-9]*; do",
            "  [ -e \"$card/device/vendor\" ] || continue",
            "  slot=''",
            "  driver=''",
            "  while IFS='=' read -r key value; do",
            "    case \"$key\" in",
            "      PCI_SLOT_NAME) slot=$value ;;",
            "      DRIVER) driver=$value ;;",
            "    esac",
            "  done < \"$card/device/uevent\"",
            "  [ -n \"$slot\" ] || continue",
            "  vendor=$(cat \"$card/device/vendor\" 2>/dev/null)",
            "  device=$(cat \"$card/device/device\" 2>/dev/null)",
            "  boot_vga=$(cat \"$card/device/boot_vga\" 2>/dev/null)",
            "  bypath=/dev/dri/by-path/pci-${slot}-card",
            "  if [ -e \"$bypath\" ]; then present=1; else present=0; fi",
            "  printf 'CARD|card=%s|slot=%s|driver=%s|vendor=%s|device=%s|boot_vga=%s|bypath=%s|present=%s\\n' \"$card\" \"$slot\" \"$driver\" \"$vendor\" \"$device\" \"$boot_vga\" \"$bypath\" \"$present\"",
            "done",
            "if command -v lspci >/dev/null 2>&1; then",
            "  for cls in 0300 0302 0380; do",
            "    lspci -mm -nn -d \"::$cls\" 2>/dev/null | sed 's/^/LSPCI|/'",
            "  done",
            "fi"
        ].join("\n")
    }

    function nvidiaNameCommand() {
        return "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=pci.bus_id,name --format=csv,noheader 2>/dev/null"
    }

    function gpuBySlot(slot) {
        for (var i = 0; i < root.gpus.length; ++i) {
            if (root.gpus[i].slot === slot) {
                return root.gpus[i]
            }
        }
        return null
    }

    function statsForSlot(slot) {
        if (!root.statsBySlot) {
            return null
        }
        return root.statsBySlot[slot] || null
    }

    function statsPollingEnabled() {
        return Plasmoid.configuration.showSensors !== false &&
               (root.desktopMode
                ? Plasmoid.configuration.widgetModeContinuousSensors === true
                : root.expanded)
    }

    function updateStatsPolling() {
        var enabled = root.statsPollingEnabled()
        if (!enabled) {
            root.statsBySlot = ({})
        }
        if (statsTimer.running !== enabled) {
            statsTimer.running = enabled
        }
    }

    function applyParsedMode(parsed) {
        root.currentLoaded = true
        if (parsed.mode === "gpu") {
            root.currentSlot = parsed.slot
        } else if (parsed.mode === "external") {
            root.resolveExternal(parsed.path)   // async readlink match -> slot
        } else {
            root.currentSlot = ""
        }
    }

    // Legacy conf pointing at an unknown path (e.g. the old udev name
    // /dev/dri/amd_egpu): resolve it and every GPU by-path to their real
    // /dev/dri/cardN target and match to identify the applied slot.
    function resolveExternalCommand(path) {
        var lines = []
        lines.push("printf 'EXT|%s\\n' \"$(readlink -f " +
                   GpuUtils.shellQuote(path) + " 2>/dev/null)\"")
        for (var i = 0; i < root.gpus.length; ++i) {
            var g = root.gpus[i]
            if (!g.byPath) {
                continue
            }
            lines.push("printf 'GPU|%s|%s\\n' " + GpuUtils.shellQuote(g.slot) +
                       " \"$(readlink -f " + GpuUtils.shellQuote(g.byPath) + " 2>/dev/null)\"")
        }
        return lines.join("\n")
    }

    function resolveExternal(path) {
        shell.exec(root.resolveExternalCommand(path), function (stdout) {
            root.handleExternalResolution(stdout)
        })
    }

    function handleExternalResolution(stdout) {
        var lines = String(stdout || "").split(/\r?\n/)
        var extTarget = ""
        var targets = {}
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i]
            if (line.indexOf("EXT|") === 0) {
                extTarget = line.slice(4).trim()
            } else if (line.indexOf("GPU|") === 0) {
                var rest = line.slice(4)
                var sep = rest.indexOf("|")
                if (sep !== -1) {
                    targets[rest.slice(0, sep)] = rest.slice(sep + 1).trim()
                }
            }
        }
        root.currentSlot = ""
        if (extTarget) {
            for (var slot in targets) {
                if (targets[slot] && targets[slot] === extTarget) {
                    root.currentSlot = slot
                    break
                }
            }
        }
        root.currentLoaded = true
    }

    function applyLspciNames(gpus, names) {
        for (var i = 0; i < gpus.length; ++i) {
            var gpu = gpus[i]
            if (names[gpu.slot]) {
                gpu.name = names[gpu.slot]
            }
        }
    }

    function refreshDetectedGpuCache(gpus) {
        var serialized = GpuUtils.serializeDetectedGpusCache(gpus)
        if (Plasmoid.configuration.detectedGpusCache !== serialized) {
            Plasmoid.configuration.detectedGpusCache = serialized
        }
    }

    function isValidManualSlot(slot) {
        return /^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(String(slot || ""))
    }

    function manualGpuPresenceCommand() {
        var manualGpus = GpuUtils.parseManualGpus(Plasmoid.configuration.manualGpus)
        var seen = {}
        var parts = []
        for (var i = 0; i < manualGpus.length; ++i) {
            var manual = manualGpus[i]
            var slot = String(manual.slot || "").trim()
            var byPath = String(manual.byPath || "").trim()
            if (!slot || !byPath || !root.isValidManualSlot(slot) || seen[slot]) {
                continue
            }
            seen[slot] = true
            parts.push("if [ -e " + GpuUtils.shellQuote(byPath) + " ]; then printf 'MANUAL|slot=%s|present=1\\n' " + GpuUtils.shellQuote(slot) +
                       "; else printf 'MANUAL|slot=%s|present=0\\n' " + GpuUtils.shellQuote(slot) + "; fi")
        }
        return parts.join("\n")
    }

    function parseManualGpuPresence(stdout) {
        var present = {}
        var lines = String(stdout || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim()
            if (!line || line.indexOf("MANUAL|") !== 0) {
                continue
            }
            var parts = line.split("|")
            var record = {}
            for (var j = 1; j < parts.length; ++j) {
                var part = parts[j]
                var eq = part.indexOf("=")
                if (eq === -1) {
                    continue
                }
                record[part.slice(0, eq)] = part.slice(eq + 1)
            }
            var slot = record.slot || ""
            if (!slot) {
                continue
            }
            var flag = String(record.present || "").toLowerCase()
            present[slot] = flag === "1" || flag === "true" || flag === "yes" || flag === "present"
        }
        return present
    }

    function probeManualGpuPresence(done) {
        var command = root.manualGpuPresenceCommand()
        if (!command) {
            done({})
            return
        }
        shell.exec(command, function (stdout) {
            done(root.parseManualGpuPresence(stdout))
        })
    }

    function mergeManualGpus(gpus, manualPresence) {
        var merged = gpus.slice(0)
        var seen = {}
        for (var i = 0; i < merged.length; ++i) {
            if (merged[i] && merged[i].slot) {
                seen[merged[i].slot] = true
            }
        }

        var manualGpus = GpuUtils.parseManualGpus(Plasmoid.configuration.manualGpus)
        for (var j = 0; j < manualGpus.length; ++j) {
            var manual = manualGpus[j]
            var slot = String(manual.slot || "").trim()
            var name = String(manual.name || "").trim()
            var byPath = String(manual.byPath || "").trim()
            if (!slot || !name || !byPath || !root.isValidManualSlot(slot) || seen[slot]) {
                continue
            }
            seen[slot] = true
            merged.push({
                slot: slot,
                name: name,
                vendor: "",
                vendorLabel: "Manual",
                icon: "video-display",
                driver: "",
                bootVga: false,
                byPath: byPath,
                present: manualPresence && manualPresence[slot] === true,
                statsCapability: "none"
            })
        }
        return merged
    }

    function updateGpuModel(gpus, done) {
        root.detectedGpus = gpus.slice(0)
        root.refreshDetectedGpuCache(gpus)
        root.probeManualGpuPresence(function (manualPresence) {
            root.gpus = root.mergeManualGpus(gpus, manualPresence)
            if (done) {
                done()
            }
        })
    }

    function applyNvidiaNames(gpus, stdout) {
        var lines = String(stdout || "").split(/\r?\n/)
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim()
            if (!line) {
                continue
            }
            var parts = line.split(",")
            if (parts.length < 2) {
                continue
            }
            var slot = GpuUtils.normalizeNvidiaBusId(parts.shift())
            var name = parts.join(",").trim()
            for (var j = 0; j < gpus.length; ++j) {
                if (gpus[j].slot === slot && name) {
                    gpus[j].name = name
                }
            }
        }
    }

    function handleEnumeration(stdout, done) {
        var gpus = GpuUtils.parseEnumeration(stdout)
        var lspciNames = GpuUtils.parseLspci(stdout)
        applyLspciNames(gpus, lspciNames)

        var hasNvidia = false
        for (var i = 0; i < gpus.length; ++i) {
            if (gpus[i].vendor === "0x10de") {
                hasNvidia = true
                break
            }
        }

        // nvidia-smi resumes a runtime-suspended dGPU just to read a name.
        // Only pay that wakeup when sensors are actually being shown (same
        // gate as stats polling); otherwise keep the lspci/fallback name so a
        // disabled-sensor config never touches the GPU.
        if (hasNvidia && root.statsPollingEnabled()) {
            shell.exec(nvidiaNameCommand(), function (nvidiaStdout) {
                applyNvidiaNames(gpus, nvidiaStdout)
                root.updateGpuModel(gpus, done)
            })
        } else {
            root.updateGpuModel(gpus, done)
        }
    }

    function refreshGpuModel(done) {
        shell.exec(enumerationCommand(), function (stdout) {
            handleEnumeration(stdout, done)
        })
    }

    function readCurrentMode() {
        shell.exec("cat " + GpuUtils.shellPath(root.confPath) + " 2>/dev/null", function (stdout) {
            root.applyParsedMode(GpuUtils.parseCurrentMode(stdout, root.gpus, Plasmoid.configuration.deviceOverrides))
        })
    }

    function refresh() {
        // Read the conf only after the GPU model is populated so an external
        // (legacy) conf can be resolved against the enumerated by-paths.
        // refreshInFlight keeps rapid popup expansions from stacking
        // enumerations (the executable engine always fires the callback).
        if (root.refreshInFlight) {
            return
        }
        root.refreshInFlight = true
        refreshGpuModel(function () {
            root.refreshInFlight = false
            root.readCurrentMode()
            root.updateStatsPolling()
        })
    }

    function refreshStats() {
        if (root.statsInFlight || !root.statsPollingEnabled()) {
            return
        }
        root.statsInFlight = true
        shell.exec(GpuUtils.buildStatsCommand(root.gpus), function (stdout) {
            try {
                if (root.statsPollingEnabled()) {
                    root.statsBySlot = GpuUtils.parseStats(stdout)
                }
            } finally {
                root.statsInFlight = false
            }
        })
    }

    function applyGpu(slot) {
        if (!slot) {
            return
        }
        var gpu = root.gpuBySlot(slot)
        if (!gpu || !gpu.present) {
            root.applyErrorText = i18n("That GPU is no longer available.")
            return
        }
        root.applyErrorText = ""
        shell.exec(GpuUtils.buildApplyCommand(root.gpus, slot, root.farmDir, root.confPath, Plasmoid.configuration.deviceOverrides),
                   function (stdout, stderr, exitCode) {
            if (Number(exitCode) !== 0) {
                root.applyErrorText = i18n("Failed to update the GPU setting (exit code %1).", exitCode)
                return
            }
            root.applyParsedMode(GpuUtils.parseCurrentMode(stdout, root.gpus, Plasmoid.configuration.deviceOverrides))
        })
    }

    function applyAuto() {
        root.applyErrorText = ""
        shell.exec(GpuUtils.buildAutoCommand(root.confPath), function (stdout, stderr, exitCode) {
            if (Number(exitCode) !== 0) {
                root.applyErrorText = i18n("Failed to restore automatic GPU selection (exit code %1).", exitCode)
                return
            }
            root.currentSlot = ""
            root.currentLoaded = true
        })
    }

    function logout() {
        shell.exec("gdbus call --session --dest org.kde.Shutdown " +
                   "--object-path /Shutdown --method org.kde.Shutdown.logout", function () {})
    }

    Component.onCompleted: refresh()

    Connections {
        target: Plasmoid.configuration

        function onDeviceOverridesChanged() {
            if (root.currentLoaded) {
                root.readCurrentMode()
            }
        }

        function onShowSensorsChanged() {
            root.updateStatsPolling()
        }

        function onConfirmBeforeApplyChanged() {
            if (!Plasmoid.configuration.confirmBeforeApply) {
                root.pendingApplySlot = ""
            }
        }

        function onManualGpusChanged() {
            if (root.currentLoaded || root.expanded) {
                root.updateGpuModel(root.detectedGpus, function () {
                    if (root.currentLoaded) {
                        root.readCurrentMode()
                    }
                })
            }
        }

        function onWidgetModeContinuousSensorsChanged() {
            root.updateStatsPolling()
        }
    }

    Timer {
        id: statsTimer
        interval: Plasmoid.configuration.pollIntervalMs
        repeat: true
        triggeredOnStart: true
        running: false
        onTriggered: root.refreshStats()
    }

    function handleExpandedChanged() {
        if (!root.expanded) {
            root.logoutPending = false
            root.pendingApplySlot = ""
            root.updateStatsPolling()
            return
        }
        refresh()
    }
    onExpandedChanged: root.handleExpandedChanged()

    compactRepresentation: CompactRepresentation {
        mode: root.mode
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullRepresentation {
        plasmoidRoot: root
    }
}
