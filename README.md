
<p align="center">
  <img src="https://raw.githubusercontent.com/mrk9091/SmartBypass/main/f01ee74aadf0ed828fef38bd3b46ac02.jpg" 
       alt="SmartBypass" 
       style="border-radius: 16px; max-width: 100%;" />
</p>
# SmartBypass v1.0

**Advanced bypass charging for all Android devices.**  
A Magisk module that keeps your battery at a safe level while plugged in — protecting longevity, reducing heat, and putting you in control.

---

## What It Does

When you leave your phone plugged in, the charger holds the battery at 100% continuously. This produces heat and accelerates chemical wear — the two biggest killers of lithium batteries over time.

SmartBypass solves this by intercepting the charge at a configurable target (default 80%) and holding it there. While plugged in, your phone runs directly off the charger with the battery sitting comfortably below full. When gaming, it activates automatically. When the device gets hot, it lowers the target on its own.

---

## Requirements

- Android 8.0+
- Magisk v20.4+ (or KernelSU / APatch with service.sh support)
- Root access

---

## Installation

1. Download `SmartBypass-v1.0.zip`
2. Open **Magisk** → Modules → Install from storage
3. Select the zip and flash
4. Reboot

The engine starts automatically on boot. No app required.

---

## How It Works

### Hardware Detection

On first boot, SmartBypass scans your device's kernel nodes and selects the best available method — in order of preference:

| Method | Devices |
|---|---|
| **ASUS_ROG** | ASUS ROG Phone (hardware bypass rail) |
| **ASUS_DUAL** | ASUS ZenFone (dual charge threshold) |
| **LENOVO_LEGION** | Lenovo Legion Phone |
| **REDMAGIC** | Nubia RedMagic |
| **SAMSUNG** | Samsung (slate / store mode) |
| **ONEPLUS_OPPO** | OnePlus, OPPO, Realme |
| **XIAOMI** | Xiaomi, POCO (input suspend) |
| **INPUT_SUSPEND** | Generic input suspend (many vendors) |
| **CHARGE_ENABLE** | Generic charge enable toggle |
| **CHARGE_LIMIT** | Generic charge threshold node |
| **EMULATED** | Any device — software charge cycling |

If your device has no native kernel support, the emulated engine takes over. It watches the battery level and toggles charging on/off within a tight band, mimicking hardware bypass in software. A minimum toggle interval (default 30 s) prevents rapid switching that could stress the charging IC.

### Smart Thermal Control

SmartBypass tracks temperature using a weighted moving average across all available thermal zones, prioritising skin/SOC sensors. If the device is heating up quickly, the bypass target is automatically lowered:

- Rising faster than ~3 °C/cycle → target drops 5% (floor: 70%)
- Rising faster than ~2 °C/cycle → target drops 2% (floor: 72%)

When temperatures stabilise, the target returns to normal on the next decision cycle.

### Game Detection

SmartBypass queries the foreground app every few cycles and matches it against a built-in list of 60+ game publishers. It also checks the app's declared category as a fallback. When a game is detected while plugged in, bypass activates immediately regardless of battery level.

### Decision Logic (per cycle)

```
Unplugged?          → Bypass OFF
Gaming + plugged?   → Bypass ON  (highest priority)
Temp ≥ trigger?     → Bypass ON
Battery ≥ target?   → Bypass ON
Otherwise           → Bypass OFF
```

---

## Configuration

Create or edit `/data/adb/smartbypass/bypass.conf` — changes apply on the next cycle without a reboot.

```sh
# Battery level to hold at (default: 80)
BYPASS_TARGET=80

# Hysteresis band — resumes charging when battery drops this far below target (default: 2)
BYPASS_BAND=2

# Temperature (°C) that triggers bypass regardless of battery level (default: 38)
BYPASS_TEMP_TRIGGER=38

# Activate bypass automatically when gaming (default: 1 = enabled)
BYPASS_ON_GAME=1

# Deactivate bypass when charger is unplugged (default: 1 = enabled)
BYPASS_UNPLUG_OFF=1

# Maximum battery health ceiling — used when restoring charging (default: 100)
HEALTH_CEIL=100

# Log verbosity: 1 = normal, 2 = verbose (default: 1)
LOG_LEVEL=1

# Poll interval when idle / unplugged, seconds (default: 15)
POLL_INTERVAL=15

# Poll interval when active or plugged, seconds (default: 5)
ACTIVE_INTERVAL=5

# Poll interval while gaming, seconds (default: 3)
GAMING_INTERVAL=3

# Minimum seconds between emulated charge toggles — prevents IC stress (default: 30)
EMU_MIN_TOGGLE_INTERVAL=30

# How many cycles between game-detection runs — reduces dumpsys overhead (default: 4)
GAME_DETECT_INTERVAL=4
```

---

## Files & Logs

```
/data/adb/smartbypass/
├── bypass.conf          ← your config overrides
├── bypass.pid           ← engine PID (managed automatically)
├── bypass.stat          ← live status (readable at any time)
├── battery_health.stat  ← cumulative health & bypass-time totals
└── logs/
    └── bypass.log       ← rolling log (trimmed to 600 lines)
```

### Reading live status

```sh
cat /data/adb/smartbypass/bypass.stat
```

Example output:
```
BYPASS_MODE=ON
BYPASS_TYPE=XIAOMI
BYPASS_REASON=at_target(81%)
BATT=80
TEMP=36
PWR_MW=420
HEALTH=97
CYCLES=312
TOTAL_BYPASS_MIN=2847
DYN_TARGET=80
LAST=2026-04-19 14:22:05
```

### Sending a manual status dump to log

```sh
kill -USR1 $(cat /data/adb/smartbypass/bypass.pid)
```

---

## Stopping & Uninstalling

**Temporary stop** (survives reboot):
```sh
kill $(cat /data/adb/smartbypass/bypass.pid)
```

**Permanent uninstall** — disable the module in Magisk and reboot, or flash `uninstall.sh` directly. All charging nodes are restored to stock values on removal.

---

## Compatibility Notes

- **SELinux enforcing**: Most devices allow writes to `/sys/class/power_supply` from root. If bypass writes silently fail, check `dmesg` for AVC denials and add a custom sepolicy rule via Magisk.
- **KernelSU / APatch**: Supported. Ensure `service.sh` is executed on boot by your root solution.
- **Wireless charging**: Detected and treated as plugged-in. Bypass activates normally.
- **Multiple power supplies**: SmartBypass scans all `/sys/class/power_supply/*/` entries and validates each reading before use.

---

## Author:

Telegram: [mrk](https://t.me/mrkGL01)
