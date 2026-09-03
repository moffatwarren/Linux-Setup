// Quickshell bar -- see CLAUDE.md at the repo root.
//
// Enable with `config.bar = "quickshell"` in hypr/modules/config.lua (the LIVE
// copy; that value is machine-local and preserved across install.sh runs).
//
// The tailscale / pia / weather modules reuse the shell helper scripts in
// ~/.config/hypr/scripts/, so their logic lives in one place.

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

ShellRoot {
    // One bar per connected monitor.
    Variants {
        model: Quickshell.screens

        Bar {}
    }

    // The notification popups. Quickshell is the notification daemon now (see
    // NotificationService.qml) -- swaync is gone, so if this is not here nothing
    // draws a notification at all, volume and brightness OSDs included.
    // Deliberately NOT a Variants over screens: it follows the focused monitor
    // by itself, and one window per screen would pop every notification twice.
    NotificationToasts {}

    // Low-battery warnings. Instantiated here, once, rather than inside
    // BatteryPill: there is one Bar per monitor, so a per-monitor watcher would
    // raise every warning twice on a two-screen machine.
    BatteryWatcher {}

    // The four full-screen overlays -- SUPER+W wallpaper picker, SUPER+SPACE
    // app launcher, SUPER+V clipboard history, SUPER+K keybind list. They ride
    // along in the bar process rather than each being its own `qs -p` so that
    // opening one is instant: built once, in the background, then only shown
    // and hidden. They share their window with each other via OverlayPanel.qml.
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

    LazyLoader {
        id: keybindsHelp
        loading: true

        KeybindsHelp {}
    }

    // `qs ipc call <target> toggle`, which is what the keybinds in
    // hypr/modules/binds.lua run. The bar is the only quickshell instance and
    // it uses the default config path, so `qs ipc call` finds it with no -c.
    //
    // Each overlay takes the keyboard exclusively while open, so opening one
    // closes the others first -- two exclusive layer surfaces up at once
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

    IpcHandler {
        target: "keybinds"

        function toggle(): void { closeOverlays("keybinds"); keybindsHelp.item?.toggle(); }
        function open(): void { closeOverlays("keybinds"); keybindsHelp.item?.show(); }
        function close(): void { keybindsHelp.item?.close(); }
    }

    // SUPER+N, in place of `swaync-client -t`. The menu belongs to a bar module
    // rather than to a window of its own, so this opens the one on the monitor
    // you are actually looking at; NotificationService.menuMonitor is what keeps
    // the other monitors' copies shut.
    IpcHandler {
        target: "notifications"

        function toggle(): void {
            const monitor = Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name) : "";
            // Only clear the overlays on the way OPEN. closeOverlays() also
            // shuts this menu, so calling it first unconditionally would make
            // every press re-open the menu it had just closed.
            if (NotificationService.menuMonitor !== monitor) closeOverlays("");
            NotificationService.toggleMenu(monitor);
        }

        function close(): void { NotificationService.closeMenu(); }
        function dnd(): void { NotificationService.toggleDnd(); }
        function clear(): void { NotificationService.clearAll(); }
    }

    // The screen recorder (SUPER+CTRL+S) writes a state file and then calls
    // this, so the bar picks the change up on the event rather than by polling
    // the script. `stop` is here so the recording can be ended from a script or
    // a bind as well as by clicking the pill.
    IpcHandler {
        target: "recorder"

        function refresh(): void { RecorderService.reload(); }
        function toggle(): void { RecorderService.toggle(); }
        function stop(): void { RecorderService.stop(); }
    }

    function closeOverlays(except: string): void {
        if (except !== "wallpaper") wallpaperPicker.item?.close();
        if (except !== "launcher") appLauncher.item?.close();
        if (except !== "clipboard") clipboardMenu.item?.close();
        if (except !== "keybinds") keybindsHelp.item?.close();
        // The notification menu grabs the keyboard too, so it has to go the same
        // way -- an overlay opened over it would be typing into a dead surface.
        NotificationService.closeMenu();
    }
}
