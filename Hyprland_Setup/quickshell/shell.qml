// Quickshell bar -- see CLAUDE.md at the repo root.
//
// Enable with `config.bar = "quickshell"` in hypr/modules/config.lua (the LIVE
// copy; that value is machine-local and preserved across install.sh runs).
//
// The tailscale / pia / weather modules reuse the shell helper scripts in
// ~/.config/hypr/scripts/, so their logic lives in one place.

import Quickshell

ShellRoot {
    // One bar per connected monitor.
    Variants {
        model: Quickshell.screens

        Bar {}
    }
}
