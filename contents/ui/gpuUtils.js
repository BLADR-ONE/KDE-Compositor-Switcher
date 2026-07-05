.pragma library

function vendorLabel(vendorId) {
    var id = String(vendorId || "").toLowerCase()
    if (id === "0x8086") {
        return "Intel"
    }
    if (id === "0x1002") {
        return "AMD"
    }
    if (id === "0x10de") {
        return "NVIDIA"
    }
    return id ? ("Vendor " + id) : "Unknown"
}

function vendorIcon(vendorId) {
    var id = String(vendorId || "").toLowerCase()
    if (id === "0x8086") {
        return "computer-laptop"
    }
    if (id === "0x1002") {
        return "video-display"
    }
    if (id === "0x10de") {
        return "video-card"
    }
    return "video-display"
}

function fallbackName(vendorId, deviceId) {
    return vendorLabel(vendorId) + " GPU (0x" + String(deviceId || "").replace(/^0x/i, "") + ")"
}

// nvidia-smi prints "00000000:2F:00.0" (8-digit domain, uppercase hex);
// kernel PCI_SLOT_NAME is "0000:2f:00.0" (4-digit domain, lowercase hex).
function normalizeNvidiaBusId(busId) {
    var id = String(busId || "").trim().toLowerCase()
    if (/^[0-9a-f]{8}:/.test(id)) {
        return id.slice(4)
    }
    return id
}

function formatGiB(bytes) {
    var value = Number(bytes)
    if (!isFinite(value) || value < 0) {
        return "—"
    }
    return (value / (1024 * 1024 * 1024)).toFixed(1) + " GiB"
}

function parseDeviceOverrides(text) {
    var overrides = {}
    var lines = String(text || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (!line) {
            continue
        }
        var eq = line.indexOf("=")
        if (eq === -1) {
            continue
        }
        var slot = line.slice(0, eq).trim()
        var path = line.slice(eq + 1).trim()
        if (!slot || !path || path.indexOf(":") !== -1) {
            continue
        }
        overrides[slot] = path
    }
    return overrides
}

function overridePathForSlot(overrides, slot) {
    if (!overrides || !slot) {
        return ""
    }
    return overrides[slot] || ""
}

function tokenForGpu(gpu, farmDir, overrides) {
    if (!gpu || !gpu.slot) {
        return ""
    }
    var overridePath = overridePathForSlot(overrides, gpu.slot)
    if (overridePath) {
        return overridePath
    }
    return farmDir + "/" + symlinkName(gpu.slot)
}

function tokenMatchesOverride(token, overrides) {
    var path = String(token || "")
    if (!overrides) {
        return ""
    }
    for (var slot in overrides) {
        if (!Object.prototype.hasOwnProperty.call(overrides, slot)) {
            continue
        }
        if (overrides[slot] === path) {
            return slot
        }
    }
    return ""
}

function parseEnumeration(stdout) {
    var gpus = []
    var lines = String(stdout || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (!line || line.indexOf("CARD|") !== 0) {
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
        var vendor = String(record.vendor || "").toLowerCase()
        var device = String(record.device || "").toLowerCase()
        var driver = String(record.driver || "")
        var present = String(record.present || "").toLowerCase()
        var gpu = {
            slot: record.slot || "",
            vendor: vendor,
            vendorLabel: vendorLabel(vendor),
            icon: vendorIcon(vendor),
            name: fallbackName(vendor, device),
            driver: driver,
            bootVga: record.boot_vga === "1" || record.boot_vga === "true" || record.boot_vga === "yes",
            byPath: record.bypath || "",
            present: present === "1" || present === "true" ||
                     present === "yes" || present === "present",
            statsCapability: driver === "amdgpu" ? "sysfs"
                              : vendor === "0x10de" ? "nvidia"
                              : "none"
        }
        gpus.push(gpu)
    }
    return gpus
}

function parseLspci(stdout) {
    var names = {}
    var lines = String(stdout || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (!line || line.indexOf("LSPCI|") !== 0) {
            continue
        }
        line = line.slice(6)
        var slot = line.split(/\s+/)[0]
        if (!slot) {
            continue
        }
        var quoted = line.match(/"([^"]*)"/g)
        if (!quoted || quoted.length < 3) {
            continue
        }
        var name = quoted[2].slice(1, -1).replace(/\s*\[[0-9a-fA-F]{4}\]\s*$/, "")
        if (name) {
            names[slot] = name
            if (/^[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$/.test(slot)) {
                names["0000:" + slot] = name
            }
        }
    }
    return names
}

function shellQuote(s) {
    return "'" + String(s).replace(/'/g, "'\"'\"'") + "'"
}

// Quote a filesystem path for POSIX sh while keeping a leading literal
// "$HOME" expandable (commands run through /bin/sh). Everything after the
// "$HOME" prefix still goes through shellQuote.
function shellPath(p) {
    var s = String(p)
    if (s.indexOf("$HOME") === 0) {
        return "\"$HOME\"" + shellQuote(s.slice(5))
    }
    return shellQuote(s)
}

function basename(p) {
    var s = String(p)
    var idx = s.lastIndexOf("/")
    return idx === -1 ? s : s.slice(idx + 1)
}

// PCI slot "0000:31:00.0" -> colon-free "gpu-0000_31_00_0" (KWIN_DRM_DEVICES is
// colon-separated, so farm symlink names must never contain a colon).
function symlinkName(slot) {
    return "gpu-" + String(slot).replace(/[:.]/g, "_")
}

// Inverse of symlinkName for the fixed PCI slot format DDDD:BB:DD.F:
// last "_" -> ".", earlier "_" -> ":".
function slotFromSymlinkName(name) {
    var rest = String(name).replace(/^gpu-/, "")
    var lastUnderscore = rest.lastIndexOf("_")
    if (lastUnderscore === -1) {
        return rest
    }
    return rest.slice(0, lastUnderscore).replace(/_/g, ":") + "." + rest.slice(lastUnderscore + 1)
}

// Ordered device tokens for KWIN_DRM_DEVICES: chosen GPU first (render
// device), then all other PRESENT GPUs by ascending slot. Override paths are
// used directly; non-overridden GPUs use the colon-free farm symlink.
function composeKwinDevices(gpus, chosenSlot, farmDir, overrides) {
    var present = []
    for (var i = 0; i < gpus.length; ++i) {
        if (gpus[i] && gpus[i].present) {
            present.push(gpus[i])
        }
    }
    present.sort(function (a, b) {
        return a.slot < b.slot ? -1 : (a.slot > b.slot ? 1 : 0)
    })
    var paths = []
    for (var c = 0; c < present.length; ++c) {
        if (present[c].slot === chosenSlot) {
            paths.push(tokenForGpu(present[c], farmDir, overrides))
            break
        }
    }
    // Safety invariant: never compose a list that does not start with the
    // user-confirmed GPU (also rules out an empty KWIN_DRM_DEVICES value).
    if (paths.length === 0) {
        throw new Error("composeKwinDevices: chosen slot not among present GPUs: " + chosenSlot)
    }
    for (var j = 0; j < present.length; ++j) {
        if (present[j].slot === chosenSlot) {
            continue
        }
        paths.push(tokenForGpu(present[j], farmDir, overrides))
    }
    // Safety invariant: farm paths must be colon-free (colons would break the
    // colon-separated KWIN_DRM_DEVICES list and risk a login boot-loop).
    for (var k = 0; k < paths.length; ++k) {
        if (paths[k].indexOf(":") !== -1) {
            throw new Error("composeKwinDevices: colon in farm path (safety invariant): " + paths[k])
        }
    }
    return paths
}

// One POSIX-sh command: create farm + environment.d dirs, refresh the
// colon-free symlinks for every PRESENT GPU without an override, overwrite the
// conf with the KWIN_DRM_DEVICES line, then cat it back. Output is syntax-only
// (sh -n) safe.
function buildApplyCommand(gpus, chosenSlot, farmDir, confPath, deviceOverridesText) {
    var confDir = String(confPath).replace(/\/[^\/]*$/, "")
    var overrides = parseDeviceOverrides(deviceOverridesText)
    var parts = []
    parts.push("mkdir -p " + shellPath(farmDir) + " " + shellPath(confDir))
    for (var i = 0; i < gpus.length; ++i) {
        var g = gpus[i]
        if (!g || !g.present || overridePathForSlot(overrides, g.slot)) {
            continue
        }
        var link = farmDir + "/" + symlinkName(g.slot)
        parts.push("ln -sfn " + shellPath(g.byPath) + " " + shellPath(link))
    }
    var farmPaths = composeKwinDevices(gpus, chosenSlot, farmDir, overrides)
    var quoted = []
    for (var j = 0; j < farmPaths.length; ++j) {
        quoted.push(shellPath(farmPaths[j]))
    }
    parts.push("printf 'KWIN_DRM_DEVICES=%s\\n' " + quoted.join(":") + " > " + shellPath(confPath))
    parts.push("cat " + shellPath(confPath))
    return parts.join(" && ")
}

// Auto (system default): remove the conf, echo a fixed "no conf" token.
function buildAutoCommand(confPath) {
    return "rm -f " + shellPath(confPath) + " && echo GPUMODE_AUTO"
}

// Interpret conf content. Empty / no KWIN_DRM_DEVICES -> auto. Otherwise decode
// the first token: a configured override path -> {mode:"gpu", slot}; a farm
// symlink basename -> {mode:"gpu", slot}; any other path (e.g. a legacy udev
// name) -> {mode:"external", path} for async readlink resolve.
function parseCurrentMode(confContent, gpus, deviceOverridesText) {
    var content = String(confContent || "")
    var match = content.match(/^[ \t]*KWIN_DRM_DEVICES=(.*)$/m)
    if (!match) {
        return { mode: "auto" }
    }
    var value = match[1].trim()
    // systemd environment.d strips surrounding quotes; tolerate a hand-quoted value.
    var unquoted = value.match(/^"(.*)"$/) || value.match(/^'(.*)'$/)
    if (unquoted) {
        value = unquoted[1].trim()
    }
    if (!value) {
        return { mode: "auto" }
    }
    var first = value.split(":")[0]
    var overrides = parseDeviceOverrides(deviceOverridesText)
    var overrideSlot = tokenMatchesOverride(first, overrides)
    if (overrideSlot) {
        return { mode: "gpu", slot: overrideSlot }
    }
    var base = basename(first)
    if (/^gpu-/.test(base)) {
        return { mode: "gpu", slot: slotFromSymlinkName(base) }
    }
    return { mode: "external", path: first }
}

function parseNumberOrNull(value) {
    var text = String(value || "").trim()
    if (!text || text === "NA") {
        return null
    }
    var num = Number(text)
    return isFinite(num) ? num : null
}

function mergeStatsRecord(statsBySlot, slot, fields) {
    if (!slot) {
        return
    }
    if (!statsBySlot[slot]) {
        statsBySlot[slot] = {
            utilization: null,
            vramUsedBytes: null,
            vramTotalBytes: null,
            tempC: null
        }
    }
    var current = statsBySlot[slot]
    for (var key in fields) {
        var value = fields[key]
        if (value !== null && typeof value !== "undefined") {
            current[key] = value
        }
    }
}

function parseStats(stdout) {
    var statsBySlot = {}
    var lines = String(stdout || "").split(/\r?\n/)
    for (var i = 0; i < lines.length; ++i) {
        var line = lines[i].trim()
        if (!line) {
            continue
        }
        if (line.indexOf("GPU|") === 0) {
            var gpuParts = line.slice(4).split("|")
            var gpuFields = {}
            var slot = ""
            for (var j = 0; j < gpuParts.length; ++j) {
                var gpuPart = gpuParts[j]
                var gpuEq = gpuPart.indexOf("=")
                if (gpuEq === -1) {
                    continue
                }
                var gpuKey = gpuPart.slice(0, gpuEq)
                var gpuValue = gpuPart.slice(gpuEq + 1)
                if (gpuKey === "slot") {
                    slot = gpuValue
                } else if (gpuKey === "busy") {
                    gpuFields.utilization = parseNumberOrNull(gpuValue)
                } else if (gpuKey === "vu") {
                    gpuFields.vramUsedBytes = parseNumberOrNull(gpuValue)
                } else if (gpuKey === "vt") {
                    gpuFields.vramTotalBytes = parseNumberOrNull(gpuValue)
                } else if (gpuKey === "temp") {
                    var temp = parseNumberOrNull(gpuValue)
                    gpuFields.tempC = temp === null ? null : temp / 1000
                }
            }
            mergeStatsRecord(statsBySlot, slot, gpuFields)
            continue
        }
        if (line.indexOf("NV|") === 0) {
            var nvParts = line.slice(3).split(",")
            if (nvParts.length < 5) {
                continue
            }
            var nvSlot = normalizeNvidiaBusId(nvParts.shift())
            var nvUtil = parseNumberOrNull(nvParts.shift())
            var nvUsed = parseNumberOrNull(nvParts.shift())
            var nvTotal = parseNumberOrNull(nvParts.shift())
            var nvTemp = parseNumberOrNull(nvParts.shift())
            mergeStatsRecord(statsBySlot, nvSlot, {
                utilization: nvUtil,
                vramUsedBytes: nvUsed === null ? null : nvUsed * 1024 * 1024,
                vramTotalBytes: nvTotal === null ? null : nvTotal * 1024 * 1024,
                tempC: nvTemp
            })
        }
    }
    return statsBySlot
}

function buildStatsCommand(gpus) {
    var hasNvidia = false
    for (var i = 0; i < gpus.length; ++i) {
        if (gpus[i] && gpus[i].vendor === "0x10de") {
            hasNvidia = true
            break
        }
    }

    var parts = []
    parts.push("for card in /sys/class/drm/card[0-9]*; do")
    parts.push("  [ -e \"$card/device/vendor\" ] || continue")
    parts.push("  slot=''")
    parts.push("  driver=''")
    parts.push("  while IFS='=' read -r key value; do")
    parts.push("    case \"$key\" in")
    parts.push("      PCI_SLOT_NAME) slot=$value ;;")
    parts.push("      DRIVER) driver=$value ;;")
    parts.push("    esac")
    parts.push("  done < \"$card/device/uevent\"")
    parts.push("  [ -n \"$slot\" ] || continue")
    parts.push("  busy=NA")
    parts.push("  vu=NA")
    parts.push("  vt=NA")
    parts.push("  temp=NA")
    parts.push("  if [ \"$driver\" = amdgpu ]; then")
    parts.push("    if [ -r \"$card/device/gpu_busy_percent\" ]; then")
    parts.push("      busy=$(cat \"$card/device/gpu_busy_percent\" 2>/dev/null)")
    parts.push("      [ -n \"$busy\" ] || busy=NA")
    parts.push("    fi")
    parts.push("    if [ -r \"$card/device/mem_info_vram_used\" ]; then")
    parts.push("      vu=$(cat \"$card/device/mem_info_vram_used\" 2>/dev/null)")
    parts.push("      [ -n \"$vu\" ] || vu=NA")
    parts.push("    fi")
    parts.push("    if [ -r \"$card/device/mem_info_vram_total\" ]; then")
    parts.push("      vt=$(cat \"$card/device/mem_info_vram_total\" 2>/dev/null)")
    parts.push("      [ -n \"$vt\" ] || vt=NA")
    parts.push("    fi")
    parts.push("    for hwmon in \"$card\"/device/hwmon/hwmon*; do")
    parts.push("      [ -r \"$hwmon/temp1_input\" ] || continue")
    parts.push("      temp=$(cat \"$hwmon/temp1_input\" 2>/dev/null)")
    parts.push("      [ -n \"$temp\" ] || temp=NA")
    parts.push("      break")
    parts.push("    done")
    parts.push("  fi")
    parts.push("  printf 'GPU|slot=%s|busy=%s|vu=%s|vt=%s|temp=%s\\n' \"$slot\" \"$busy\" \"$vu\" \"$vt\" \"$temp\"")
    parts.push("done")
    if (hasNvidia) {
        parts.push("command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu --format=csv,noheader,nounits 2>/dev/null | sed 's/^/NV|/'")
    }
    return parts.join("\n")
}
