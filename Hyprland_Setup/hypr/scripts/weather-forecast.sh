#!/usr/bin/env bash
# Current conditions plus a seven-day forecast for the quickshell weather
# module -- both the pill and its hover panel.
#
# Everything comes from Open-Meteo (free, no API key), which publishes a WMO
# condition code the bar can map to an icon. wttr.in, which used to drive the
# pill, only publishes three days and exposes no condition code at all in its
# one-line format, so the pill and the panel could not have agreed on an icon.
# The location still comes from wttr.in, so only one service does the IP
# geolocation.
#
# Prints raw numbers -- WMO condition code, temperature, min/max, precipitation
# chance -- and leaves every bit of formatting to the QML, the way
# system-stats.sh does. On any failure it prints nothing, so the module keeps
# its last good reading rather than showing a confidently wrong one.
#
# --force ignores the forecast cache's age, for the panel's double-click-to-
# refresh. The location cache is left alone: it is a week old at worst, it
# costs two extra requests to rebuild, and where you are is not what you are
# asking to re-check.

set -uo pipefail

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
LOC_CACHE="$CACHE_DIR/weather-location.json"
FORECAST_CACHE="$CACHE_DIR/weather-forecast.json"

# The bar polls this on the pill's own refresh interval and reuses the same
# answer for the hover panel, so it is cached: the weather for ten minutes
# (Open-Meteo updates about every fifteen), the location for a week.
LOC_MAX_AGE=$((7 * 24 * 3600))
FORECAST_MAX_AGE=$((10 * 60))

case "${1:-}" in
    --force) FORECAST_MAX_AGE=0 ;;   # fresh() compares age -lt 0, never true
esac

fresh() {
    local file=$1 max_age=$2 age
    [ -s "$file" ] || return 1
    age=$(( $(date +%s) - $(stat -c %Y "$file" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$max_age" ]
}

# Latitude, longitude, a place name and which temperature unit wttr.in uses
# here -- so the panel reads in the same unit as the pill above it. wttr.in
# picks the unit from the location (°F in the US, °C elsewhere) and exposes it
# nowhere in its JSON, hence the second, tiny request.
refresh_location() {
    fresh "$LOC_CACHE" "$LOC_MAX_AGE" && return 0

    local j1 unit
    j1=$(curl -s --max-time 15 'https://wttr.in/?format=j1') || return 1
    [ -n "$j1" ] || return 1

    unit=F
    case "$(curl -s --max-time 10 'https://wttr.in/?format=%t')" in
        *C*) unit=C ;;
    esac

    mkdir -p "$CACHE_DIR"
    jq -e --arg unit "$unit" '
        .nearest_area[0] as $a
        | {
            lat:   ($a.latitude  | tonumber),
            lon:   ($a.longitude | tonumber),
            place: ([$a.areaName[0].value, $a.region[0].value]
                    | map(select(. != null and . != "")) | join(", ")),
            unit:  $unit
          }
    ' <<<"$j1" >"$LOC_CACHE.tmp" 2>/dev/null || { rm -f "$LOC_CACHE.tmp"; return 1; }

    mv "$LOC_CACHE.tmp" "$LOC_CACHE"
}

refresh_forecast() {
    fresh "$FORECAST_CACHE" "$FORECAST_MAX_AGE" && return 0
    [ -s "$LOC_CACHE" ] || return 1

    local lat lon place unit temp_unit url daily
    lat=$(jq -r '.lat'   "$LOC_CACHE") || return 1
    lon=$(jq -r '.lon'   "$LOC_CACHE") || return 1
    place=$(jq -r '.place' "$LOC_CACHE") || return 1
    unit=$(jq -r '.unit'  "$LOC_CACHE") || return 1

    temp_unit=celsius
    [ "$unit" = F ] && temp_unit=fahrenheit

    url="https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon"
    url+="&current=weather_code,temperature_2m"
    url+="&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"
    url+="&temperature_unit=$temp_unit&timezone=auto&forecast_days=7"

    daily=$(curl -s --max-time 15 "$url") || return 1
    [ -n "$daily" ] || return 1

    mkdir -p "$CACHE_DIR"
    # Transpose Open-Meteo's parallel arrays into one row per day. A day
    # missing a reading keeps the row and drops the field, so the QML can omit
    # that column instead of printing a zero it was never told.
    jq -e --arg place "$place" --arg unit "$unit" '
        .daily as $d
        | {
            place: $place,
            unit:  $unit,
            current: ({ code: .current.weather_code, temp: .current.temperature_2m }
                      | with_entries(select(.value != null))),
            days: [ range(0; ($d.time | length)) as $i | {
                      date: $d.time[$i],
                      code: $d.weather_code[$i],
                      max:  $d.temperature_2m_max[$i],
                      min:  $d.temperature_2m_min[$i],
                      pop:  $d.precipitation_probability_max[$i]
                    } | with_entries(select(.value != null)) ]
          }
        | select((.days | length) > 0)
    ' <<<"$daily" >"$FORECAST_CACHE.tmp" 2>/dev/null || { rm -f "$FORECAST_CACHE.tmp"; return 1; }

    mv "$FORECAST_CACHE.tmp" "$FORECAST_CACHE"
}

refresh_location
refresh_forecast

# A stale cache still beats an empty panel when the network is down -- hence
# `updated`, the cache file's mtime: it is when the data was actually fetched,
# not when it was read, so a panel opened after a failed refresh says so. It
# comes from the file rather than from the QML so it survives a bar restart.
if [ -s "$FORECAST_CACHE" ]; then
    updated=$(stat -c %Y "$FORECAST_CACHE" 2>/dev/null || echo 0)
    jq -c --argjson updated "$updated" '. + { updated: $updated }' \
        "$FORECAST_CACHE" 2>/dev/null || cat "$FORECAST_CACHE"
fi
exit 0
