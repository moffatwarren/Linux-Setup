local config = require("modules.config")
local monitor_utils = require("modules.utils.monitor_utils")
local workspace_utils = require("modules.utils.workspace_utils")

hl.bind(config.mainMod .. " + RETURN", hl.dsp.exec_cmd(config.terminal), { bypass = true })
hl.bind(config.mainMod .. " + Q", hl.dsp.window.close(), { bypass = true })
hl.bind(config.mainMod .. " + L", hl.dsp.exec_cmd("hyprlock"), { bypass = true })
hl.bind(config.mainMod .. " + SHIFT + L", hl.dsp.exec_cmd("hyprlock & sleep 0.5 && systemctl suspend"), { bypass = true })
hl.bind(config.mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }), { bypass = true })
hl.bind(config.mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "fullscreen" }), { bypass = true })
hl.bind(config.mainMod .. " + ALT + F", hl.dsp.window.float({ action = "toggle" }), { bypass = true })
hl.bind(config.mainMod .. " + P", hl.dsp.window.pin(), { bypass = true })
hl.bind(config.mainMod .. " + J", hl.dsp.layout("togglesplit")) -- dwindle only
-- App launcher, clipboard history, wallpaper picker and the keybind list are
-- all quickshell overlays living in the bar process (see
-- quickshell/OverlayPanel.qml), so the binds just poke their IPC handlers.
hl.bind(config.mainMod .. " + SPACE", hl.dsp.exec_cmd("qs ipc call launcher toggle"), { bypass = true })
-- The list quickshell/KeybindsHelp.qml draws is hand-written; anything added
-- or changed in this file has to be added there too.
hl.bind(config.mainMod .. " + K", hl.dsp.exec_cmd("qs ipc call keybinds toggle"), { bypass = true })
hl.bind(config.mainMod .. " + D", hl.dsp.exec_cmd("qs ipc call defaults toggle"), { bypass = true })
hl.bind(config.mainMod .. " + E", hl.dsp.exec_cmd("~/.config/hypr/scripts/launch-file-manager.sh"), { bypass = true })
hl.bind(config.mainMod .. " + B", hl.dsp.exec_cmd("~/.config/hypr/scripts/launch-browser.sh"), { bypass = true })
hl.bind(config.mainMod .. " + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | swappy -f -'), { bypass = true })
hl.bind(config.mainMod .. " + ALT + S", hl.dsp.exec_cmd('grim -g "$(slurp)" - | tesseract stdin stdout | wl-copy'), { bypass = true })
-- One key starts and stops a region recording; the bar grows a red pill with
-- the elapsed time while it runs (quickshell/RecorderPill.qml).
hl.bind(config.mainMod .. " + CTRL + S", hl.dsp.exec_cmd("~/.config/hypr/scripts/screen-record.sh --toggle"), { bypass = true })
hl.bind(config.mainMod .. " + O", hl.dsp.exec_cmd("~/.config/hypr/scripts/audio-output-toggle.sh"), { bypass = true })
hl.bind(config.mainMod .. " + W", hl.dsp.exec_cmd("qs ipc call wallpaper toggle"), { bypass = true })
hl.bind(config.mainMod .. " + SHIFT + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-random.sh"), { bypass = true })
hl.bind(config.mainMod .. " + V", hl.dsp.exec_cmd("qs ipc call clipboard toggle"), { bypass = true })
hl.bind(config.mainMod .. " + N", hl.dsp.exec_cmd("qs ipc call notifications toggle"), { bypass = true })
hl.bind(config.mainMod .. " + SHIFT + N", hl.dsp.exec_cmd("qs ipc call notifications dnd"), { bypass = true })
hl.bind(config.mainMod .. " + T", hl.dsp.exec_cmd(config.terminal .. " --class btop-float -e btop"), { bypass = true })
hl.bind(config.mainMod .. " + G", hl.dsp.exec_cmd('~/.config/hypr/scripts/launch-browser.sh --app="https://gemini.google.com/app"'),
	{ bypass = true })
hl.bind(config.mainMod .. " + Y", hl.dsp.exec_cmd('~/.config/hypr/scripts/launch-browser.sh --app="https://youtube.com"'),
	{ bypass = true })
-- Turns the laptop's built-in screen off/on. Which monitor that is comes from
-- the DRM connector name (monitor_utils.internal_panel); there is nothing to
-- configure. Does nothing on a desktop, or on a laptop with no external screen
-- attached -- see monitor_utils for why that guard is not optional.
hl.bind(config.mainMod .. " + SHIFT + Z", monitor_utils.toggle_panel, { locked = true })
-- Swaps which side the two monitors are on -- the right-hand one becomes the
-- left-hand one. Inert unless exactly two are enabled; see monitor_utils for
-- why two and not "the nearest pair". Not `locked`, unlike the panel toggle
-- above: that one has to work for a lid closing on a locked session, and
-- rearranging screens you cannot see is not a thing to do from a lock screen.
hl.bind(config.mainMod .. " + CTRL + Z", monitor_utils.swap_monitors)
-- Sends every window on the current workspace to an empty workspace on the
-- other monitor -- the next one to the right, wrapping round -- and leaves the
-- focus and the pointer on this screen. Inert with one enabled monitor, or on a
-- workspace with nothing on it. See monitor_utils.dump_to_other_monitor.
hl.bind(config.mainMod .. " + M", monitor_utils.dump_to_other_monitor)

-- Move window focus using arrow keys
hl.bind(config.mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(config.mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(config.mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(config.mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Move / swap window position in direction using mainMod + SHIFT + arrow keys
hl.bind(config.mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(config.mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(config.mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(config.mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }))

-- Resize active window using mainMod + CTRL + arrow keys
hl.bind(config.mainMod .. " + CTRL + left", hl.dsp.window.resize({ x = -25, y = 0, relative = true }), { repeating = true, bypass = true })
hl.bind(config.mainMod .. " + CTRL + right", hl.dsp.window.resize({ x = 25, y = 0, relative = true }), { repeating = true, bypass = true })
hl.bind(config.mainMod .. " + CTRL + up", hl.dsp.window.resize({ x = 0, y = -25, relative = true }), { repeating = true, bypass = true })
hl.bind(config.mainMod .. " + CTRL + down", hl.dsp.window.resize({ x = 0, y = 25, relative = true }), { repeating = true, bypass = true })

-- Workspaces 1-10 (Using a Lua loop to keep the config clean!)
--
-- Three keys per workspace, on one number row and over the same range, so there
-- is no number that means workspace 10 under one modifier and nothing under
-- another: go there, send the focused window there, send every window on this
-- workspace there. The CTRL one is workspace_utils.move_all_to, and unlike the
-- other two it takes the focus with the windows -- see that function for why.
--
-- `i` is a fresh local per iteration in Lua, so the closure below captures this
-- pass's number rather than the loop's final one.
for i = 1, 10 do
	local key = i % 10 -- 10 maps to key 0
	hl.bind(config.mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }), { bypass = true })
	hl.bind(config.mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }), { bypass = true })
	hl.bind(config.mainMod .. " + CTRL + " .. key, function()
		workspace_utils.move_all_to(i)
	end, { bypass = true })
end

hl.bind(config.mainMod .. " + SHIFT + mouse:272", hl.dsp.window.move({ monitor = "+1" }))

-- Scroll through existing workspaces with mouse scroll
hl.bind(config.mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { bypass = true })
hl.bind(config.mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { bypass = true })

-- Move/resize windows with main mod + mouse drag
hl.bind(config.mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(config.mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

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

-- Lid closed: blank the built-in panel and move its workspaces to the external
-- screen. Lid opened: bring it back. With NO external screen attached, closing
-- the lid does nothing here on purpose -- systemd-logind suspends the machine
-- instead, which is its default behaviour and the rule we want. See
-- monitor_utils.panel_off.
hl.bind("switch:on:Lid Switch", monitor_utils.panel_off, { locked = true })
hl.bind("switch:off:Lid Switch", monitor_utils.panel_on, { locked = true })

-- A new screen: rebuild the bars a moment later. quickshell's shell.qml is
-- `Variants { model: Quickshell.screens }`, so it does build a Bar for the new
-- monitor by itself -- but one built while the compositor is still settling the
-- output can come up with stale geometry, and the bar already on screen has
-- just had its workspaces rearranged under it. `qs ipc call bar refresh`
-- destroys and rebuilds every Bar against the settled layout.
--
-- This is NOT the old handler, which restarted quickshell outright
-- (`killall quickshell; setsid quickshell &`) and put two bars on the screen at
-- every login. This event ALSO fires for the monitors already connected when
-- Hyprland starts, ~70ms before "hyprland.start" runs autostart.lua -- so back
-- then killall found nothing to kill, setsid started a bar, and autostart
-- started a second. An IPC call into a bar that is not up yet is a no-op
-- ("Target not found", exit 0), so that same early event costs nothing now.
-- Rebuilding only the Variants also keeps the notification history, the audio
-- rotation and the five overlays, which a restart would throw away.
--
-- The sleep is why this is an exec_cmd rather than a direct call: the new
-- wl_output has to reach quickshell before a rebuild can include it, and
-- monitor.added fires before that. A second is cheap margin, and it runs in its
-- own process rather than on Hyprland's config thread.
hl.on("monitor.added", function()
	hl.dispatch(hl.dsp.exec_cmd("sleep 1; qs ipc call bar refresh"))
end)

hl.on("monitor.removed", monitor_utils.handle_remove_monitor)
