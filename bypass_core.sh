#!/system/bin/sh
# bypass_core.sh — SmartBypass v1.0
VERSION="1.0"
ENGINE="SmartBypass"
BASE_DIR="/data/adb/smartbypass"
LOG="$BASE_DIR/logs/bypass.log"
PID_FILE="$BASE_DIR/bypass.pid"
CONF="$BASE_DIR/bypass.conf"
HEALTH_FILE="$BASE_DIR/battery_health.stat"
STAT_FILE="$BASE_DIR/bypass.stat"

mkdir -p "$BASE_DIR/logs"
exec 200>"$PID_FILE"
flock -n 200 || exit 0
echo $$ >&200

[ "$(id -u)" -ne 0 ] && { echo "Root required" >&2; exit 1; }
echo -1000 > /proc/self/oom_score_adj 2>/dev/null
touch "$LOG"

[ -f "$CONF" ] && . "$CONF"

: "${BYPASS_TARGET:=80}"
: "${BYPASS_BAND:=2}"
: "${BYPASS_TEMP_TRIGGER:=38}"
: "${BYPASS_ON_GAME:=1}"
: "${BYPASS_UNPLUG_OFF:=1}"
: "${HEALTH_CEIL:=100}"
: "${LOG_LEVEL:=1}"
: "${POLL_INTERVAL:=15}"
: "${ACTIVE_INTERVAL:=5}"
: "${GAMING_INTERVAL:=3}"
: "${EMU_MIN_TOGGLE_INTERVAL:=30}"
: "${GAME_DETECT_INTERVAL:=4}"

: "${GAME_LIST:=com.garena com.activision com.miHoYo com.HoYoverse com.kurogame com.tencent.ig com.pubg com.dts.freefireth com.mojang com.mobile.legends com.riotgames com.supercell com.innersloth com.ea.gp com.netease com.epicgames com.blizzard com.gameloft com.kabam com.squareenix com.bandainamco com.sega com.nianticlabs com.nexon com.netmarble com.lilithgames com.yostar com.robtopx com.nekki com.fingersoft com.igg com.plarium com.scopely com.ketchapp com.miniclip com.gamevil com.snail com.gtarcade com.levelinfinite com.proximabeta com.dragonest com.tencent.tmgp com.tencent.lolm com.pearlabyss com.krafton com.xd com.neople}"

log() {
    _lvl=${3:-1}; [ "$_lvl" -gt "$LOG_LEVEL" ] && return
    echo "$(date '+%H:%M:%S') [$1] $2" >> "$LOG"
}

log_trim() {
    _lc=$(wc -l < "$LOG" 2>/dev/null)
    [ "${_lc:-0}" -gt 600 ] && tail -n 300 "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
}

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 2; done

log "INIT" "$ENGINE v$VERSION  PID=$$"

# read-back confirms the kernel accepted the value
write() {
    [ -f "$1" ] || return 1
    [ -w "$1" ] || return 1
    _wcur=$(cat "$1" 2>/dev/null) || return 1
    [ "$_wcur" = "$2" ] && return 0
    echo "$2" > "$1" 2>/dev/null || return 1
    _wcur=$(cat "$1" 2>/dev/null)
    [ "$_wcur" = "$2" ]
}

_exit_handler() {
    log "EXIT" "Signal — restoring normal charging"
    _restore_all_nodes
    flock -u 200 2>/dev/null
    rm -f "$PID_FILE"
    exit 0
}

_stat_handler() {
    _batt=$(get_batt); _temp=$(get_temp)
    log "STAT" "MODE=$BYPASS_MODE TYPE=$BYPASS_TYPE BATT=${_batt}% TEMP=${_temp}C PLUGGED=$PLUGGED GAME=$IS_GAME($CUR_APP)"
    _save_stat
}

trap '_exit_handler' TERM INT
trap '_stat_handler' USR1

BYPASS_TYPE="EMULATED"
BYPASS_NODE=""
BYPASS_NODE2=""
CHARGE_LIMIT_NODE=""
INPUT_SUSPEND_NODE=""
CHARGE_ENABLE_NODE=""
BYPASS_NATIVE=0

detect_bypass_hardware() {
    log "DETECT" "Scanning hardware bypass nodes..."

    if [ -f /sys/class/power_supply/battery/charge_control_end_threshold ] && \
       [ -f /proc/driver/charger_limit_enable ]; then
        BYPASS_TYPE="ASUS_ROG"
        CHARGE_LIMIT_NODE="/sys/class/power_supply/battery/charge_control_end_threshold"
        BYPASS_NODE="/proc/driver/charger_limit_enable"
        BYPASS_NATIVE=1
        log "DETECT" "ASUS ROG — native hardware bypass rail"
        return
    fi

    if [ -f /sys/class/power_supply/battery/charge_control_end_threshold ] && \
       [ -f /sys/class/power_supply/battery/charge_control_start_threshold ]; then
        BYPASS_TYPE="ASUS_DUAL"
        CHARGE_LIMIT_NODE="/sys/class/power_supply/battery/charge_control_end_threshold"
        BYPASS_NODE2="/sys/class/power_supply/battery/charge_control_start_threshold"
        BYPASS_NATIVE=1
        log "DETECT" "ASUS dual-threshold native bypass"
        return
    fi

    _ll=$(ls /sys/bus/platform/drivers/lenovo_battery_curve/*/charge_mode 2>/dev/null | head -1)
    if [ -n "$_ll" ]; then
        BYPASS_TYPE="LENOVO_LEGION"
        BYPASS_NODE="$_ll"
        BYPASS_NATIVE=1
        log "DETECT" "Lenovo Legion — native bypass mode: $_ll"
        return
    fi
    if [ -f /sys/class/power_supply/lenovo_battery/charge_control_end_threshold ]; then
        BYPASS_TYPE="LENOVO_LEGION"
        CHARGE_LIMIT_NODE="/sys/class/power_supply/lenovo_battery/charge_control_end_threshold"
        BYPASS_NATIVE=1
        log "DETECT" "Lenovo Legion charge threshold"
        return
    fi

    for _n in \
        /sys/class/power_supply/battery/game_mode \
        /sys/devices/platform/charger/game_charging_mode; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            BYPASS_TYPE="REDMAGIC"
            BYPASS_NODE="$_n"
            BYPASS_NATIVE=1
            log "DETECT" "RedMagic game bypass: $_n"
            return
        }
    done

    for _n in \
        /sys/class/power_supply/battery/batt_slate_mode \
        /sys/class/power_supply/battery/store_mode; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            BYPASS_TYPE="SAMSUNG"
            BYPASS_NODE="$_n"
            BYPASS_NATIVE=1
            log "DETECT" "Samsung bypass mode: $_n"
            return
        }
    done

    for _n in \
        /sys/class/power_supply/battery/op_charge_mode \
        /sys/class/power_supply/battery/oem_charge_mode \
        /sys/class/power_supply/battery/mmi_charging_enable; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            BYPASS_TYPE="ONEPLUS_OPPO"
            BYPASS_NODE="$_n"
            BYPASS_NATIVE=1
            log "DETECT" "OnePlus/OPPO charge mode: $_n"
            return
        }
    done

    if [ -f /sys/class/power_supply/battery/input_suspend ] && \
       [ -w /sys/class/power_supply/battery/input_suspend ]; then
        BYPASS_TYPE="XIAOMI"
        INPUT_SUSPEND_NODE="/sys/class/power_supply/battery/input_suspend"
        [ -f /sys/class/power_supply/battery/charge_control_end_threshold ] && \
            CHARGE_LIMIT_NODE="/sys/class/power_supply/battery/charge_control_end_threshold"
        BYPASS_NATIVE=1
        log "DETECT" "Xiaomi input_suspend — near-native bypass"
        return
    fi

    for _n in \
        /sys/class/power_supply/usb/input_suspend \
        /sys/class/power_supply/main/input_suspend \
        /sys/class/power_supply/ac/input_suspend \
        /sys/class/power_supply/dc/input_suspend; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            BYPASS_TYPE="INPUT_SUSPEND"
            INPUT_SUSPEND_NODE="$_n"
            BYPASS_NATIVE=1
            log "DETECT" "Generic input_suspend: $_n"
            return
        }
    done

    for _n in \
        /sys/class/power_supply/battery/charging_enabled \
        /sys/class/power_supply/battery/charge_enabled \
        /sys/class/power_supply/battery/enable_charging \
        /sys/class/power_supply/battery/battery_charging_enabled; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            BYPASS_TYPE="CHARGE_ENABLE"
            CHARGE_ENABLE_NODE="$_n"
            log "DETECT" "Charge enable toggle: $_n"
            break
        }
    done

    for _n in \
        /sys/class/power_supply/battery/charge_control_end_threshold \
        /sys/class/power_supply/main/charge_control_end_threshold \
        /sys/class/power_supply/bms/charge_control_end_threshold \
        /sys/class/power_supply/battery/constant_charge_voltage_max; do
        [ -f "$_n" ] && [ -w "$_n" ] && {
            CHARGE_LIMIT_NODE="$_n"
            [ "$BYPASS_TYPE" = "EMULATED" ] && BYPASS_TYPE="CHARGE_LIMIT"
            log "DETECT" "Charge limit node: $_n"
            break
        }
    done

    [ "$BYPASS_TYPE" = "EMULATED" ] && \
        log "DETECT" "No native nodes — using emulated bypass"

    log "DETECT" "Final type=$BYPASS_TYPE native=$BYPASS_NATIVE"
}

BYPASS_MODE="OFF"
BYPASS_START_TS=0

_accum_bypass_time() {
    [ "$BYPASS_MODE" = "ON" ] || return
    [ "${BYPASS_START_TS:-0}" -gt 0 ] || return
    _now=$(date +%s)
    _delta_min=$(( (_now - BYPASS_START_TS) / 60 ))
    TOTAL_BYPASS_MIN=$(( TOTAL_BYPASS_MIN + _delta_min ))
    BYPASS_START_TS=$_now
}

_bypass_activate() {
    _tgt=$1; _band=$2
    _start=$(( _tgt - _band ))

    case "$BYPASS_TYPE" in
        ASUS_ROG)
            write "$CHARGE_LIMIT_NODE" "$_tgt"
            write "$BYPASS_NODE" 1
            log "ON" "ASUS ROG: rail ON  limit=${_tgt}%";;
        ASUS_DUAL)
            write "$BYPASS_NODE2" "$_start"
            write "$CHARGE_LIMIT_NODE" "$_tgt"
            log "ON" "ASUS dual: start=${_start}% end=${_tgt}%";;
        LENOVO_LEGION)
            write "$BYPASS_NODE" 1 2>/dev/null || write "$BYPASS_NODE" "$_tgt"
            log "ON" "Lenovo Legion bypass mode";;
        REDMAGIC)
            write "$BYPASS_NODE" 1
            log "ON" "RedMagic game bypass";;
        SAMSUNG)
            write "$BYPASS_NODE" 1
            log "ON" "Samsung bypass/slate mode";;
        ONEPLUS_OPPO)
            write "$BYPASS_NODE" 0
            log "ON" "OnePlus/OPPO charge OFF (bypass)";;
        XIAOMI)
            [ -n "$CHARGE_LIMIT_NODE" ] && write "$CHARGE_LIMIT_NODE" "$_tgt"
            write "$INPUT_SUSPEND_NODE" 1
            log "ON" "Xiaomi input suspended at ${_tgt}%";;
        INPUT_SUSPEND)
            write "$INPUT_SUSPEND_NODE" 1
            log "ON" "Input suspended";;
        CHARGE_ENABLE)
            write "$CHARGE_ENABLE_NODE" 0
            [ -n "$CHARGE_LIMIT_NODE" ] && write "$CHARGE_LIMIT_NODE" "$_tgt"
            log "ON" "Charge disabled at ${_tgt}%";;
        CHARGE_LIMIT)
            write "$CHARGE_LIMIT_NODE" "$_tgt"
            log "ON" "Charge limited to ${_tgt}%";;
        EMULATED)
            log "ON" "Emulated bypass — holding at ${_tgt}% (band ${_band}%)";;
    esac

    BYPASS_MODE="ON"
    [ "${BYPASS_START_TS:-0}" -le 0 ] && BYPASS_START_TS=$(date +%s)
    _save_stat
}

_bypass_deactivate() {
    _accum_bypass_time
    BYPASS_START_TS=0

    case "$BYPASS_TYPE" in
        ASUS_ROG)
            write "$BYPASS_NODE" 0
            write "$CHARGE_LIMIT_NODE" "$HEALTH_CEIL";;
        ASUS_DUAL)
            write "$BYPASS_NODE2" 0
            write "$CHARGE_LIMIT_NODE" "$HEALTH_CEIL";;
        LENOVO_LEGION)
            write "$BYPASS_NODE" 0 2>/dev/null;;
        REDMAGIC)
            write "$BYPASS_NODE" 0;;
        SAMSUNG)
            write "$BYPASS_NODE" 0;;
        ONEPLUS_OPPO)
            write "$BYPASS_NODE" 1;;
        XIAOMI|INPUT_SUSPEND)
            write "$INPUT_SUSPEND_NODE" 0
            [ -n "$CHARGE_LIMIT_NODE" ] && write "$CHARGE_LIMIT_NODE" "$HEALTH_CEIL";;
        CHARGE_ENABLE)
            write "$CHARGE_ENABLE_NODE" 1
            [ -n "$CHARGE_LIMIT_NODE" ] && write "$CHARGE_LIMIT_NODE" "$HEALTH_CEIL";;
        CHARGE_LIMIT)
            write "$CHARGE_LIMIT_NODE" "$HEALTH_CEIL";;
        EMULATED)
            _emu_resume;;
    esac

    BYPASS_MODE="OFF"
    log "OFF" "Bypass deactivated — normal charging restored"
    _save_stat
}

_restore_all_nodes() {
    for _n in \
        /sys/class/power_supply/battery/charge_control_end_threshold \
        /sys/class/power_supply/battery/charge_control_start_threshold \
        /sys/class/power_supply/main/charge_control_end_threshold \
        /sys/class/power_supply/bms/charge_control_end_threshold \
        /sys/class/power_supply/lenovo_battery/charge_control_end_threshold; do
        [ -f "$_n" ] && [ -w "$_n" ] && echo 100 > "$_n" 2>/dev/null
    done
    for _n in \
        /sys/class/power_supply/battery/input_suspend \
        /sys/class/power_supply/usb/input_suspend \
        /sys/class/power_supply/main/input_suspend \
        /sys/class/power_supply/ac/input_suspend; do
        [ -f "$_n" ] && [ -w "$_n" ] && echo 0 > "$_n" 2>/dev/null
    done
    for _n in \
        /sys/class/power_supply/battery/charging_enabled \
        /sys/class/power_supply/battery/charge_enabled \
        /sys/class/power_supply/battery/enable_charging \
        /sys/class/power_supply/battery/battery_charging_enabled; do
        [ -f "$_n" ] && [ -w "$_n" ] && echo 1 > "$_n" 2>/dev/null
    done
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
    log "RESTORE" "All charging nodes reset to stock"
}
# dev: yubk/gellado/mrk

EMU_STATE="IDLE"
EMU_LAST_TOGGLE=0
EMU_TOGGLE_COUNT=0

_emu_pause() {
    _now=$(date +%s)
    EMU_LAST_TOGGLE=${EMU_LAST_TOGGLE:-0}
    _since=$(( _now - EMU_LAST_TOGGLE ))
    [ "$_since" -lt "$EMU_MIN_TOGGLE_INTERVAL" ] && return

    [ -n "$CHARGE_ENABLE_NODE" ] && { write "$CHARGE_ENABLE_NODE" 0; EMU_LAST_TOGGLE=$_now; return; }
    [ -n "$INPUT_SUSPEND_NODE" ] && { write "$INPUT_SUSPEND_NODE" 1; EMU_LAST_TOGGLE=$_now; return; }
    [ -n "$CHARGE_LIMIT_NODE"  ] && { write "$CHARGE_LIMIT_NODE" "$BYPASS_TARGET"; EMU_LAST_TOGGLE=$_now; return; }
    for _n in \
        /sys/class/power_supply/battery/charging_enabled \
        /sys/class/power_supply/battery/charge_enabled \
        /sys/class/power_supply/battery/enable_charging; do
        [ -f "$_n" ] && [ -w "$_n" ] && { write "$_n" 0; EMU_LAST_TOGGLE=$_now; return; }
    done
    EMU_LAST_TOGGLE=$_now
}

_emu_resume() {
    [ -n "$CHARGE_ENABLE_NODE" ] && { write "$CHARGE_ENABLE_NODE" 1; return; }
    [ -n "$INPUT_SUSPEND_NODE" ] && { write "$INPUT_SUSPEND_NODE" 0; return; }
    [ -n "$CHARGE_LIMIT_NODE"  ] && { write "$CHARGE_LIMIT_NODE" 100; return; }
    for _n in \
        /sys/class/power_supply/battery/charging_enabled \
        /sys/class/power_supply/battery/charge_enabled \
        /sys/class/power_supply/battery/enable_charging; do
        [ -f "$_n" ] && [ -w "$_n" ] && { write "$_n" 1; return; }
    done
}

# takes PLUGGED not CHRG — status goes "Not charging" the moment we
# pause it, which would flip the state back on the very next cycle
_emulated_step() {
    _batt=$1; _tgt=$2; _band=$3; _plugged=$4
    _resume=$(( _tgt - _band ))

    [ "$_plugged" = "0" ] && {
        if [ "$EMU_STATE" != "UNPLUGGED" ]; then
            EMU_STATE="UNPLUGGED"
            log "EMU" "Unplugged — emulation paused" 2
        fi
        return
    }

    if [ "$_batt" -ge "$_tgt" ]; then
        if [ "$EMU_STATE" != "PAUSED" ]; then
            _emu_pause
            EMU_STATE="PAUSED"
            EMU_TOGGLE_COUNT=$(( EMU_TOGGLE_COUNT + 1 ))
            log "EMU" "Paused charging at ${_batt}% (target=${_tgt}%)"
        fi
    elif [ "$_batt" -le "$_resume" ]; then
        if [ "$EMU_STATE" != "CHARGING" ]; then
            _emu_resume
            EMU_STATE="CHARGING"
            EMU_TOGGLE_COUNT=$(( EMU_TOGGLE_COUNT + 1 ))
            log "EMU" "Resumed charging from ${_batt}% → ${_tgt}%"
        fi
    fi
}

# TEMP_RATE is stored x10 (fixed-point) to avoid truncation from /10
PREV_TEMP=0; TEMP_RATE=0; TH1=0; TH2=0

get_temp() {
    _best=0; _best_prio=0
    for _z in /sys/class/thermal/thermal_zone*; do
        [ -f "$_z/type" ] && [ -f "$_z/temp" ] || continue
        _tp=$(cat "$_z/type" 2>/dev/null); [ -z "$_tp" ] && continue
        _v=$(cat "$_z/temp"  2>/dev/null); [ -z "$_v"  ] && continue
        [ "$_v" -gt 1000 ] 2>/dev/null && _v=$(( _v / 1000 ))
        { [ "$_v" -le 0 ] || [ "$_v" -ge 120 ]; } 2>/dev/null && continue
        case "$_tp" in
            *skin*|*xo_therm*|*quiet*) _p=3;;
            *cpu*|*soc*|*tsens*|*big*) _p=2;;
            *battery*|*batt*)          _p=2;;
            *)                          _p=1;;
        esac
        if [ "$_p" -gt "$_best_prio" ] || \
           { [ "$_p" -eq "$_best_prio" ] && [ "$_v" -gt "$_best" ]; }; then
            _best=$_v; _best_prio=$_p
        fi
    done
    if [ "$_best" -eq 0 ]; then
        _bt=$(cat /sys/class/power_supply/battery/temp 2>/dev/null)
        if [ -n "$_bt" ]; then
            [ "$_bt" -gt 1000 ] 2>/dev/null && _bt=$(( _bt / 10 ))
            _best=$_bt
        fi
    fi
    echo "${_best:-35}"
}

thermal_update() {
    _cur=${1:-35}
    TH1=${TH1:-0}; TH2=${TH2:-0}; PREV_TEMP=${PREV_TEMP:-0}
    if [ "$PREV_TEMP" -gt 0 ]; then
        _d=$(( _cur - PREV_TEMP ))
        TEMP_RATE=$(( _d*6 + TH1*3 + TH2 ))
        TH2=$TH1; TH1=$_d
    fi
    PREV_TEMP=$_cur
}

effective_bypass_target() {
    _base=$BYPASS_TARGET
    # x10 scale: 30 ≈ +3°C/cycle avg, 20 ≈ +2°C/cycle avg
    if [ "$TEMP_RATE" -ge 30 ]; then
        _base=$(( _base - 5 ))
        [ "$_base" -lt 70 ] && _base=70
    elif [ "$TEMP_RATE" -ge 20 ]; then
        _base=$(( _base - 2 ))
        [ "$_base" -lt 72 ] && _base=72
    fi
    echo "$_base"
}

get_batt() {
    for _f in /sys/class/power_supply/*/capacity; do
        [ -f "$_f" ] && [ -r "$_f" ] || continue
        _b=$(cat "$_f" 2>/dev/null)
        [ -n "$_b" ] && [ "$_b" -ge 0 ] 2>/dev/null && \
            [ "$_b" -le 100 ] 2>/dev/null && echo "$_b" && return
    done
    echo "50"
}

is_charging() {
    for _f in /sys/class/power_supply/*/status; do
        [ -f "$_f" ] && [ -r "$_f" ] || continue
        _s=$(cat "$_f" 2>/dev/null)
        case "$_s" in Charging|Full) echo 1; return;; esac
    done
    echo 0
}

is_plugged() {
    for _supply in usb ac wireless dc; do
        _f="/sys/class/power_supply/${_supply}/online"
        [ -f "$_f" ] && [ "$(cat "$_f" 2>/dev/null)" = "1" ] && { echo 1; return; }
    done
    echo 0
}

get_charge_rate_mw() {
    _v=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
    _i=$(cat /sys/class/power_supply/battery/current_now 2>/dev/null)
    if [ -n "$_v" ] && [ -n "$_i" ]; then
        [ "$_i" -lt 0 ] 2>/dev/null && _i=$(( -_i ))
        echo $(( _v / 1000 * _i / 1000000 ))
        return
    fi
    _p=$(cat /sys/class/power_supply/battery/power_now 2>/dev/null)
    [ -n "$_p" ] && { echo $(( _p / 1000 )); return; }
    echo 0
}

get_battery_health() {
    _f=$(cat /sys/class/power_supply/battery/charge_full        2>/dev/null)
    _d=$(cat /sys/class/power_supply/battery/charge_full_design 2>/dev/null)
    [ -n "$_f" ] && [ -n "$_d" ] && [ "$_d" -gt 0 ] && \
        { echo $(( _f * 100 / _d )); return; }
    echo 100
}

get_cycles() {
    _c=$(cat /sys/class/power_supply/battery/cycle_count 2>/dev/null)
    echo "${_c:-0}"
}

CUR_APP=""; IS_GAME=0; GAME_DETECT_CYCLE=0

detect_game() {
    _app=$(timeout 2 dumpsys activity activities 2>/dev/null \
        | grep -m1 "topResumedActivity\|mResumedActivity" \
        | grep -oE '[a-zA-Z][a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d'/' -f1)
    [ -z "$_app" ] && _app=$(timeout 2 dumpsys window windows 2>/dev/null \
        | grep -m1 "mCurrentFocus\|mFocusedApp" \
        | grep -oE '[a-zA-Z][a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1 | cut -d'/' -f1)
    CUR_APP="$_app"; IS_GAME=0
    [ -z "$_app" ] && return
    for _pkg in $GAME_LIST; do
        case "$_app" in *${_pkg}*) IS_GAME=1; return;; esac
    done
    _cat=$(timeout 2 dumpsys package "$_app" 2>/dev/null | grep -i "category" | head -1)
    case "$_cat" in *game*|*GAME*) IS_GAME=1;; esac
}

detect_game_cached() {
    GAME_DETECT_CYCLE=$(( GAME_DETECT_CYCLE + 1 ))
    if [ "$GAME_DETECT_CYCLE" -ge "${GAME_DETECT_INTERVAL:-4}" ]; then
        detect_game
        GAME_DETECT_CYCLE=0
    fi
}

BYPASS_REASON="none"

should_bypass() {
    _batt=$1; _temp=$2; _plugged=$3; _game=$4

    if [ "$_plugged" = "0" ] && [ "$BYPASS_UNPLUG_OFF" = "1" ]; then
        BYPASS_REASON="unplugged"; echo 0; return
    fi
    if [ "$_game" = "1" ] && [ "$_plugged" = "1" ] && [ "$BYPASS_ON_GAME" = "1" ]; then
        BYPASS_REASON="gaming"; echo 1; return
    fi
    if [ "$_temp" -ge "$BYPASS_TEMP_TRIGGER" ] && [ "$_plugged" = "1" ]; then
        BYPASS_REASON="thermal(${_temp}C)"; echo 1; return
    fi
    if [ "$_batt" -ge "$BYPASS_TARGET" ] && [ "$_plugged" = "1" ]; then
        BYPASS_REASON="at_target(${_batt}%)"; echo 1; return
    fi

    BYPASS_REASON="normal"; echo 0
}

SESSION_START=$(date +%s)
TOTAL_BYPASS_MIN=0

[ -f "$HEALTH_FILE" ] && . "$HEALTH_FILE"
: "${TOTAL_BYPASS_MIN:=0}"

_save_stat() {
    _h=$(get_battery_health)
    _c=$(get_cycles)
    _batt=$(get_batt)
    _temp=$(get_temp)
    _pwr=$(get_charge_rate_mw)

    printf "BYPASS_MODE=%s\nBYPASS_TYPE=%s\nBYPASS_REASON=%s\nBATT=%s\nTEMP=%s\nPWR_MW=%s\nHEALTH=%s\nCYCLES=%s\nTOTAL_BYPASS_MIN=%s\nDYN_TARGET=%s\nLAST=%s\n" \
        "$BYPASS_MODE" "$BYPASS_TYPE" "$BYPASS_REASON" \
        "$_batt" "$_temp" "$_pwr" "$_h" "$_c" \
        "$TOTAL_BYPASS_MIN" "${DYN_TARGET:-$BYPASS_TARGET}" \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        > "$STAT_FILE"
}

_save_health() {
    _accum_bypass_time
    _h=$(get_battery_health); _c=$(get_cycles)
    printf "HEALTH=%s\nCYCLES=%s\nTOTAL_BYPASS_MIN=%s\nLAST_UPDATE=%s\n" \
        "$_h" "$_c" "$TOTAL_BYPASS_MIN" "$(date '+%Y-%m-%d %H:%M')" \
        > "$HEALTH_FILE"
}

detect_bypass_hardware

[ -f "$STAT_FILE" ] && . "$STAT_FILE"
: "${DYN_TARGET:=$BYPASS_TARGET}"
BYPASS_MODE="OFF"

_h=$(get_battery_health); _c=$(get_cycles)
log "INIT" "Battery health=${_h}%  cycles=${_c}"
log "INIT" "Bypass: type=$BYPASS_TYPE native=$BYPASS_NATIVE"
log "INIT" "Config: target=${BYPASS_TARGET}% band=${BYPASS_BAND}% temp_trigger=${BYPASS_TEMP_TRIGGER}C"

CYCLE=0; PREV_BYPASS_ON=0

log "LOOP" "Main loop started"

while true; do

    BATT=$(get_batt)
    TEMP=$(get_temp)
    CHRG=$(is_charging)
    PLUGGED=$(is_plugged)
    PWR=$(get_charge_rate_mw)
    detect_game_cached
    thermal_update "$TEMP"

    DYN_TARGET=$(effective_bypass_target)
    DO_BYPASS=$(should_bypass "$BATT" "$TEMP" "$PLUGGED" "$IS_GAME")

    if [ "$DO_BYPASS" = "1" ] && [ "$BYPASS_MODE" != "ON" ]; then
        _bypass_activate "$DYN_TARGET" "$BYPASS_BAND"
        log "ON" "Bypass ON — reason=$BYPASS_REASON  batt=${BATT}% temp=${TEMP}C target=${DYN_TARGET}%"
        PREV_BYPASS_ON=1
    elif [ "$DO_BYPASS" = "0" ] && [ "$BYPASS_MODE" = "ON" ]; then
        _bypass_deactivate
        log "OFF" "Bypass OFF — reason=$BYPASS_REASON  batt=${BATT}%"
        PREV_BYPASS_ON=0
    fi

    [ "$BYPASS_TYPE" = "EMULATED" ] && [ "$DO_BYPASS" = "1" ] && \
        _emulated_step "$BATT" "$DYN_TARGET" "$BYPASS_BAND" "$PLUGGED"

    if [ "$BYPASS_MODE" = "ON" ] && [ "$BYPASS_TYPE" != "EMULATED" ] && \
       [ "$DYN_TARGET" != "$BYPASS_TARGET" ]; then
        _bypass_activate "$DYN_TARGET" "$BYPASS_BAND"
    fi

    CYCLE=$(( CYCLE + 1 ))

    [ $(( CYCLE % 3 )) -eq 0 ] && \
        log "RUN" "BATT=${BATT}% TEMP=${TEMP}C(rate=${TEMP_RATE}) PWR=${PWR}mW CHRG=$CHRG PLUGGED=$PLUGGED MODE=$BYPASS_MODE REASON=$BYPASS_REASON GAME=$IS_GAME($CUR_APP)" 2

    log "RUN" "BATT=${BATT}% TEMP=${TEMP}C MODE=$BYPASS_MODE REASON=$BYPASS_REASON"

    [ $(( CYCLE % 12 )) -eq 0 ] && { _save_health; _save_stat; log_trim; }

    if [ "$IS_GAME" = "1" ] && [ "$PLUGGED" = "1" ]; then
        sleep "$GAMING_INTERVAL"
    elif [ "$BYPASS_MODE" = "ON" ] || [ "$PLUGGED" = "1" ]; then
        sleep "$ACTIVE_INTERVAL"
    else
        sleep "$POLL_INTERVAL"
    fi

done
