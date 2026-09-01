local config = require("modules.config")
local bar = config.bar or "quickshell"

 hl.on("hyprland.start", function ()
    -- No notification daemon here: quickshell is the notification server
    -- itself now (quickshell/NotificationService.qml), so starting swaync
    -- as well would leave the two fighting over
    -- org.freedesktop.Notifications.
    hl.exec_cmd(bar .. " & awww-daemon & hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
 end)
