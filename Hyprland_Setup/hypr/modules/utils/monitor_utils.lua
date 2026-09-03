local config = require("modules.config")
local monitor_utils = {}

-- The laptop's built-in screen: finding it, turning it off, turning it on.
--
-- WHICH monitor that is is not configured. The kernel only ever names a panel
-- wired to the board eDP (every current laptop), LVDS (pre-2013) or DSI
-- (tablets, some ARM laptops), and never uses those for anything you can plug
-- in -- and Hyprland names monitors after the DRM connector they are on, so the
-- connector name answers it on any machine with nothing to set up. This
-- replaced `config.mainMonitor`, a hand-set name install.sh had to carry across
-- every deploy, and which was stale on the machine it came from: it said "DP-1"
-- where the monitor is DP-2, so the keybind had been pointing at a disconnected
-- connector with nothing to report it.
--
-- All of this is Lua rather than a script in hypr/scripts/, which is where the
-- rest of this repo puts work like it. Under a Lua config `hyprctl dispatch`
-- takes a Lua EXPRESSION, not a dispatcher name, and `hyprctl keyword` refuses
-- outright ("keyword can't work with non-legacy parsers"), so a shell script
-- cannot drive monitors here at all. hl.get_monitors()/hl.monitor() can, and
-- being in-process it is synchronous with no IPC round trip.

-- Where the kernel puts connector state. Probed by name rather than listed,
-- because Lua has no readdir and shelling out for one is not worth it. Two of
-- each is far past what any real machine has; the loop stops at the first hit.
local CARDS = { 0, 1, 2, 3 }
local PANEL_CONNECTORS = { "eDP-1", "eDP-2", "LVDS-1", "LVDS-2", "DSI-1", "DSI-2" }

-- The connected internal panel's name, or nil on a desktop. Not cached: a
-- reload is the only thing that would clear a cache anyway, and this is a
-- handful of io.open calls.
function monitor_utils.internal_panel()
	for _, connector in ipairs(PANEL_CONNECTORS) do
		for _, card in ipairs(CARDS) do
			local f = io.open("/sys/class/drm/card" .. card .. "-" .. connector .. "/status", "r")
			if f then
				local status = f:read("l")
				f:close()
				-- "connected" and not, say, a panel that has been unplugged in
				-- a machine that supports it.
				if status == "connected" then
					return connector
				end
			end
		end
	end
	return nil
end

-- hl.get_monitors() lists what Hyprland currently has ENABLED, so presence in
-- it is the on/off state. Read every time rather than tracked in a boolean,
-- which is what this used to do and which went stale the moment anything
-- changed a monitor by another route (a reload, a hotplug, hyprctl by hand).
local function enabled_monitors()
	local names = {}
	for _, m in ipairs(hl.get_monitors()) do
		names[#names + 1] = m.name
	end
	return names
end

local function panel_is_on(panel)
	for _, name in ipairs(enabled_monitors()) do
		if name == panel then
			return true
		end
	end
	return false
end

-- The screen a disabled panel's workspaces should land on: the first enabled
-- monitor that is not the panel. With several, any is as good as another.
local function external_monitor(panel)
	for _, name in ipairs(enabled_monitors()) do
		if name ~= panel then
			return name
		end
	end
	return nil
end

-- Hyprland relocates a disabled monitor's workspaces itself, but not
-- predictably to a monitor of our choosing, and "where did my windows go" is
-- the whole question when the lid shuts. Done explicitly and first, so the move
-- is the one thing that definitely happened before the output went away.
local function move_workspaces_off_panel(panel, target)
	for _, ws in ipairs(hl.get_workspaces()) do
		-- ws.monitor is a monitor object, not a name. Special workspaces have a
		-- negative id and are per-monitor overlays, so moving one is
		-- meaningless.
		if ws.id > 0 and ws.monitor and ws.monitor.name == panel then
			hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(ws.id), monitor = target }))
		end
	end
end

-- Turn the panel on. Deliberately NOT guarded on an external being present:
-- unplugging the external while the panel is off has to be recoverable, and
-- monitor.removed calls this for exactly that reason.
function monitor_utils.panel_on()
	local panel = monitor_utils.internal_panel()
	if not panel or panel_is_on(panel) then
		return
	end
	hl.monitor({ output = panel, mode = "highrr", position = "auto", scale = "1" })
end

-- Turn the panel off, but only ever while something else is showing. That is
-- the whole "laptop with an external screen attached" condition, and it is the
-- difference between a key that does nothing and a machine with every display
-- disabled and no way to see the shortcut that undoes it.
--
-- On the lid: with no external screen this does nothing, ON PURPOSE. Closing
-- the lid there is systemd-logind's business, and its DEFAULT handling is
-- already the rule we want -- HandleLidSwitch=suspend fires, except that logind
-- counts "more than one display connected" as docked and then applies
-- HandleLidSwitchDocked=, which defaults to `ignore`. So logind suspends
-- exactly when there is no external screen, and stands aside exactly when there
-- is, leaving that case to this function. Nothing to configure; install.sh's
-- check_lid_handling warns if a machine has been set up otherwise.
function monitor_utils.panel_off()
	local panel = monitor_utils.internal_panel()
	if not panel or not panel_is_on(panel) then
		return
	end
	local target = external_monitor(panel)
	if not target then
		return
	end
	move_workspaces_off_panel(panel, target)
	hl.monitor({ output = panel, disabled = true })
end

function monitor_utils.toggle_panel()
	local panel = monitor_utils.internal_panel()
	if not panel then
		return -- a desktop: nothing to toggle, and nothing worth saying so
	end
	if panel_is_on(panel) then
		monitor_utils.panel_off()
	else
		monitor_utils.panel_on()
	end
end

function monitor_utils.handle_new_monitor(monitor)
	if not monitor then
		return
	end
	-- Restart the bar so it draws on the monitor that just appeared. This was
	-- building a dispatcher and dropping it on the floor -- exec_cmd only
	-- describes the command, hl.dispatch is what runs it -- so hotplug had
	-- silently not restarted the bar at all. `;` rather than `&&`, which
	-- skipped the restart whenever killall found nothing to kill.
	local bar = config.bar or "quickshell"
	hl.dispatch(hl.dsp.exec_cmd("killall " .. bar .. "; setsid " .. bar .. " &"))
end

function monitor_utils.handle_remove_monitor(monitor)
	if not monitor then
		return
	end
	-- An external screen was unplugged. Bring the panel back if it is off, or
	-- this is a laptop with every display disabled and no way to see the
	-- shortcut that would undo it.
	monitor_utils.panel_on()
end

return monitor_utils
