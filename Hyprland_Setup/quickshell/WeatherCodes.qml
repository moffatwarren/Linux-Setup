pragma Singleton

import Quickshell
import QtQuick

// The WMO weather codes Open-Meteo publishes, mapped to a nerd font glyph, a
// short label and a colour. A singleton because both halves of the weather
// module read it: the pill shows the current condition's glyph, and
// ForecastPopup shows one per day -- and they must never disagree.
Singleton {
    // WMO weather codes, as published by Open-Meteo. Glyphs are private-use
    // nerd font codepoints written as \u escapes -- pasting the character
    // itself silently yields an empty string.
    function condition(code) {
        switch (code) {
        case 0:  return { icon: "\ue30d", text: "Clear",         color: Theme.yellow };
        case 1:  return { icon: "\ue302", text: "Mainly clear",  color: Theme.yellow };
        case 2:  return { icon: "\ue302", text: "Partly cloudy", color: Theme.subtext1 };
        case 3:  return { icon: "\ue33d", text: "Overcast",      color: Theme.subtext0 };
        case 45: return { icon: "\ue313", text: "Fog",           color: Theme.overlay0 };
        case 48: return { icon: "\ue313", text: "Rime fog",      color: Theme.overlay0 };
        case 51: return { icon: "\ue319", text: "Light drizzle", color: Theme.sapphire };
        case 53: return { icon: "\ue319", text: "Drizzle",       color: Theme.sapphire };
        case 55: return { icon: "\ue319", text: "Heavy drizzle", color: Theme.sapphire };
        case 56: return { icon: "\ue31a", text: "Icy drizzle",   color: Theme.sky };
        case 57: return { icon: "\ue31a", text: "Icy drizzle",   color: Theme.sky };
        case 61: return { icon: "\ue318", text: "Light rain",    color: Theme.blue };
        case 63: return { icon: "\ue318", text: "Rain",          color: Theme.blue };
        case 65: return { icon: "\ue318", text: "Heavy rain",    color: Theme.blue };
        case 66: return { icon: "\ue31a", text: "Freezing rain", color: Theme.sky };
        case 67: return { icon: "\ue31a", text: "Freezing rain", color: Theme.sky };
        case 71: return { icon: "\ue35e", text: "Light snow",    color: Theme.sky };
        case 73: return { icon: "\ue35e", text: "Snow",          color: Theme.sky };
        case 75: return { icon: "\ue35e", text: "Heavy snow",    color: Theme.sky };
        case 77: return { icon: "\ue35e", text: "Snow grains",   color: Theme.sky };
        case 80: return { icon: "\ue316", text: "Light showers", color: Theme.blue };
        case 81: return { icon: "\ue316", text: "Showers",       color: Theme.blue };
        case 82: return { icon: "\ue316", text: "Heavy showers", color: Theme.blue };
        case 85: return { icon: "\ue35e", text: "Snow showers",  color: Theme.sky };
        case 86: return { icon: "\ue35e", text: "Snow showers",  color: Theme.sky };
        case 95: return { icon: "\ue31d", text: "Thunderstorm",  color: Theme.mauve };
        case 96: return { icon: "\ue31d", text: "Storm, hail",   color: Theme.mauve };
        case 99: return { icon: "\ue31d", text: "Storm, hail",   color: Theme.mauve };
        // An unmapped code is a condition with no glyph here, not a clear sky
        // -- say so rather than drawing a confident sun.
        default: return { icon: "\ue374", text: "Unknown",       color: Theme.overlay0 };
        }
    }
}
