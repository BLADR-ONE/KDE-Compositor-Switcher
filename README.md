# GPU Mode — KDE Plasma 6 Applet

A Plasma panel / system-tray / desktop widget that lets you pick which GPU
KWin uses as its **compositing device** on a multi-GPU Linux system: hybrid
iGPU+dGPU laptops, eGPU setups (Thunderbolt/OcuLink), or desktops with more
than one graphics card (Intel, AMD, NVIDIA, in any combination). It shows
live per-GPU sensors (name, VRAM, utilization, temperature) and never
changes anything without an explicit action from you.

## Why this exists

KWin (Plasma's Wayland compositor) picks one DRM device as its primary
render device, read once from the `KWIN_DRM_DEVICES` environment variable at
session start. On multi-GPU systems that choice has real consequences:

- **Compositing on a discrete/external GPU** removes a cross-GPU copy from
  every frame — useful when your displays are attached to that GPU (gaming,
  external monitors on an eGPU).
- **Compositing on the integrated GPU** frees the discrete GPU's VRAM
  entirely for compute/gaming workloads, at the cost of a small per-frame
  copy for anything that still needs to scan out through the other card.

There is no live handoff between the two — switching the compositing GPU
requires a logout/login. The widget therefore does two things: writes the
config, and offers an explicit "log out now" button. It never logs out
automatically, and (with the default setting) always asks for confirmation
before writing a new configuration.

## How it works

### 1. Detection

On load (and every time the popup expands), the widget scans
`/sys/class/drm/card*` for present GPUs, reading each device's PCI slot,
driver, vendor ID and boot-VGA flag, and cross-checking presence against
`/dev/dri/by-path/`. Vendor is identified from the PCI vendor ID
(Intel/AMD/NVIDIA); a friendly name comes from `nvidia-smi` (NVIDIA),
`lspci` (everyone else), or a generic `<Vendor> GPU (0x<id>)` fallback. No
GPU name or path is ever hardcoded — everything is discovered at runtime, so
the same package works on any machine.

### 2. The colon problem, and the symlink farm

`KWIN_DRM_DEVICES` is a **colon-separated** list. This has two consequences:

- Plain `/dev/dri/cardN` names are unstable — the numbering can shuffle
  between boots, especially with a hotpluggable GPU.
- The stable `/dev/dri/by-path/pci-0000:01:00.0-card` names **cannot be used
  directly** because they contain colons; KWin splits them into garbage
  fragments and then fails with "No suitable DRM devices" → a login
  boot-loop. (This was discovered the hard way, on real hardware.)

The fix is a **colon-free symlink farm** the plasmoid maintains itself, at
`~/.local/share/gpumode/dev/` (e.g. `gpu-0000_01_00_0 →
/dev/dri/by-path/pci-0000:01:00.0-card`), regenerated every time you apply a
mode. It lives outside the plasmoid's package directory so a
`kpackagetool6 --upgrade`/`--remove` can never leave it dangling, and it
requires no root access and no manual udev rules — zero-root, boot-stable,
colon-safe, on any machine.

### 3. Applying a mode

Selecting a GPU (or "Auto") writes one line to
`~/.config/environment.d/kwin-gpu.conf` (read by systemd's user session and
inherited by KWin):

- **A specific GPU**: `KWIN_DRM_DEVICES=<chosen>:<other present GPUs, by
  ascending PCI slot>`. The chosen GPU renders; the others stay listed so
  their attached displays keep working for scanout.
- **Auto (system default)**: the conf file is removed entirely, and KWin
  picks on its own.

Only GPUs currently present are ever written into the list, so unplugging an
eGPU (or a dock) doesn't leave a stale, unopenable device blocking KWin —
it just falls through to whatever else is present.

## Install / first run (no root required)

```fish
# install (from the directory containing this repo's contents/ + metadata.json)
kpackagetool6 --type Plasma/Applet --install .

# upgrade after an update
kpackagetool6 --type Plasma/Applet --upgrade .

# run standalone with QML errors printed to the terminal (best debug loop)
plasmawindowed org.bladr.gpumode

# uninstall
kpackagetool6 --type Plasma/Applet --remove org.bladr.gpumode
```

After installing, add the widget to a panel, the system tray (enable it via
*Configure System Tray → Entries*), or the desktop.

## Features

- **N-GPU picker** — every detected GPU gets a card (name, vendor icon,
  connected/disconnected state); click one to make it the compositing GPU.
- **Auto (system default)** — clears the override and lets KWin choose.
- **Live sensors per GPU** — VRAM used/total with a bar, utilization,
  temperature. AMD via sysfs (`gpu_busy_percent`, `mem_info_vram_*`,
  `hwmon`), NVIDIA via `nvidia-smi`, Intel is limited (no non-root sysfs
  counters, shown as "—").
- **Confirmations** — applying a mode and logging out both ask for
  confirmation by default (configurable); nothing is written or applied
  silently.
- **Config page** — poll interval, a widget-mode toggle for whether sensors
  keep polling continuously when the plasmoid sits on the desktop (it's
  always visible there, so continuous polling costs extra wakeups/power),
  a toggle to hide sensors entirely, and advanced per-GPU device-path
  overrides for distros where auto-detection needs a hint.

## Recovery

If a login ever breaks after switching modes:

1. Switch to a TTY: `Ctrl+Alt+F3`, log in there.
2. Remove the override: `rm ~/.config/environment.d/kwin-gpu.conf`.
3. Optionally also clear the symlink farm: `rm -rf ~/.local/share/gpumode/dev`.
4. Switch back (`Ctrl+Alt+F1`/`F2`, whichever runs the display manager) and
   log in normally — KWin will auto-pick with no override.

## If your distro lacks `/dev/dri/by-path`

Some distros/kernels don't ship the `by-path` udev links. If a GPU shows as
detected but its by-path device is missing, use the **device overrides**
field in the config page to point that PCI slot at a stable path of your
own (e.g. a custom udev symlink) — one `pciSlot=devicePath` per line; the
path must not contain a colon.

## License

GPL-3.0-only — see [LICENSE](LICENSE). Author: bladr.
