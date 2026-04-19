#!/system/bin/sh
# SmartBypass v1.0 — uninstall.sh
BASE_DIR="/data/adb/smartbypass"
PID_FILE="$BASE_DIR/bypass.pid"
LOG="$BASE_DIR/logs/bypass.log"

echo "$(date '+%H:%M:%S') [UNINSTALL] SmartBypass v1.0 removing..." >> "$LOG" 2>/dev/null

# ── Stop engine gracefully, then force-kill if needed ──
if [ -f "$PID_FILE" ]; then
    _pid=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$_pid" ] && [ -d "/proc/$_pid" ]; then
        kill "$_pid" 2>/dev/null
        sleep 2
        [ -d "/proc/$_pid" ] && kill -9 "$_pid" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi

# Kill any orphan processes
for _p in $(ps 2>/dev/null | grep "[b]ypass_core" | awk '{print $1}'); do
    kill "$_p" 2>/dev/null
done

# ── Restore charge limit thresholds ──
for _n in \
    /sys/class/power_supply/battery/charge_control_end_threshold \
    /sys/class/power_supply/battery/charge_control_start_threshold \
    /sys/class/power_supply/main/charge_control_end_threshold \
    /sys/class/power_supply/bms/charge_control_end_threshold \
    /sys/class/power_supply/lenovo_battery/charge_control_end_threshold; do
    [ -f "$_n" ] && [ -w "$_n" ] && echo 100 > "$_n" 2>/dev/null
done

# ── Restore input suspend ──
for _n in \
    /sys/class/power_supply/battery/input_suspend \
    /sys/class/power_supply/usb/input_suspend \
    /sys/class/power_supply/main/input_suspend \
    /sys/class/power_supply/ac/input_suspend; do
    [ -f "$_n" ] && [ -w "$_n" ] && echo 0 > "$_n" 2>/dev/null
done

# ── Restore charging enable ──
for _n in \
    /sys/class/power_supply/battery/charging_enabled \
    /sys/class/power_supply/battery/charge_enabled \
    /sys/class/power_supply/battery/enable_charging \
    /sys/class/power_supply/battery/battery_charging_enabled; do
    [ -f "$_n" ] && [ -w "$_n" ] && echo 1 > "$_n" 2>/dev/null
done

# ── Restore vendor-specific nodes ──
[ -f /proc/driver/charger_limit_enable ] && \
    echo 0 > /proc/driver/charger_limit_enable 2>/dev/null
[ -f /sys/class/power_supply/battery/batt_slate_mode ] && \
    echo 0 > /sys/class/power_supply/battery/batt_slate_mode 2>/dev/null
[ -f /sys/class/power_supply/battery/store_mode ] && \
    echo 0 > /sys/class/power_supply/battery/store_mode 2>/dev/null
[ -f /sys/class/power_supply/battery/game_mode ] && \
    echo 0 > /sys/class/power_supply/battery/game_mode 2>/dev/null
for _n in \
    /sys/class/power_supply/battery/op_charge_mode \
    /sys/class/power_supply/battery/oem_charge_mode; do
    [ -f "$_n" ] && [ -w "$_n" ] && echo 1 > "$_n" 2>/dev/null
done

# ── Remove data directory ──
rm -rf "$BASE_DIR"

echo "$(date '+%H:%M:%S') [UNINSTALL] Done — charging fully restored" >> "$LOG" 2>/dev/null
