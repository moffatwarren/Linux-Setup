local config = require("modules.config")
local workspace_utils = require("modules.utils.workspace_utils")

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
--
-- COLLECT FIRST, DISPATCH SECOND. Moving a workspace destroys and recreates
-- workspace objects, which leaves every OTHER handle in an already-fetched
-- list dangling -- and a dangling handle does not error, it reads every field
-- as nil. So the obvious single loop crashed on the SECOND eligible workspace:
-- `ws.id > 0` compiles to `0 < ws.id`, so a nil id raises "attempt to compare
-- number with nil" and the whole of panel_off dies BEFORE it disables
-- anything. Measured: with three workspaces on the panel, moving the first
-- made the third's captured handle report `id = nil`.
local function move_workspaces_off_panel(panel, target)
	local ids = {}
	for _, ws in ipairs(hl.get_workspaces()) do
		-- ws.monitor is a monitor object, not a name. Special workspaces have a
		-- negative id and are per-monitor overlays, so moving one is
		-- meaningless. The `ws.id and` guard is the dangling-handle case above.
		if ws.id and ws.id > 0 and ws.monitor and ws.monitor.name == panel then
			ids[#ids + 1] = ws.id
		end
	end
	for _, id in ipairs(ids) do
		hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = target }))
	end
end

-- Hyprland re-lays-out the remaining monitors when one goes away -- an external
-- at x=1920 slides to x=0 once the panel at x=0 is disabled -- but it does NOT
-- carry their LAYER SURFACES across with them. Measured with the panel off and
-- one 2560x1440 external, via `hyprctl layers`:
--
--   Monitor DP-2 (hyprctl monitors says x=0)
--     awww-daemon  xywh: 1920 0 2560 1440   <- x should be 0
--     quickshell   xywh: 1925 2 2550 30     <- x should be 5
--
-- Right size, wrong place: the bar and the wallpaper are drawn one screen-width
-- to the right of the screen they belong to, so the bar is a stub against the
-- right edge and most of the wallpaper is off the side. That is the whole of
-- "the wallpaper and the bar are not centered on the external monitor", and
-- neither program is at fault -- the surfaces are exactly where Hyprland put
-- them. Only the REMOVAL direction is affected: verified that bringing the
-- panel back moves the external's layers with it correctly, because a monitor
-- being added runs a full re-layout and one going away does not.
--
-- Writing a monitor's CURRENT position explicitly is what re-applies the rule
-- and drags its layer surfaces back onto it. A write that does not CHANGE the
-- rule is short-circuited, so `position = "auto"` on a monitor whose rule is
-- already auto does nothing at all (measured -- the layers stayed at 1920), and
-- neither `transform` nor `hl.dsp.force_renderer_reload()` moves them either;
-- it has to be the position.
--
-- So the monitors that are staying are PINNED where they already are, and
-- pinned BEFORE the panel goes away rather than repaired afterwards. Pinning
-- first means nothing ever moves, which is the difference between preventing
-- the bug and chasing it: there is no window in which a surface is misplaced,
-- and no dependence on when Hyprland gets round to re-applying anything. An
-- earlier version wrote the position and then put the rule back to `auto` a
-- moment later to avoid leaving anything pinned, and that is exactly the
-- fragile shape to avoid -- issued back to back the two writes collapse into
-- one and the fix does not happen at all (measured: it only ever worked with
-- seconds between the writes, which a keypress does not have).
--
-- The pin costs nothing that matters. It is written to the position auto had
-- already chosen, so it changes no layout today, and it is a runtime rule
-- rather than a committed line, so `hyprctl reload` clears it. With the panel
-- off the remaining screen keeps its old origin rather than sliding to 0,0 --
-- a gap in the coordinate space to the left of it, which nothing can see.
--
-- MODE AND SCALE ARE RESTATED, and leaving them out is a trap worth the line.
-- modules/monitors.lua is a CATCH-ALL rule -- `output = ""`, config.monitorMode,
-- position auto, scale 1 -- and a monitor-SPECIFIC rule takes precedence over
-- it wholesale rather than merging with it. So a specific rule naming only a
-- position drops that monitor's scale to Hyprland's own auto scale, which for a
-- 1920x1080 laptop panel is 1.5. Measured exactly that way: one
-- `hl.monitor({ output = "eDP-1", mode = ... })` and the panel went from scale 1
-- to 1.5, its layer surfaces resizing to 1280x720 to match -- which looks like
-- the very bug this function exists to fix and is not one. Both fields are
-- therefore carried over from what the monitor currently has, so pinning the
-- position changes the position and nothing else.
--
-- Names, positions and scales are read into a plain table before any write, for
-- the reason move_workspaces_off_panel does the same: hl.monitor() re-lays-out,
-- and a handle from a list fetched beforehand can be left dangling.
local function pin_monitors(except)
	local mons = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.name and m.x and m.y and m.name ~= except then
			mons[#mons + 1] = {
				name = m.name,
				position = m.x .. "x" .. m.y,
				scale = tostring(m.scale),
			}
		end
	end
	for _, m in ipairs(mons) do
		hl.monitor({ output = m.name, mode = config.monitorMode, position = m.position, scale = m.scale })
	end
end

-- Turn the panel on. Deliberately NOT guarded on an external being present:
-- unplugging the external while the panel is off has to be recoverable, and
-- monitor.removed calls this for exactly that reason.
--
-- `disabled = false` is not redundant, and leaving it out is why SUPER+SHIFT+Z
-- turned the panel off and then could not turn it back on. hl.monitor() MERGES
-- its spec into the rule already stored for that output rather than replacing
-- it, so the `disabled = true` panel_off wrote stays in force for any later
-- call that does not say otherwise -- a mode, a position and a scale are
-- applied to a rule that is still disabled. Measured on 0.56.2 against a
-- headless output: after `hl.monitor({ output = o, disabled = true })`, a spec
-- of mode/position/scale WITHOUT this field returns `ok` and the output stays
-- gone; with it, the output comes back. The `ok` is the trap -- there is no
-- error anywhere to find, which is what made this look like a dead keybind.
--
-- `mode` is the one field still asserted here rather than recorded by
-- panel_off, and that is deliberate: config.monitorMode says how a mode is
-- picked at all, and re-deciding it is what we want on the way back regardless
-- of what the panel was left at. Position and scale are the opposite -- there
-- is no right answer to assert, only the one it had.
function monitor_utils.panel_on()
	local panel = monitor_utils.internal_panel()
	if not panel or panel_is_on(panel) then
		return
	end
	-- Only `disabled` is cleared. It must NOT restate position or scale: the
	-- merge that makes `disabled = false` necessary also means the position and
	-- scale panel_off wrote are still in the rule, so naming them again can only
	-- overwrite them with something worse. `position = "auto"` did exactly that
	-- -- "auto" means "place me right of everything already placed", so every
	-- restore appended the panel to the far right of the layout instead of
	-- putting it back. Measured: a panel at x=0 beside one external came back at
	-- x=3840, and each further toggle moved it further out, which is what a
	-- growing row of screens "that do not exist" actually was.
	hl.monitor({ output = panel, disabled = false, mode = config.monitorMode })
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
	-- Write the panel's CURRENT place into the rule on the way down, because a
	-- disabled monitor is not in hl.get_monitors() and nothing can read its
	-- position back afterwards. hl.monitor() merges, so this is what panel_on
	-- restores by saying nothing about either field. Read now, while the monitor
	-- is still enabled and the values are still true.
	-- Pin everything that is staying BEFORE the panel goes away, so Hyprland
	-- has no gap to close and no monitor moves out from under its own bar and
	-- wallpaper. See pin_monitors.
	pin_monitors(panel)
	local m = hl.get_monitor(panel)
	if m and m.x and m.y then
		hl.monitor({ output = panel, position = m.x .. "x" .. m.y, scale = tostring(m.scale), disabled = true })
	else
		hl.monitor({ output = panel, disabled = true })
	end
end

-- SUPER+CTRL+Z: swap which side the two monitors are on.
--
-- Does nothing unless EXACTLY two monitors are enabled. One monitor has no
-- other side to be on, and with three or more "swap the two of them" has no
-- meaning -- there is no pair to pick, and guessing one would move a screen the
-- key never mentioned. hl.get_monitors() lists what is enabled, so a laptop
-- with the panel switched off counts as one and the key is inert, which is the
-- same "read the state, never track it" rule the rest of this file follows.
--
-- NOT to be confused with hl.dsp.workspace.swap_monitors, which swaps the two
-- monitors' active WORKSPACES and leaves them physically where they are. This
-- moves the screens; the windows stay on the screen they were already on.
--
-- The geometry: the one that was on the right takes the leftmost x, and the one
-- that was on the left is placed immediately after it. The origin is whatever
-- the left edge already was rather than a hardcoded 0, so a pair that is not
-- flush against x=0 -- which is exactly what panel_off's pinning can leave
-- behind -- keeps its place instead of jumping to the origin.
--
-- WIDTH IS DIVIDED BY SCALE. Hyprland lays monitors out in LOGICAL pixels,
-- so a 2560px monitor at scale 1.25 occupies 2048 of the layout, and placing
-- the second monitor at the raw 2560 would leave a 512px hole between them.
-- m.size is the raw pixel size too, not the logical one, so there is nothing
-- to read that avoids the division.
--
-- Both monitors are written explicitly, and that is also what keeps their bar
-- and wallpaper with them: a monitor whose rule is re-applied gets its layer
-- surfaces repositioned, while one that merely gets MOVED as a side effect of
-- someone else's re-layout does not (see pin_monitors for the whole story).
-- Here both sides of the swap are named, so both re-apply.
--
-- `mode` and `scale` are restated for the reason pin_monitors restates them:
-- a monitor-specific rule overrides modules/monitors.lua's catch-all wholesale,
-- so a rule naming only a position would drop the monitor to Hyprland's auto
-- scale.
function monitor_utils.swap_monitors()
	local mons = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.name and m.x and m.y and m.width and m.scale and m.scale > 0 then
			mons[#mons + 1] = {
				name = m.name,
				x = m.x,
				y = m.y,
				width = math.floor(m.width / m.scale + 0.5),
				scale = tostring(m.scale),
			}
		end
	end
	if #mons ~= 2 then
		return
	end

	local left, right = mons[1], mons[2]
	if left.x > right.x then
		left, right = right, left
	end
	-- Stacked one above the other, not side by side: there is no left and right
	-- to exchange, so do nothing rather than invent a horizontal layout.
	if left.x == right.x then
		return
	end

	local origin = left.x
	hl.monitor({
		output = right.name,
		mode = config.monitorMode,
		position = origin .. "x" .. right.y,
		scale = right.scale,
	})
	hl.monitor({
		output = left.name,
		mode = config.monitorMode,
		position = (origin + right.width) .. "x" .. left.y,
		scale = left.scale,
	})
end

-- SUPER+M: send every window on the current workspace to an empty workspace on
-- the other monitor, leaving the keyboard focus and the pointer where they are.
--
-- Inert unless more than one monitor is ENABLED. hl.get_monitors() is that
-- list, so a laptop whose panel is off after SUPER+SHIFT+Z counts as one and
-- the key does nothing -- the same "read the state, never track it" rule the
-- rest of this file follows. Inert too on an empty workspace: there is nothing
-- to move, and every step below would still run.
--
-- "The other monitor" is the next one to the RIGHT, wrapping round from the
-- rightmost. With two that is simply the other one, which is the case this key
-- exists for; with three it is at least an order you can predict and repeat,
-- rather than whichever hl.get_monitors() happened to list first. Unlike
-- swap_monitors this does NOT refuse a third monitor -- "swap the two of them"
-- names no pair when there are three, where "send this lot next door" still
-- names something.
local function next_monitor(current)
	local mons = {}
	for _, m in ipairs(hl.get_monitors()) do
		if m.name and m.x then
			mons[#mons + 1] = { name = m.name, x = m.x }
		end
	end
	if #mons < 2 then
		return nil
	end
	table.sort(mons, function(a, b)
		return a.x < b.x
	end)
	for i, m in ipairs(mons) do
		if m.name == current then
			return mons[i % #mons + 1].name
		end
	end
	return nil
end

-- The workspace id to dump onto: the lowest that is free. A workspace holding
-- windows is obviously not free, and neither is an EMPTY one that some monitor
-- is currently displaying -- an empty workspace exists at all only while it is
-- being shown (Hyprland destroys an invisible one), so taking it would blank
-- that screen. An empty workspace already on the TARGET is the exception and
-- the ideal answer, since showing it there is what this is about to do anyway.
--
-- The current workspace can never be picked: it holds windows, or the caller
-- returned before asking.
local function free_workspace_id(target)
	local taken = {}
	for _, ws in ipairs(hl.get_workspaces()) do
		if ws.id and ws.id > 0 then
			local reusable = ws.windows == 0 and ws.monitor and ws.monitor.name == target
			if not reusable then
				taken[ws.id] = true
			end
		end
	end
	for id = 1, 99 do
		if not taken[id] then
			return id
		end
	end
	return nil
end

-- Three steps, and the order is the whole of it: fill the workspace, move it
-- across, then show it. Measured on 0.56.2.
--
--   1. THE MOVES ARE SILENT -- workspace_utils.move_windows, which is also
--      where the `follow = false` spelling of that is written up. Here the
--      focus must stay put for a reason of its own: input.lua sets
--      follow_mouse = 1, so focus left on the far screen with the pointer still
--      on this one is undone by the first twitch of the mouse. That is why this
--      key does not end on the windows it moved and SUPER+CTRL+1..0 does.
--   2. A workspace that does not exist yet is created on the monitor of the
--      window moved into it (verified: a window on DP-2 sent to workspace 9
--      took workspace 9 to DP-2), so it is built here and moved across
--      afterwards. Doing it the other way round -- making it on the target
--      first -- needs an empty workspace to survive being created, which it
--      only does while something displays it, so it costs a focus excursion to
--      the other monitor and back. Filling it first means it always has windows
--      in it and nothing has to hold it open.
--   3. hl.dsp.workspace.move RELOCATES the workspace but does not SHOW it: the
--      target monitor goes on displaying whatever it was displaying, which is
--      the one outcome worse than doing nothing -- the windows are gone from
--      this screen and not visible on that one. `monitor:set_workspace()` is
--      what displays it, and unlike focusing the monitor it moves neither the
--      focus nor the pointer (verified: cursor unmoved, `focused` unchanged,
--      the target's active workspace changed). It takes a spec table with a
--      workspace OBJECT -- an id number is "attempt to index a number value"
--      and a table naming an id that does not exist yet returns `ok` and does
--      nothing at all, which is the other reason the workspace is filled first.
function monitor_utils.dump_to_other_monitor()
	local monitor = hl.get_active_monitor()
	local workspace = hl.get_active_workspace()
	if not monitor or not monitor.name or not workspace or not workspace.id then
		return
	end
	local target = next_monitor(monitor.name)
	if not target then
		return -- one enabled monitor: nowhere to send anything
	end

	-- Collected before the first move, and as addresses rather than handles --
	-- see workspace_utils.window_addresses for why either matters.
	local addresses = workspace_utils.window_addresses(workspace.id)
	if #addresses == 0 then
		return
	end

	local id = free_workspace_id(target)
	if not id then
		return
	end

	workspace_utils.move_windows(addresses, id)
	hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(id), monitor = target }))

	-- Fetched now rather than earlier: the workspace may not have existed when
	-- this function started, and the handles from before the moves are the
	-- dangling ones.
	local target_monitor = hl.get_monitor(target)
	local moved = hl.get_workspace(id)
	if target_monitor and moved then
		target_monitor:set_workspace({ workspace = moved })
	end
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

-- IMPORTANT: "monitor.removed" fires for a monitor we DISABLED ourselves, not
-- just for a cable coming out -- Hyprland makes no distinction, and verified
-- here: `hl.monitor({ output = "eDP-1", disabled = true })` logs
-- "monitor.removed: eDP-1" immediately. So this handler has to ignore the
-- panel's own removal or it undoes panel_off one event later: the key disabled
-- the panel, this brought it straight back, and SUPER+SHIFT+Z looked like it
-- did nothing at all while quietly cycling the output.
--
-- That fight is also everything else that was reported. Each cycle was a real
-- DRM disable/enable of the panel -- which is a monitor replug as far as the
-- rest of the session is concerned, so it re-ran the layout and left
-- WirePlumber holding a ghost sink node per cycle, the duplicate audio outputs
-- in the bar's audio menu (the same ghosting AudioService.uniqueByName already
-- filters after an HDMI replug).
--
-- It only started when panel_on() began working. Before the `disabled = false`
-- fix, panel_on could not re-enable anything, so this handler had always been
-- calling a function that did nothing and the loop could not close. That is
-- the third time in this repo that repairing a dead line was itself the
-- regression -- see the monitor.added duplicate bar, and hypridle's DPMS.
function monitor_utils.handle_remove_monitor(monitor)
	if not monitor then
		return
	end
	local panel = monitor_utils.internal_panel()
	if not panel or monitor.name == panel then
		return
	end
	-- An external screen was unplugged. Bring the panel back if it is off, or
	-- this is a laptop with every display disabled and no way to see the
	-- shortcut that would undo it.
	monitor_utils.panel_on()
	-- A screen was physically unplugged, so unlike panel_off there was no
	-- chance to pin anything first and whatever is left may already have slid
	-- across. Writing each remaining monitor's current position repairs that
	-- after the fact -- the same single write, doing the same job a step later.
	pin_monitors(nil)
end

return monitor_utils
