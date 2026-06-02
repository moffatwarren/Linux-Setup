package.path = package.path .. ";/home/warren/.config/hypr/modules/?.lua"
local wallpaper_utils = require("utils.wallpaper_utils")
local monitor_utils = require("utils.monitor_utils")

local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "thunar"
local menu = "rofi -show drun"
local browser = "google-chrome-stable"

hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { bypass = true })
hl.bind(mainMod .. " + Q", hl.dsp.window.close(), { bypass = true })
hl.bind(mainMod .. " + M", hl.dsp.exit(), { bypass = true })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("killall waybar && waybar &"), { bypass = true })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"), { bypass = true })
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("hyprlock & sleep 0.5 && systemctl suspend"), { bypass = true })
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { bypass = true })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }), { bypass = true })
hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.window.float({ action = "toggle" }), { bypass = true })
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu), { bypass = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { bypass = true })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser), { bypass = true })
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { bypass = true })
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("~/.config/waybar/scripts/audio-output-toggle.sh"), { bypass = true })
--hl.bind(mainMod .. " + W", wallpaper_utils.select, { bypass = true })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-selector.sh"), { bypass = true })
hl.bind(mainMod .. " + SHIFT + W", wallpaper_utils.set_random, { bypass = true })
hl.bind(
	mainMod .. " + V",
	hl.dsp.exec_cmd("cliphist list | rofi -dmenu -display-columns 2 | cliphist decode | wl-copy"),
	{ bypass = true }
)
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal .. " --class btop-float -e btop"), { bypass = true })
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(browser .. ' --app="https://gemini.google.com/app"'), { bypass = true })
hl.bind(mainMod .. " + SHIFT + Z", monitor_utils.turn_off_monitor, { locked = true })
hl.bind(mainMod .. " + SHIFT + X", monitor_utils.turn_on_monitor, { locked = true })

-- Move window focus using arrow keys
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Workspaces 1-9 (Using a Lua loop to keep the config clean!)
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { bypass = true })
	hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { bypass = true })
end

hl.bind(mainMod .. " + SHIFT + mouse:272", hl.dsp.window.move({ monitor = "+1" }))

-- Scroll through existing workspaces with mouse scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e-1" }), { bypass = true })
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e+1" }), { bypass = true })

-- Move/resize windows with main mod + mouse drag
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Media & Volume Controls (Using the options table for repeat behavior)
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh up"),
	{ bypass = true, repeating = true, locked = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh down"),
	{ bypass = true, repeating = true, locked = true }
)
hl.bind(
	"XF86AudioMute",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh mute"),
	{ bypass = true, locked = true }
)
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-notify.sh up"),
	{ bypass = true, repeating = true, locked = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-notify.sh down"),
	{ bypass = true, repeating = true, locked = true }
)
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { bypass = true, locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { bypass = true, locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { bypass = true, locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { bypass = true, locked = true })

hl.bind("switch:on:Lid Switch", monitor_utils.turn_off_monitor, { locked = true })
hl.bind("switch:off:Lid Switch", monitor_utils.turn_on_monitor, { locked = true })

hl.on("monitor.added", monitor_utils.handle_new_monitor)
hl.on("monitor.removed", monitor_utils.handle_remove_monitor)