#!/usr/bin/env bash
# System vitals for the quickshell power-profile module's hover panel.
#
# Prints one JSON object of raw numbers -- bytes, percentages and millidegrees
# -- and leaves every bit of formatting to the QML side. A value that cannot be
# read is omitted rather than reported as 0, so the panel can drop the row
# instead of showing a confidently wrong reading.
#
# Sensor paths are discovered by name, never by index: hwmonN numbering is
# assigned in probe order and changes between boots, and the DRM card index
# moves the same way.

set -uo pipefail

# --- sensor discovery -------------------------------------------------------

# The hwmon whose `name` is one of the arguments, e.g. `hwmon_by_name coretemp
# k10temp`. First match wins, so list them most-specific first.
hwmon_by_name() {
    local dir name want
    for dir in /sys/class/hwmon/hwmon*; do
        name=$(cat "$dir/name" 2>/dev/null) || continue
        for want in "$@"; do
            [ "$name" = "$want" ] && { echo "$dir"; return 0; }
        done
    done
    return 1
}

# The tempN_input in $1 whose tempN_label matches the regex $2. Falls back to
# temp1_input, which is the package/edge sensor on every driver used here.
temp_input_by_label() {
    local dir=$1 rx=$2 label
    for label in "$dir"/temp*_label; do
        [ -e "$label" ] || break
        if [[ $(cat "$label" 2>/dev/null) =~ $rx ]]; then
            echo "${label%_label}_input"
            return 0
        fi
    done
    [ -e "$dir/temp1_input" ] && { echo "$dir/temp1_input"; return 0; }
    return 1
}

# First power attribute in $1 (power*_average, power*_input) in microwatts.
power_input() {
    local dir=$1 p
    for p in "$dir"/power*_average "$dir"/power*_input; do
        [ -r "$p" ] || continue
        read_num "$p" && return 0
    done
    return 1
}

# The GPU to report on. A card exposing VRAM or utilisation (amdgpu) wins over
# the first card found, because on a machine with an iGPU *and* a discrete card
# the iGPU usually enumerates first -- and i915/xe expose no load, no VRAM and
# no hwmon, so picking it silently drops every GPU row and the power reading.
# Only with no such card does the first one (i915/nouveau) get used.
gpu_device() {
    local card first=""
    for card in /sys/class/drm/card[0-9]*; do
        [ -e "$card/device/vendor" ] || continue
        if [ -e "$card/device/mem_info_vram_total" ] || [ -e "$card/device/gpu_busy_percent" ]; then
            echo "$card/device"
            return 0
        fi
        [ -n "$first" ] || first="$card/device"
    done
    [ -n "$first" ] && { echo "$first"; return 0; }
    return 1
}

read_num() { [ -r "$1" ] && cat "$1" 2>/dev/null; }

# --- collection -------------------------------------------------------------

json=""
add() { json+="${json:+,}\"$1\":$2"; }

# Memory: MemAvailable is what the kernel thinks is actually reclaimable, which
# is the number `free` calls "available" and the only honest "used".
while read -r key value _; do
    case "$key" in
        MemTotal:)     mem_total=$((value * 1024)) ;;
        MemAvailable:) mem_avail=$((value * 1024)) ;;
    esac
done < /proc/meminfo
if [ -n "${mem_total:-}" ] && [ -n "${mem_avail:-}" ]; then
    add ram_used $((mem_total - mem_avail))
    add ram_total "$mem_total"
fi

# Disk: the root filesystem only. -B1 keeps everything in bytes.
if read -r _ dtotal dused _ < <(df -B1 --output=source,size,used,target / | tail -1); then
    add disk_used "$dused"
    add disk_total "$dtotal"
fi

gpu_power=""
cpu_power=""
busy=""
t=""
vused=""
gpu=$(gpu_device) || gpu=""
if [ -n "$gpu" ]; then
    busy=$(read_num "$gpu/gpu_busy_percent") && [ -n "$busy" ] && add gpu_pct "$busy"
    vused=$(read_num "$gpu/mem_info_vram_used")
    vtotal=$(read_num "$gpu/mem_info_vram_total")
    if [ -n "$vused" ] && [ -n "$vtotal" ] && [ "$vtotal" -gt 0 ]; then
        add vram_used "$vused"
        add vram_total "$vtotal"
    fi
    # The GPU's own hwmon hangs off the DRM device, so it needs no name search.
    for h in "$gpu"/hwmon/hwmon*; do
        [ -d "$h" ] || break
        t=$(temp_input_by_label "$h" '^edge$') && t=$(read_num "$t") \
            && [ -n "$t" ] && add gpu_temp "$t"
        p=$(power_input "$h") && [ -n "$p" ] && [ "$p" -gt 0 ] && gpu_power=$p
        break
    done
fi

# NVIDIA fallback via nvidia-smi if hwmon found no power (proprietary driver)
if [ -z "$gpu_power" ] && command -v nvidia-smi >/dev/null 2>&1; then
    nv_line=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw --format=csv,noheader,nounits 2>/dev/null | head -1)
    if [ -n "$nv_line" ]; then
        IFS=',' read -r nv_busy nv_temp nv_vused nv_vtotal nv_power <<< "$nv_line"
        nv_busy=$(echo "$nv_busy" | tr -d ' ')
        nv_temp=$(echo "$nv_temp" | tr -d ' ')
        nv_vused=$(echo "$nv_vused" | tr -d ' ')
        nv_vtotal=$(echo "$nv_vtotal" | tr -d ' ')
        nv_power=$(echo "$nv_power" | tr -d ' ')

        [ -z "$busy" ] && [[ "$nv_busy" =~ ^[0-9]+$ ]] && add gpu_pct "$nv_busy"
        [ -z "$t" ] && [[ "$nv_temp" =~ ^[0-9]+$ ]] && [ "$nv_temp" -gt 0 ] && add gpu_temp "$((nv_temp * 1000))"
        if [ -z "$vused" ] && [[ "$nv_vused" =~ ^[0-9]+$ ]] && [[ "$nv_vtotal" =~ ^[0-9]+$ ]]; then
            add vram_used "$((nv_vused * 1024 * 1024))"
            add vram_total "$((nv_vtotal * 1024 * 1024))"
        fi
        if [[ "$nv_power" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            gpu_power=$(awk "BEGIN {print int($nv_power * 1000000)}")
        fi
    fi
fi

# CPU: Intel's coretemp calls it "Package id 0", AMD's k10temp calls it "Tctl".
if cpu_hwmon=$(hwmon_by_name coretemp k10temp zenpower amd_energy); then
    t=$(temp_input_by_label "$cpu_hwmon" '^(Package id 0|Tctl|Tdie)$') \
        && t=$(read_num "$t") && [ -n "$t" ] && add cpu_temp "$t"
    p=$(power_input "$cpu_hwmon") && [ -n "$p" ] && [ "$p" -gt 0 ] && cpu_power=$p
fi

# Power: on laptops discharging, battery power measures whole-system draw.
# On desktops / AC, sum available CPU and GPU package sensors.
bat_power=""
for ps in /sys/class/power_supply/*; do
    [ -d "$ps" ] || continue
    type=$(cat "$ps/type" 2>/dev/null) || continue
    [ "$type" = "Battery" ] || continue
    p=$(read_num "$ps/power_now") && [ -n "$p" ] && [ "$p" -gt 0 ] && { bat_power=$p; break; }
    c=$(read_num "$ps/current_now") && v=$(read_num "$ps/voltage_now")
    if [ -n "$c" ] && [ -n "$v" ] && [ "$c" -gt 0 ] && [ "$v" -gt 0 ]; then
        bat_power=$(( (c * v) / 1000000 ))
        [ "$bat_power" -gt 0 ] && break
    fi
done

if [ -n "$bat_power" ]; then
    add power_uw "$bat_power"
elif [ -n "$cpu_power" ] || [ -n "$gpu_power" ]; then
    total_power=$(( ${cpu_power:-0} + ${gpu_power:-0} ))
    [ "$total_power" -gt 0 ] && add power_uw "$total_power"
fi

echo "{$json}"
