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

    // The three full-screen overlays -- SUPER+W wallpaper picker, SUPER+SPACE
    // app launcher, SUPER+V clipboard history. They ride along in the bar
    // process rather than each being its own `qs -p` so that opening one is
    // instant: built once, in the background, then only shown and hidden.
    // They share their window with each other via OverlayPanel.qml.
    LazyLoader {
        id: wallpaperPicker
        loading: true

        WallpaperPicker {}
    }

    LazyLoader {
        id: appLauncher
        loading: true

        AppLauncher {}
    }

    LazyLoader {
        id: clipboardMenu
        loading: true

        ClipboardMenu {}
    }

    // `qs ipc call <target> toggle`, which is what the keybinds in
    // hypr/modules/binds.lua run. The bar is the only quickshell instance and
    // it uses the default config path, so `qs ipc call` finds it with no -c.
    //
    // Each overlay takes the keyboard exclusively while open, so opening one
    // closes the other two first -- two exclusive layer surfaces up at once
    // leaves the keystrokes going to whichever the compositor picked.
    IpcHandler {
        target: "wallpaper"

        function toggle(): void { closeOverlays("wallpaper"); wallpaperPicker.item?.toggle(); }
        function open(): void { closeOverlays("wallpaper"); wallpaperPicker.item?.show(); }
        function close(): void { wallpaperPicker.item?.close(); }
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void { closeOverlays("launcher"); appLauncher.item?.toggle(); }
        function open(): void { closeOverlays("launcher"); appLauncher.item?.show(); }
        function close(): void { appLauncher.item?.close(); }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void { closeOverlays("clipboard"); clipboardMenu.item?.toggle(); }
        function open(): void { closeOverlays("clipboard"); clipboardMenu.item?.show(); }
        function close(): void { clipboardMenu.item?.close(); }
    }

    function closeOverlays(except: string): void {
        if (except !== "wallpaper") wallpaperPicker.item?.close();
        if (except !== "launcher") appLauncher.item?.close();
        if (except !== "clipboard") clipboardMenu.item?.close();
    }
}
