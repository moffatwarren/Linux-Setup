local config = require("modules.config")
local monitor_utils = {}

-- Which monitor is the laptop's built-in panel is worked out from the DRM
-- connector name, not configured -- see hypr/scripts/monitor-toggle.sh, which
-- is the whole of that logic. `config.mainMonitor` used to live here and had to
-- be hand-set per machine and preserved by install.sh across every deploy.
--
-- The work is in a script rather than in Lua for two reasons: enumerating
-- monitors needs `hyprctl`, and calling that from inside a Lua event handler
-- would be Hyprland talking to its own IPC socket on its own thread; and Lua
-- has no way to list a directory without shelling out anyway.
local TOGGLE = "~/.config/hypr/scripts/monitor-toggle.sh"

function monitor_utils.handle_new_monitor(monitor)
	if not monitor then
		return
	end
	-- Restart the bar so it draws on the monitor that just appeared. This was
	-- building a dispatcher and dropping it on the floor -- exec_cmd only
	-- describes the command, hl.dispatch is what runs it -- so hotplug had
	-- silently not restarted the bar at all. `;` rather than `&&`, which skipped
	-- the restart entirely whenever killall found nothing to kill.
	local bar = config.bar or "quickshell"
	hl.dispatch(hl.dsp.exec_cmd("killall " .. bar .. "; setsid " .. bar .. " &"))
end

function monitor_utils.handle_remove_monitor(monitor)
	if not monitor then
		return
	end
	-- An external screen was unplugged. Bring the built-in panel back if it is
	-- off, or this is a laptop with every display disabled and no way to see
	-- the shortcut that would undo it. `--on` never turns anything off, so
	-- this is safe to fire on any removal, including the panel's own.
	hl.dispatch(hl.dsp.exec_cmd(TOGGLE .. " --on"))
end

return monitor_utils
