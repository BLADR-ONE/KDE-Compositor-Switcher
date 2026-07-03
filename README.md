# GPU Mode — KDE Plasma 6 Applet

A small Plasma panel/system-tray widget that switches which GPU KWin uses for
desktop compositing on a hybrid + eGPU laptop. Built for a setup with an Intel
iGPU and an AMD RX 7900 XT connected via M.2 OcuLink, where the external
monitor is physically plugged into the eGPU.

## Why this exists

KWin (Plasma's Wayland compositor) picks one DRM device as its primary render
device. On this machine that choice matters a lot:

- **Compositing on the eGPU (7900 XT)** removes a cross-GPU copy from every
  frame and dramatically improves gaming (measured: Elden Ring went from
  ~40 fps spiky to 60 fps 1% lows at max settings).
- **Compositing on the iGPU (Intel)** frees the eGPU's VRAM. When large local
  LLM models fill the 7900 XT's 20 GB, KWin's buffers living in that VRAM get
  evicted and the desktop stutters badly. Moving compositing to Intel makes
  desktop smoothness independent of eGPU VRAM pressure.

KWin reads its device preference from the `KWIN_DRM_DEVICES` environment
variable **once, at session start**. There is no live handoff — switching
modes requires a logout/login. The widget therefore does two things: writes
the config, and offers an explicit "log out now" button. It never logs out
automatically.

## The mechanism

### 1. Stable device names (udev)

`KWIN_DRM_DEVICES` is a **colon-separated** list. This has two consequences:

- Plain `/dev/dri/cardN` names are unstable — the numbering shuffles between
  boots, especially with a hotpluggable third GPU (NVIDIA dGPU).
- The stable `/dev/dri/by-path/pci-0000:31:00.0-card` names **cannot be used**
  because they contain colons; KWin splits them into garbage fragments and
  then fails with "No suitable DRM devices" → login boot-loop. (This was
  discovered the hard way.)

The fix is a udev rule creating colon-free, PCI-address-pinned symlinks
(`/etc/udev/rules.d/99-gpu-names.rules`):

```
SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="0000:31:00.0", SYMLINK+="dri/amd_egpu"
SUBSYSTEM=="drm", KERNEL=="card*", KERNELS=="0000:00:02.0", SYMLINK+="dri/intel_igpu"
```

Note: after creating the rule, trigger with `--action=add`
(`sudo udevadm trigger --subsystem-match=drm --action=add`) — a plain
"change" trigger does not create the symlinks. Real boots emit add events
natively, so the links regenerate automatically thereafter.

**Porting to another machine:** only the PCI addresses in this rule change.
Find them with `lspci | grep -i vga`.

### 2. The two modes

The widget writes one line to `~/.config/environment.d/kwin-gpu.conf`
(read by systemd's user session and inherited by KWin):

| Mode | File contents | Effect |
|---|---|---|
| eGPU (gaming) | `KWIN_DRM_DEVICES=/dev/dri/amd_egpu:/dev/dri/intel_igpu` | AMD renders + scans out. Intel is fallback. |
| iGPU (LLM / travel) | `KWIN_DRM_DEVICES=/dev/dri/intel_igpu:/dev/dri/amd_egpu` | Intel renders; AMD stays in the session **for scanout only**. |

Key semantics: **the first device in the list is the render device; later
devices remain usable for display scanout.** This is why iGPU mode still
lists the AMD card — the external monitor is plugged into it. An earlier
version wrote Intel *only*, which made KWin drop the AMD device entirely,
taking the eGPU-connected monitor (the only usable display, lid closed) with
it → black screen. Both current modes keep both devices listed, which also
makes both modes safe when the eGPU is disconnected: the missing device
simply fails to open and KWin falls through to Intel + laptop panel.

In iGPU mode the AMD card only holds a scanout framebuffer (tens of MB) plus
a per-frame Intel→AMD copy for the desktop — negligible for desktop use, and
it cannot be evicted into stutter by VRAM pressure the way full compositing
buffers can.

### 3. Recovery (if a bad config ever locks the session again)

`Ctrl+Alt+F3` → TTY login → `rm ~/.config/environment.d/kwin-gpu.conf` →
back to SDDM (`Ctrl+Alt+F2` or F1) → log in. KWin auto-picks with no
override.

## Package structure

```
org.bladr.gpumode/
├── metadata.json          # applet identity + tray eligibility
└── contents/
    └── ui/
        └── main.qml       # all logic and UI (single file)
```

### metadata.json

Standard Plasma 6 applet metadata (`KPackageStructure: "Plasma/Applet"`,
`X-Plasma-API-Minimum-Version: "6.0"`). One non-obvious key:

- `"X-Plasma-NotificationAreaCategory": "Hardware"` — makes the applet
  eligible for the **system tray** (Configure System Tray → Entries → set
  "GPU Mode" to Shown). Without this key it can only live in a panel.

### main.qml — structure

Root element is `PlasmoidItem` (Plasma 6 API). State is one string property:

```
mode: "egpu" | "igpu" | "auto" | "unknown"
```

- `auto` = the conf file doesn't exist (KWin auto-picks; no override)
- `unknown` = not yet read (transient, at startup)

**Shell access** is via the classic `executable` dataengine, imported through
the compatibility module `org.kde.plasma.plasma5support`
(`P5Support.DataSource`). This is the standard way for a pure-QML applet to
run commands in Plasma 6 without a C++ plugin. Pattern:

```qml
P5Support.DataSource {
    engine: "executable"
    connectedSources: []
    onNewData: function (source, data) { ...; disconnectSource(source) }
    function exec(cmd) { connectSource(cmd) }
}
```

The command string itself is the source key; `disconnectSource` after each
result makes it one-shot.

**State reading:** every mode-setting command chains `&& cat <conf>` so the
same `onNewData` handler that observes writes also re-parses the real file —
the widget never trusts its own memory of the mode. It also re-reads on
`Component.onCompleted` and every time the popup expands
(`onExpandedChanged`). This keeps it in sync with external edits (e.g. a
`gpu-mode` shell function writing the same file).

**Mode parsing:** since *both* device names appear in *both* configs, mode is
determined by **which name appears first** in the file (i.e. which is the
render device), not by presence:

```qml
var amd = out.indexOf("amd_egpu")
var intel = out.indexOf("intel_igpu")
mode = (amd !== -1 && (intel === -1 || amd < intel)) ? "egpu"
     : (intel !== -1) ? "igpu" : "auto"
```

**Logout** uses `gdbus` (ships with glib2, always present) rather than
`qdbus` (needs qt6-tools, not installed by default):

```
gdbus call --session --dest org.kde.Shutdown \
  --object-path /Shutdown --method org.kde.Shutdown.logout
```

**UI layout:**

- `compactRepresentation` (panel/tray icon): a `Kirigami.Icon` whose source
  reflects the mode, plus a small colored status dot (green = eGPU,
  yellow = iGPU, grey = auto/unknown) drawn as a `Rectangle` overlay.
  Clicking toggles `root.expanded`.
- `fullRepresentation` (popup): heading, current-mode label, two checkable
  `PC3.Button`s (checked state bound to `mode`, clicking writes the config
  immediately), a "changes apply at next login" hint, and the explicit
  "Apply now — log out" button at the bottom.

## Install / upgrade / debug

```fish
# install (from the directory containing org.bladr.gpumode/)
kpackagetool6 --type Plasma/Applet --install org.bladr.gpumode

# upgrade after editing
kpackagetool6 --type Plasma/Applet --upgrade org.bladr.gpumode
systemctl --user restart plasma-plasmashell

# run standalone with QML errors printed to the terminal (best debug loop)
plasmawindowed org.bladr.gpumode

# uninstall
kpackagetool6 --type Plasma/Applet --remove org.bladr.gpumode
```

Installed location: `~/.local/share/plasma/plasmoids/org.bladr.gpumode/` —
you can edit `main.qml` there directly and restart plasmashell to iterate.

## Ideas for future work

- Third mode: NVIDIA dGPU handling for the hybrid/travel case (currently the
  NVIDIA card is deliberately excluded from `KWIN_DRM_DEVICES` in both modes).
- Read `gpu_busy_percent` / VRAM usage from
  `/sys/class/drm/<card>/device/` and show it in the popup.
- Detect eGPU presence (does `/dev/dri/amd_egpu` exist?) and grey out the
  eGPU button when disconnected.
- Confirmation dialog on the logout button.
- Config page (`contents/config/`) to make device paths configurable instead
  of hardcoded, so the widget ports to other machines without editing QML.
