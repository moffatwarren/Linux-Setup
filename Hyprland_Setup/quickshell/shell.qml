// Quickshell port of the waybar config -- see CLAUDE.md at the repo root.
//
// Enable with `config.bar = "quickshell"` in hypr/modules/config.lua (the LIVE
// copy; that value is machine-local and preserved across install.sh runs).
//
// The tailscale / pia / weather modules reuse the existing waybar helper
// scripts in ~/.config/waybar/scripts/, so their logic lives in one place.

import Quickshell

ShellRoot {
    // One bar per connected monitor.
    Variants {
        model: Quickshell.screens

        Bar {}
    }
}
