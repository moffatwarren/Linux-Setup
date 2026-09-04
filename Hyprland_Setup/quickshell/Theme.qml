pragma Singleton

import Quickshell
import QtQuick

// Catppuccin Mocha -- mirrors waybar/mocha.css so both bars look identical.
Singleton {
    readonly property string rosewater: "#f5e0dc"
    readonly property string flamingo:  "#f2cdcd"
    readonly property string pink:      "#f5c2e7"
    readonly property string mauve:     "#cba6f7"
    readonly property string red:       "#f38ba8"
    readonly property string maroon:    "#eba0ac"
    readonly property string peach:     "#fab387"
    readonly property string yellow:    "#f9e2af"
    readonly property string green:     "#a6e3a1"
    readonly property string teal:      "#94e2d5"
    readonly property string sky:       "#89dceb"
    readonly property string sapphire:  "#74c7ec"
    readonly property string blue:      "#89b4fa"
    readonly property string lavender:  "#b4befe"
    readonly property string text:      "#cdd6f4"
    readonly property string subtext1:  "#bac2de"
    readonly property string subtext0:  "#a6adc8"
    readonly property string overlay0:  "#6c7086"
    readonly property string surface2:  "#585b70"
    readonly property string surface1:  "#45475a"
    readonly property string surface0:  "#313244"
    readonly property string base:      "#1e1e2e"
    readonly property string mantle:    "#181825"
    readonly property string crust:     "#11111b"

    // The bar's one surface colour: `Bar.qml` paints its whole slab with this
    // too, so a pill is indistinguishable from the strip behind it. `base`
    // matches the popup frames (ListPopup, CalendarPopup, ForecastPopup and the
    // menus all draw `Theme.base` inside a surface1 border), so a hover panel
    // reads as an extension of the bar rather than a separate surface.
    readonly property color pill: base

    readonly property string fontFamily: "JetBrainsMono Nerd Font"
    readonly property int fontSize: 12
    readonly property int pillHeight: 22
    // The bar slab's corner radius (Bar.qml). height/2 would be a full capsule;
    // keep it in step with decoration.rounding in hypr/modules/look.lua.
    readonly property int barRadius: 8
    readonly property int pillPad: 12

    // Every drop-down hangs off the bottom edge of the slab, so it carries the
    // slab's own radius on the two corners that are still corners -- MenuPopup
    // squares the top pair off. These were the literals 12 / 1 / 10 repeated in
    // all thirteen popup files.
    readonly property int popupRadius: barRadius
    readonly property int borderWidth: 1
    readonly property int popupPad: 10
}
