#!/usr/bin/env bash
# System vitals for the quickshell power-profile module's menu.
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

# How strongly a card is wanted as "the GPU". Discrete beats integrated: on a
# machine with both, the discrete card is the one doing the work, and the iGPU
# usually enumerates first, so taking the first card reports the wrong one.
#   3  discrete -- NVIDIA; AMD with its own VRAM (amdgpu only creates
#      mem_info_vram_vendor when it can name the VRAM chips, which an APU's
#      carve-out of system RAM never has); Intel Arc (an i915/xe dGPU has a
#      hwmon of its own, an iGPU has none)
#   2  AMD APU -- integrated, but amdgpu still reports its load and VRAM
#   1  anything else, i.e. an Intel iGPU, which reports nothing at all
gpu_score() {
    case "$(cat "$1/vendor" 2>/dev/null)" in
        0x10de) echo 3 ;;
        0x1002) [ -e "$1/mem_info_vram_vendor" ] && echo 3 || echo 2 ;;
        0x8086) [ -d "$1/hwmon" ] && echo 3 || echo 1 ;;
        *)      echo 1 ;;
    esac
}

# The GPU to report on: the highest-scoring card, ties going to the most VRAM
# (an APU beside an AMD dGPU, should the vendor test ever miss) and then to the
# first found. A runtime-suspended card is skipped rather than read: asking
# amdgpu or nvidia-smi for a number powers a sleeping laptop dGPU back up, and
# polling it every two seconds would keep it awake for as long as the menu is
# open. Prints the resolved PCI device path, whose basename is the bus id.
gpu_device() {
    local card dev score vram best="" best_score=0 best_vram=-1
    for card in /sys/class/drm/card[0-9]*; do
        [[ ${card##*/} =~ ^card[0-9]+$ ]] || continue
        dev=$(readlink -f "$card/device") || continue
        [ -e "$dev/vendor" ] || continue
        [ "$(cat "$dev/power/runtime_status" 2>/dev/null)" = suspended ] && continue
        score=$(gpu_score "$dev")
        vram=$(read_num "$dev/mem_info_vram_total") || vram=0
        if [ "$score" -gt "$best_score" ] \
            || { [ "$score" -eq "$best_score" ] && [ "${vram:-0}" -gt "$best_vram" ]; }; then
            best=$dev best_score=$score best_vram=${vram:-0}
        fi
    done
    [ -n "$best" ] && { echo "$best"; return 0; }
    return 1
}

# A PCI device's name as lspci has it ("GB203 [GeForce RTX 5070 Ti]"), cached
# per bus id under XDG_RUNTIME_DIR: it cannot change while the machine is up,
# and lspci parses the whole pci.ids database on every call. Trimming it to the
# marketing name is display, and is left to the QML.
pci_name() {
    local cache="${XDG_RUNTIME_DIR:-/tmp}/system-stats-pcinames.$UID" key val=""
    if [ -r "$cache" ]; then
        while IFS=$'\t' read -r key val; do
            [ "$key" = "$1" ] && { echo "$val"; return 0; }
        done < "$cache"
    fi
    command -v lspci >/dev/null 2>&1 || return 1
    while IFS=$'\t' read -r key val; do
        [ "$key" = "Device:" ] && break
        val=""
    done < <(lspci -vmm -s "$1" 2>/dev/null)
    [ -n "$val" ] || return 1
    printf '%s\t%s\n' "$1" "$val" >> "$cache" 2>/dev/null
    echo "$val"
}

# NVIDIA's proprietary driver exposes nothing in sysfs, so the numbers come from
# nvidia-smi, asked for this card by PCI bus id so a second NVIDIA card cannot
# answer for it. A field the card does not support comes back "[N/A]" or
# "[Not Supported]" and fails its pattern, which omits the row.
nvidia_stats() {
    local line nv_busy nv_temp nv_vused nv_vtotal nv_power frac
    local nv_name
    # name goes last: it is the one field that could hold a comma, and the last
    # variable of a `read` takes the rest of the line.
    line=$(nvidia-smi --id="$1" --format=csv,noheader,nounits \
        --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,power.draw,name \
        2>/dev/null) || return 1
    IFS=',' read -r nv_busy nv_temp nv_vused nv_vtotal nv_power nv_name <<< "$line"
    nv_busy=${nv_busy// /} nv_temp=${nv_temp// /} nv_vused=${nv_vused// /}
    nv_vtotal=${nv_vtotal// /} nv_power=${nv_power// /} nv_name=${nv_name# }

    [ -n "$nv_name" ] || nv_name=$(pci_name "$1") || nv_name=""
    [ -n "$nv_name" ] && add_str gpu_name "$nv_name"

    [[ $nv_busy =~ ^[0-9]+$ ]] && add gpu_pct "$nv_busy"
    [[ $nv_temp =~ ^[0-9]+$ ]] && [ "$nv_temp" -gt 0 ] && add gpu_temp "$((nv_temp * 1000))"
    if [[ $nv_vused =~ ^[0-9]+$ ]] && [[ $nv_vtotal =~ ^[0-9]+$ ]] && [ "$nv_vtotal" -gt 0 ]; then
        add vram_used "$((nv_vused * 1024 * 1024))"
        add vram_total "$((nv_vtotal * 1024 * 1024))"
    fi
    # Watts with a fraction, to microwatts, without forking awk for it.
    if [[ $nv_power =~ ^([0-9]+)(\.([0-9]+))?$ ]]; then
        frac="${BASH_REMATCH[3]}000000"
        gpu_power=$(( BASH_REMATCH[1] * 1000000 + 10#${frac:0:6} ))
    fi
}

# --- CPU package power (RAPL) -----------------------------------------------
# coretemp and k10temp report temperature only. Package power on both Intel and
# AMD (Zen) comes from RAPL under /sys/class/powercap, whose top-level
# intel-rapl:N domains are the packages (the name is historical; AMD's are
# called that too). RAPL is an energy *counter* in microjoules, so a power
# reading is a delta between two samples. The last sample is kept under
# XDG_RUNTIME_DIR, and the menu's two-second poll differences against it; with
# no usable previous sample -- the first run, the menu having been shut long
# enough that an average over the gap says nothing about now -- the script takes
# a quarter-second one of its own.
#
# energy_uj is root-only by default (CVE-2020-8694: fine-grained energy is a
# side channel). udev/70-rapl-energy.rules lets wheel read it; without that rule
# the domains are unreadable, nothing is printed and the row is dropped.

# Readable package domains, one path per line.
rapl_domains() {
    local d
    for d in /sys/class/powercap/intel-rapl:*; do
        [[ ${d##*/} =~ ^intel-rapl:[0-9]+$ ]] || continue
        [[ $(cat "$d/name" 2>/dev/null) == package-* ]] || continue
        [ -r "$d/energy_uj" ] && echo "$d"
    done
}

# "<microseconds> <energy_uj per domain...>" for the domains given.
rapl_sample() {
    local d e out=${EPOCHREALTIME//[.,]/}
    for d in "$@"; do
        e=$(<"$d/energy_uj") || return 1
        out+=" $e"
    done
    echo "$out"
}

rapl_power() {
    local state="${XDG_RUNTIME_DIR:-/tmp}/system-stats-rapl.$UID"
    local -a doms=() prev=() cur=()
    local dt=0 i d range total=0
    mapfile -t doms < <(rapl_domains)
    [ "${#doms[@]}" -gt 0 ] || return 1

    read -ra cur <<< "$(rapl_sample "${doms[@]}")" || return 1
    [ -r "$state" ] && read -ra prev < "$state"
    [ "${#prev[@]}" -eq "${#cur[@]}" ] && dt=$(( cur[0] - prev[0] ))
    if [ "$dt" -lt 200000 ] || [ "$dt" -gt 10000000 ]; then
        prev=("${cur[@]}")
        sleep 0.25
        read -ra cur <<< "$(rapl_sample "${doms[@]}")" || return 1
        dt=$(( cur[0] - prev[0] ))
    fi
    echo "${cur[*]}" > "$state" 2>/dev/null
    [ "$dt" -gt 0 ] || return 1

    for i in "${!doms[@]}"; do
        d=$(( cur[i + 1] - prev[i + 1] ))
        # The counter wraps at max_energy_range_uj (about 262 kJ here, so every
        # hour or so under load).
        if [ "$d" -lt 0 ]; then
            range=$(read_num "${doms[i]}/max_energy_range_uj") || return 1
            d=$(( d + range ))
        fi
        total=$(( total + d ))
    done
    # uJ per us is watts, so uJ * 1e6 per us is microwatts.
    echo $(( total * 1000000 / dt ))
}

read_num() { [ -r "$1" ] && cat "$1" 2>/dev/null; }

# --- collection -------------------------------------------------------------

json=""
add() { json+="${json:+,}\"$1\":$2"; }
# A string value, with the two characters JSON cannot take raw escaped.
add_str() { local v=${2//\\/\\\\}; v=${v//\"/\\\"}; add "$1" "\"$v\""; }

# CPU model, from the first core's entry. An ARM kernel has no "model name", so
# there the name is simply omitted.
while IFS=':' read -r key value; do
    [[ $key == "model name"* ]] && { add_str cpu_name "${value# }"; break; }
done < /proc/cpuinfo

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
gpu=$(gpu_device) || gpu=""
if [ -n "$gpu" ] && [ "$(cat "$gpu/vendor")" = 0x10de ] && command -v nvidia-smi >/dev/null 2>&1; then
    nvidia_stats "${gpu##*/}"
elif [ -n "$gpu" ]; then
    # amdgpu, Intel Arc, and nouveau (an NVIDIA card without nvidia-smi).
    name=$(pci_name "${gpu##*/}") && add_str gpu_name "$name"
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
[ -n "$gpu_power" ] && add gpu_power_uw "$gpu_power"

# CPU: Intel's coretemp calls it "Package id 0", AMD's k10temp calls it "Tctl".
# zenpower reports power itself; everything else falls through to RAPL.
if cpu_hwmon=$(hwmon_by_name coretemp k10temp zenpower amd_energy); then
    t=$(temp_input_by_label "$cpu_hwmon" '^(Package id 0|Tctl|Tdie)$') \
        && t=$(read_num "$t") && [ -n "$t" ] && add cpu_temp "$t"
    p=$(power_input "$cpu_hwmon") && [ -n "$p" ] && [ "$p" -gt 0 ] && cpu_power=$p
fi
[ -n "$cpu_power" ] || cpu_power=$(rapl_power) || cpu_power=""
[ -n "$cpu_power" ] && add cpu_power_uw "$cpu_power"

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
