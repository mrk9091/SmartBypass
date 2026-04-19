#!/system/bin/sh
OUTFD=$2
ZIPFILE=$3

ui_print() {
    echo -e "ui_print $1\nui_print" >> /proc/self/fd/$OUTFD
}

abort() {
    ui_print ""
    ui_print "  ✗ ERROR: $1"
    ui_print ""
    exit 1
}
ok()   { ui_print "  ✓ $1"; }
info() { ui_print "  · $1"; }
warn() { ui_print "  ! $1"; }
sep()  { ui_print " "; }
# ── Header ──────────────────────────────────────────────────────
sep
ui_print "╔══════════════════════════════════════╗"
ui_print "║   SmartBypass v1.0                  ║"
ui_print "║   Advanced Bypass Charging           ║"
ui_print "║   All Android Devices Supported      ║"
ui_print "╚══════════════════════════════════════╝"
sep

# ── Checks ──────────────────────────────────────────────────────
[ "$(id -u)" != "0" ] && abort "Root required"
ok "Root confirmed"

[ -z "$MAGISK_VER_CODE" ] && warn "MAGISK_VER_CODE not set — continuing anyway"
[ -n "$MAGISK_VER" ] && info "Magisk: $MAGISK_VER"

# ── Device info ─────────────────────────────────────────────────
_model=$(getprop ro.product.model 2>/dev/null || echo "unknown")
_sdk=$(getprop ro.build.version.sdk 2>/dev/null || echo "unknown")
_cores=$(nproc 2>/dev/null || echo "?")
_ram_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | tr -dc '0-9')
_ram_gb=$(( ${_ram_kb:-4000000} / 1048576 ))
info "Device  : $_model"
info "SDK     : $_sdk"
info "CPU/RAM : ${_cores} cores / ${_ram_gb}GB"
sep

# ── Paths ───────────────────────────────────────────────────────
MODDIR="$NVBASE/modules/SmartBypass"
BASE_DIR="/data/adb/smartbypass"
CONF="$BASE_DIR/bypass.conf"

mkdir -p "$MODDIR"
mkdir -p "$BASE_DIR/logs"

# ── Extract files ───────────────────────────────────────────────
info "Extracting module files..."

unzip -o "$ZIPFILE" 'module.prop'    -d "$MODDIR" >&2 || abort "Failed to extract module.prop"
unzip -o "$ZIPFILE" 'service.sh'     -d "$MODDIR" >&2 || abort "Failed to extract service.sh"
unzip -o "$ZIPFILE" 'uninstall.sh'   -d "$MODDIR" >&2 || abort "Failed to extract uninstall.sh"
unzip -o "$ZIPFILE" 'bypass_core.sh' -d "$MODDIR" >&2 || abort "Failed to extract bypass_core.sh"

chmod 644 "$MODDIR/module.prop"
chmod 755 "$MODDIR/service.sh"
chmod 755 "$MODDIR/uninstall.sh"
chmod 755 "$MODDIR/bypass_core.sh"
ok "Module files extracted"

# Copy core to data dir (service.sh reads from here at boot)
cp "$MODDIR/bypass_core.sh" "$BASE_DIR/bypass_core.sh"
chmod 755 "$BASE_DIR/bypass_core.sh"
ok "Core engine staged: $BASE_DIR/bypass_core.sh"

sep

# ── Detect bypass hardware ───────────────────────────────────────
info "Scanning bypass hardware..."
_bypass_type="EMULATED (Universal Software Bypass)"

# ASUS ROG — native hardware bypass
if [ -f /sys/class/power_supply/battery/charge_control_end_threshold ] && \
   [ -f /proc/driver/charger_limit_enable ]; then
    _bypass_type="ASUS_ROG (Native Hardware Bypass)"

# ASUS — dual threshold
elif [ -f /sys/class/power_supply/battery/charge_control_end_threshold ] && \
     [ -f /sys/class/power_supply/battery/charge_control_start_threshold ]; then
    _bypass_type="ASUS_DUAL_THRESH (Native)"

# Lenovo Legion
elif [ -f /sys/bus/platform/drivers/lenovo_battery_curve/battery_charge_mode ] 2>/dev/null || \
     [ -f /sys/class/power_supply/lenovo_battery/charge_control_end_threshold ] 2>/dev/null; then
    _bypass_type="LENOVO_LEGION (Native)"

# RedMagic
elif [ -f /sys/class/power_supply/battery/game_mode ]; then
    _bypass_type="REDMAGIC (Native)"

# Samsung
elif [ -f /sys/class/power_supply/battery/batt_slate_mode ]; then
    _bypass_type="SAMSUNG_SLATE (Native)"

# Xiaomi
elif [ -f /sys/class/power_supply/battery/input_suspend ]; then
    _bypass_type="XIAOMI_INPUT_SUSPEND (Near-Native)"

# OnePlus / OPPO
elif [ -f /sys/class/power_supply/battery/op_charge_mode ]; then
    _bypass_type="ONEPLUS_OPPO (Near-Native)"

# Generic input suspend
elif [ -f /sys/class/power_supply/usb/input_suspend ]; then
    _bypass_type="GENERIC_INPUT_SUSPEND (Near-Native)"

# Generic charge enable toggle
elif [ -f /sys/class/power_supply/battery/charging_enabled ]; then
    _bypass_type="CHARGE_ENABLE (Software)"

# Generic charge limit threshold
elif [ -f /sys/class/power_supply/battery/charge_control_end_threshold ]; then
    _bypass_type="CHARGE_LIMIT (Software)"
fi

ok "Bypass method: $_bypass_type"
echo "DETECTED_TYPE=\"$_bypass_type\"" > "$BASE_DIR/detected_type"

sep

# ── Default config (skip if already exists) ──────────────────────
if [ ! -f "$CONF" ]; then
    info "Writing default config..."
    cat > "$CONF" << 'CONF_EOF'
# ════════════════════════════════════════════════════
# SmartBypass v1.0 — bypass.conf
# Edit values here. Restart engine or reboot to apply.
# ════════════════════════════════════════════════════

# Battery % to hold at while bypass is active (75–85 recommended)
BYPASS_TARGET=80

# Resume charging when battery drops this many % below target
# e.g. target=80, band=2 → charges 78→80 then holds
BYPASS_BAND=2

# Auto-enable bypass when device temp exceeds this (°C)
BYPASS_TEMP_TRIGGER=38

# Auto-enable bypass when a game is running and plugged in (0/1)
BYPASS_ON_GAME=1

# Disable bypass when charger is unplugged (1=recommended)
BYPASS_UNPLUG_OFF=1

# Charge ceiling in normal (non-bypass) mode
HEALTH_CEIL=100

# Logging verbosity: 1=normal  2=verbose
LOG_LEVEL=1

# Polling intervals (seconds)
POLL_INTERVAL=15
ACTIVE_INTERVAL=5
GAMING_INTERVAL=3
CONF_EOF
    ok "Config written: $CONF"
else
    ok "Existing config preserved: $CONF"
fi

# ── Done ─────────────────────────────────────────────────────────
sep
ui_print "╔══════════════════════════════════════╗"
ui_print "║  Installation complete!              ║"
ui_print "╚══════════════════════════════════════╝"
sep
ui_print "  Bypass method  : $_bypass_type"
ui_print "  Config file    : $CONF"
ui_print "  Log folder     : $BASE_DIR/logs/"
sep
ui_print "  Engine starts automatically on next boot."
ui_print "  Toggle ON/OFF anytime in Magisk → Modules."
sep
ui_print "  After reboot, check log:"
ui_print "  tail -f $BASE_DIR/logs/bypass.log"
sep
