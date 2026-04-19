#!/system/bin/sh
# SmartBypass v1.0 — service.sh
MODDIR="${0%/*}"
BASE_DIR="/data/adb/smartbypass"
CORE="$BASE_DIR/bypass_core.sh"
LOG="$BASE_DIR/logs/bypass.log"
PID_FILE="$BASE_DIR/bypass.pid"
until [ "$(getprop sys.boot_completed)" = "1" ]; do
    sleep 2
done
sleep 5
mkdir -p "$BASE_DIR/logs"
touch "$LOG"
if [ -f "$PID_FILE" ]; then
    _old=$(cat "$PID_FILE" 2>/dev/null)
    if [ -n "$_old" ] && [ -d "/proc/$_old" ]; then
        kill "$_old" 2>/dev/null
        sleep 2
        [ -d "/proc/$_old" ] && kill -9 "$_old" 2>/dev/null
    fi
    rm -f "$PID_FILE"
fi
if [ -f "$MODDIR/bypass_core.sh" ]; then
    cp "$MODDIR/bypass_core.sh" "$CORE"
    chmod 755 "$CORE"
fi
if [ -f "$CORE" ]; then
    (sh "$CORE" >> "$LOG" 2>&1) &
    echo $! > "$PID_FILE"
    echo "$(date '+%H:%M:%S') [BOOT] SmartBypass v1.0 engine started PID=$(cat "$PID_FILE")" >> "$LOG"
else
    echo "$(date '+%H:%M:%S') [BOOT] ERROR: bypass_core.sh not found at $CORE" >> "$LOG"
fi
