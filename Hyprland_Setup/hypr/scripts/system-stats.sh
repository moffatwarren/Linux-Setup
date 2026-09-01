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

# The first amdgpu/i915/nouveau render card. `device/gpu_busy_percent` only
# exists on amdgpu, so utilisation is simply absent on the others.
gpu_device() {
    local card
    for card in /sys/class/drm/card[0-9]*; do
        [ -e "$card/device/vendor" ] || continue
        echo "$card/device"
        return 0
    done
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
        break
    done
fi

# CPU: Intel's coretemp calls it "Package id 0", AMD's k10temp calls it "Tctl".
if cpu_hwmon=$(hwmon_by_name coretemp k10temp zenpower); then
    t=$(temp_input_by_label "$cpu_hwmon" '^(Package id 0|Tctl|Tdie)$') \
        && t=$(read_num "$t") && [ -n "$t" ] && add cpu_temp "$t"
fi

echo "{$json}"
