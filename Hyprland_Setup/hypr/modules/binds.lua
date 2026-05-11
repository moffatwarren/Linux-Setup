local mainMod = "SUPER"
local terminal = "kitty"
local fileManager = "thunar"
local menu = "rofi --show drun"
local browser = "google-chrome-stable"


hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal), { bypass = true })
hl.bind(mainMod .. " + Q", hl.dsp.killactive(), { bypass = true })
hl.bind(mainMod .. " M", hl.dsp.exit(), { bypass = true })
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/launch-waybar.sh"), { bypass = true })
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"), { bypass = true })
hl.bind(mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("hyprlock & sleep 0.5 && systemctl suspend"), { bypass = true })
hl.bind(mainMod .. " + F", hl.dsp.fullscreen(2), { bypass = true })
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.fullscreen(1), { bypass = true })
hl.bind(mainMod .. " + ALT + SPACE", hl.dsp.togglefloating(), { bypass = true })
hl.bind(mainMod .. " + J", hl.dsp.togglesplit()) -- dwindle
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd(menu), { bypass = true })
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager), { bypass = true })
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser), { bypass = true })
hl.bind(mainMod .. " + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { bypass = true })
hl.bind(mainMod .. " + O", hl.dsp.exec_cmd("~/.config/waybar/scripts/audio-output-toggle.sh"), { bypass = true })
hl.bind(mainMod .. " + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-selector.sh"), { bypass = true })
hl.bind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-random.sh"), { bypass = true })
hl.bind(
	mainMod .. " + V",
	hl.dsp.exec_cmd("cliphist list | rofi -dmenu -display-columns 2 | cliphist decode | wl-copy"),
	{ bypass = true }
)
hl.bind(mainMod .. " + T", hl.dsp.exec_cmd(terminal .. " --class btop-float -e btop"), { bypass = true })
hl.bind(mainMod .. " + G", hl.dsp.exec_cmd(browser .. ' --app="https://gemini.google.com/app"'), { bypass = true })

-- Move window focus using arrow keys
hl.bind(mainMod .. " + left", hl.dsp.movefocus("l"))
hl.bind(mainMod .. " + right", hl.dsp.movefocus("r"))
hl.bind(mainMod .. " + up", hl.dsp.movefocus("u"))
hl.bind(mainMod .. " + down", hl.dsp.movefocus("d"))

-- Workspaces 1-9 (Using a Lua loop to keep the config clean!)
for i = 1, 9 do
	-- Switch to workspace
	hl.bind(mainMod .. " + " .. tostring(i), hl.dsp.workspace(tostring(i)), { bypass = true })
	-- Move active window to workspace
	hl.bind(mainMod .. " + SHIFT + " .. tostring(i), hl.dsp.movetoworkspace(tostring(i)), { bypass = true })
end

-- Scroll through existing workspaces with mouse scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.workspace("e+1"), { bypass = true })
hl.bind(mainMod .. " + mouse_up", hl.dsp.workspace("e-1"), { bypass = true })

-- Move/resize windows with main mod + mouse drag
hl.bind(mainMod .. " + mouse:272", hl.dsp.movewindow())
hl.bind(mainMod .. " + mouse:273", hl.dsp.resizewindow())

-- Media & Volume Controls (Using the options table for repeat behavior)
hl.bind(
	"XF86AudioRaiseVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh up"),
	{ bypass = true, repeating = true }
)
hl.bind(
	"XF86AudioLowerVolume",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh down"),
	{ bypass = true, repeating = true }
)
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("~/.config/hypr/scripts/volume-notify.sh mute"), { bypass = true })
hl.bind(
	"XF86MonBrightnessUp",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-notify.sh up"),
	{ bypass = true, repeating = true }
)
hl.bind(
	"XF86MonBrightnessDown",
	hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-notify.sh down"),
	{ bypass = true, repeating = true }
)
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { bypass = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { bypass = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { bypass = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { bypass = true })