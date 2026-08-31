local config = require("modules.config")
local bar = config.bar or "waybar"

 hl.on("hyprland.start", function ()
    hl.exec_cmd(bar .. " & awww-daemon & swaync & hypridle")
    hl.exec_cmd("wl-paste --type text --watch cliphist store")
    hl.exec_cmd("wl-paste --type image --watch cliphist store")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
 end)
