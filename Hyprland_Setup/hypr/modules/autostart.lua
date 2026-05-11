 hl.on("hyprland.start", function () 
    hl.exec_once("waybar & awww-daemon & swaync & hypridle")
    hl.exec_once("wl-paste --type text --watch cliphist store")
    hl.exec_once("wl-paste --type image --watch cliphist store")
    hl.exec_once("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
 end)

