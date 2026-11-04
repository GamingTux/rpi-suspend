# 🌙 rpi-suspend — Universal Userspace Suspend, Standby & Clamshell Manager for Raspberry Pi

[![Build and Release](https://github.com/GamingTux/rpi-suspend/actions/workflows/ci.yml/badge.svg)](https://github.com/GamingTux/rpi-suspend/actions/workflows/ci.yml)
[![License: GPL v2](https://img.shields.io/badge/License-GPL_v2-blue.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html)
[![Platform](https://img.shields.io/badge/Platform-Raspberry_Pi_5_%7C_Pi_4_%7C_CM5_%7C_CM4-c51a4a)](https://www.raspberrypi.com/)
[![Debian Package](https://img.shields.io/badge/Package-.deb_(arm64%2Fall)-A81D33)](https://github.com/GamingTux/rpi-suspend/releases)

**`rpi-suspend`** (formerly `rpi-fake-sleep`) brings **native-feeling `systemctl suspend` (`s2idle`), desktop sleep integration, and smart multi-monitor Clamshell Mode** to the Raspberry Pi 5, Pi 4, Pi 500, and CM4/CM5 laptops & handhelds.

---

## 💡 Why Does This Exist?

The Broadcom BCM2712 (Raspberry Pi 5) and BCM2711 (Raspberry Pi 4) SoCs do **not** implement an ACPI/PSCI deep-sleep state (`S3 Suspend-to-RAM`) in firmware. Because the kernel reports no sleep states in `/sys/power/state`, `systemd-logind` completely hides the **Sleep / Suspend** button in KDE Plasma, GNOME, XFCE, and Wayfire, and ignores laptop lid events (`HandleLidSwitch=suspend`) as well as desktop idle-sleep timers.

When you manually run `echo freeze > /sys/power/state`, the Raspberry Pi kernel freezes tasks, **but leaves HDMI/DSI displays powered on, keeps all 4 Cortex-A76 cores online, leaves audio amplifiers active, and runs PWM fans at full speed.**

**`rpi-suspend` solves this cleanly in userspace** by overriding `systemd-suspend.service` and orchestrating a deterministic **10-stage hardware power-down** with **`<1 ms` instant wakeup** via lid switch, keyboard, or mouse—cutting total system power consumption by **~58.5%**.

---

## ⚡ Empirical Power Benchmarks

Measured on a Raspberry Pi 5 (8 GB) laptop (Argon ONE UP, NVMe SSD, Wi-Fi connected, 1920×1200 IPS panel) via hardware smart battery telemetry (`bq40z50` SMBus fuel gauge):

| Power State | System Draw (Watts) | Current (mA @ 16.0V) | Power Saved | Approx. Battery Runtime (56 Wh) |
| :--- | :---: | :---: | :---: | :---: |
| **Desktop Idle (Screen 100%, CPU `ondemand`)** | `7.21 W` | `451 mA` | — | ~7.7 hours |
| **Desktop Idle (Screen Blanked only)** | `5.10 W` | `319 mA` | `-29.3%` | ~11.0 hours |
| **🌙 `rpi-suspend` Active (`s2idle`)** | **`2.88 W`** | **`180 mA`** | **`-58.5%`** | **~19.5 hours** |

> [!NOTE]
> Even on a **desktop Raspberry Pi 5** connected to a wall adapter, `rpi-suspend` puts your HDMI monitors into hardware DPMS standby, pauses active YouTube/Spotify media streams, mutes audio, freezes background browser/application load to `0%`, parks Cores 1–3, and throttles the cooling fan down to silent standby while waking up in `<1 ms` on the first keystroke or mouse click.

---

## ✨ Key Features

### 1. 10-Stage Deep Standby Engine (`systemctl suspend`)
1. **Desktop Screen Lock (`loginctl lock-sessions`)**: Pre-locks your Wayland/X11 session *before* blanking displays so no unlocked desktop frame flashes on wake.
2. **MPRIS2 Media Pause**: Automatically pauses active media players (Firefox, Chromium, VLC, Spotify, MPV) across active user D-Bus sessions.
3. **ALSA & PipeWire Audio Mute**: Mutes hardware audio mixers to eliminate speaker pop and amplifier idle draw.
4. **Universal Display & Backlight Power-Off**:
   - Turns off `/sys/class/backlight/*` and `/sys/class/leds/*kbd*backlight*`.
   - Blanks framebuffers (`/sys/class/graphics/fb*/blank`).
   - Sends Wayland `wlr-output-power-management` (`wlr-randr --off`), KDE `kscreen-doctor --dpms off`, or X11 `xset dpms force off`.
   - Forces kernel DRM connectors (`card*-HDMI-A-*`, `card*-eDP-*`, `card*-DSI-*`) off at the KMS driver level.
5. **Userspace Process Freeze (`cgroups v2`)**: Freezes `user.slice` via `/sys/fs/cgroup/user.slice/cgroup.freeze` (`0%` CPU wakeups from browsers, Electron apps, or background indexers).
6. **Single-Core CPU0 WFI Parking (`cpuset` + IRQ Affinity)**:
   - Clamps CPU0 to its lowest frequency (`scaling_max_freq = scaling_min_freq` + `powersave` governor).
   - Evacuates all movable kernel threads, unbound workqueues (`cpumask = 1`), and hardware interrupts (`smp_affinity = 1`) onto CPU0.
   - Offlines **CPU1, CPU2, and CPU3** completely (`echo 0 > /sys/devices/system/cpu/cpu[1-3]/online`).
7. **Wi-Fi DTIM Power-Save**: Enables `iw dev wlan0 set power_save on` so your Pi stays reachable via SSH / network while sleeping, or optionally powers down Wi-Fi/Bluetooth radios completely (`SUSPEND_NETWORK=full`).
8. **USB Autosuspend & Device Power Cut**: Enables runtime PM (`power/control = auto`) across USB buses and supports profile-specific USB hub port power-cuts.
9. **Silent Fan Mode + Thermal Safety Watchdog**: Stops or slows PWM cooling fans during standby, while a lightweight 5-second watchdog monitors `/sys/class/thermal/thermal_zone0/temp` and automatically engages emergency cooling if the SoC exceeds `MAX_SLEEP_TEMP_MC` (default `65°C`).
10. **Instant `<1 ms` `epoll` Wakeup**: Listens directly to `/dev/input/event*` via zero-CPU Linux `epoll` and wakes the system immediately on:
    - Laptop Lid Open (`SW_LID = 0`)
    - Power Button (`KEY_POWER`, `KEY_WAKEUP`, `KEY_SLEEP`)
    - Any Keyboard Key (`EV_KEY`)
    - Mouse Click (`BTN_LEFT`, `BTN_RIGHT`, `BTN_MIDDLE`) or optionally Mouse Movement (`WAKE_ON_MOUSE_MOVE=1`).

---

### 2. 🖥️ Smart Clamshell Mode (`rpi-suspend-lid.service`)
Have a Raspberry Pi laptop connected to an external monitor?
- Even on unpatched Raspberry Pi kernels where the internal laptop panel is wired to `HDMI-A-2` or `DSI-1` (causing `systemd-logind` to miscount external monitors), `rpi-suspend lid-daemon` compares connected DRM outputs against the `INTERNAL_DISPLAY` list in your hardware profile.
- **Lid Closed + No External Monitor:** Triggers full system suspend (`systemctl suspend`).
- **Lid Closed + External Monitor Connected (Clamshell Mode):**
  - Keeps the system, network, audio, and external monitor **100% awake**.
  - Blanks **only** the internal laptop screen (`INTERNAL_DISPLAY`) and backlight.
  - Disables the internal laptop keyboard/touchpad behind the closed lid (`CUSTOM_POWER_CUT_PATHS`) so accidental lid pressure cannot type keys.
  - Automatically restores the internal screen and keyboard as soon as you open the lid or unplug the external monitor!

---

### 3. 🧩 Modular Hardware Profile Architecture
`rpi-suspend` ships with a **100% hardware-agnostic core** and a community-extensible profile directory (`/usr/share/rpi-suspend/profiles/*.conf`).

| Profile Name | Target Device | Key Optimizations Included |
| :--- | :--- | :--- |
| **`generic`** *(Default)* | Raspberry Pi 5, Pi 4, Pi 500, Desktop & DIY setups | Full 10-stage suspend, HDMI DPMS off, CPU0 parking, keyboard/mouse wake |
| **`argon-oneup`** *(Auto-detected)* | Argon ONE UP (Pi 5 / CM5 Laptop) | Internal `HDMI-A-2`/`eDP-1` vs external `HDMI-A-1` Clamshell Mode, AMIRA USB keyboard/backlight port power-cut (`1-1-port6/7`), C-Media audio HID unbind |
| **`uconsole`** | ClockworkPi uConsole (CM4 / CM5) | `DSI-1` internal panel handling, QMK internal keyboard backlight control |
| **`devterm`** | ClockworkPi DevTerm (CM4 / CM5) | `DSI-1` internal panel handling, thermal printer standby friendly |
| **`crowview`** | Elecrow CrowView Note (Pi 5 Laptop Bridge) | Dual-HDMI Clamshell support |
| **`pitop4`** | pi-top [4] / FHD Touch Display | Internal display + cooling bridge optimization |

---

## 📦 Installation

### Option A: Install Pre-Built Debian Package (`.deb`)
Download the latest `.deb` from the [Releases](https://github.com/GamingTux/rpi-suspend/releases) page or install directly:

```bash
wget https://github.com/GamingTux/rpi-suspend/releases/latest/download/rpi-suspend.deb
sudo apt install ./rpi-suspend.deb
```

*(Note: `rpi-suspend` automatically replaces and upgrades existing `rpi-fake-sleep` installations seamlessly.)*

### Option B: Build from Source
```bash
git clone https://github.com/GamingTux/rpi-suspend.git
cd rpi-suspend
./build_deb.sh
sudo apt install ./rpi-suspend.deb
```

---

## 🛠️ Usage & CLI Commands

Once installed, **Sleep / Suspend** works automatically through your desktop environment's start menu, power button, idle timer, or terminal:

```bash
# Enter deep standby via systemd (recommended)
systemctl suspend

# Inspect current hardware profile, displays, lid switch, and sleep capabilities
rpi-suspend status

# List all available hardware profiles
rpi-suspend profiles

# Switch hardware profile (e.g. argon-oneup, uconsole, generic)
sudo rpi-suspend set-profile argon-oneup
```

### Example `rpi-suspend status` Output
```text
=== rpi-suspend Status ===
Active Profile       : argon-oneup
Profile File         : /usr/share/rpi-suspend/profiles/argon-oneup.conf
Internal Displays    : eDP-1 HDMI-A-2
Connected Displays   : HDMI-A-2
External Displays    : (none)
Lid Switch Device    : Lid Switch (/dev/input/event0)
CPU parking (CPU0)   : True
Network Suspend Mode : powersave
Wake on Mouse Move   : False
Custom Power Cuts    : 2 path(s)
```

---

## ⚙️ Configuration & Custom Hooks

The configuration is loaded in three layers (later layers override earlier ones):
1. **Hardware Profile:** `/usr/share/rpi-suspend/profiles/<PROFILE>.conf`
2. **Main Config:** `/etc/rpi-suspend.conf`
3. **Drop-in Overrides:** `/etc/rpi-suspend.conf.d/*.conf`

### Custom Hook Scripts (`/etc/rpi-suspend/hooks.d/`)
Want to run custom commands before sleeping, after waking up, or when docking/undocking? Place any executable script in `/etc/rpi-suspend/hooks.d/`:

```bash
#!/bin/sh
# /etc/rpi-suspend/hooks.d/50-my-hook.sh
case "$1" in
    pre)
        # Runs before entering s2idle sleep
        ;;
    post)
        # Runs after waking up from s2idle sleep
        ;;
    docked)
        # Runs when lid closes with an external monitor connected
        ;;
    undocked)
        # Runs when lid opens in Clamshell Mode
        ;;
esac
```

---

## 🤝 Contributing a New Hardware Profile

Built a custom cyberdeck, handheld, or Pi laptop? Adding support for your hardware takes **zero Python code**—just create a `.conf` file in [`pkg/usr/share/rpi-suspend/profiles/`](pkg/usr/share/rpi-suspend/profiles/) and open a Pull Request!

```ini
# pkg/usr/share/rpi-suspend/profiles/my-cyberdeck.conf
INTERNAL_DISPLAY="DSI-1"
PARK_CPU_CORES=1
SUSPEND_NETWORK="powersave"
CUSTOM_POWER_CUT_PATHS="/sys/bus/usb/devices/1-1:1.0/1-1-port3/disable"
```

---

## 📜 License

Licensed under the **GNU General Public License v2.0 (GPL-2.0)**.
