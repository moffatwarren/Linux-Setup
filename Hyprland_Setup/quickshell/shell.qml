// Quickshell bar -- see CLAUDE.md at the repo root.
//
// Enable with `config.bar = "quickshell"` in hypr/modules/config.lua (the LIVE
// copy; that value is machine-local and preserved across install.sh runs).
//
// The tailscale / pia / weather modules reuse the shell helper scripts in
// ~/.config/hypr/scripts/, so their logic lives in one place.

import Quickshell
import Quickshell.Io

ShellRoot {
    // One bar per connected monitor.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // The SUPER+W wallpaper picker. It rides along in the bar process rather
    // than being its own `qs -p` so that opening it is instant -- built once,
    // in the background, and then only shown and hidden.
    LazyLoader {
        id: wallpaperPicker
        loading: true

        WallpaperPicker {}
    }

    // `qs ipc call wallpaper toggle`, which is what the keybind in
    // hypr/modules/binds.lua runs. The bar is the only quickshell instance and
    // it uses the default config path, so `qs ipc call` finds it with no -c.
    IpcHandler {
        target: "wallpaper"

        function toggle(): void { wallpaperPicker.item?.toggle(); }
        function open(): void { wallpaperPicker.item?.show(); }
        function close(): void { wallpaperPicker.item?.close(); }
    }
}
