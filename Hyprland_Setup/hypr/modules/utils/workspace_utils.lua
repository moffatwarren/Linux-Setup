local workspace_utils = {}

-- Moving a whole workspace's worth of windows somewhere else. Two keys do it:
-- SUPER+M sends them to the other monitor (monitor_utils.dump_to_other_monitor,
-- which picks the workspace and then calls in here), and SUPER+CTRL+1..0 sends
-- them to a workspace you name. Everything both of them share about *how* a
-- pile of windows is moved lives here, so the traps below are written down
-- once.

-- The addresses of every window on a workspace.
--
-- ADDRESSES, NOT WINDOW HANDLES, AND ALL OF THEM BEFORE THE FIRST MOVE. A move
-- re-lays-out, which can leave a handle from an already-fetched list dangling
-- -- and a dangling handle does not error, it reads every field as nil. That is
-- the same collect-then-dispatch rule monitor_utils.move_workspaces_off_panel
-- is written up for, where it cost a crash on the second iteration; an address
-- is a plain string and cannot go stale in that way.
function workspace_utils.window_addresses(workspace_id)
	local addresses = {}
	if not workspace_id then
		return addresses
	end
	for _, w in ipairs(hl.get_windows({ workspace = workspace_id })) do
		if w.address then
			addresses[#addresses + 1] = w.address
		end
	end
	return addresses
end

-- Move those windows to workspace `id`, without dragging the focus along.
--
-- THE FIELD FOR THAT IS `follow = false`, NOT `silent = true`. `silent` is what
-- the legacy dispatcher is called (movetoworkspacesilent) and it is not a field
-- here: passing it returns `ok` and moves the focus with the window, the same
-- shape as the `{ state = "on" }` trap in hypridle.conf -- a spec Hyprland
-- accepts and does not act on. Verified both ways on 0.56.2 against a scratch
-- window.
--
-- Silent is the right default even for the caller that wants to end up on the
-- target: focus moved once at the end is one switch, where a following move per
-- window is one per window. A workspace that does not exist yet is created on
-- the monitor of the window moved into it -- verified: a window on DP-2 sent to
-- workspace 9 took workspace 9 to DP-2 -- which is what makes SUPER+CTRL+N land
-- on the screen you pressed it from, and what monitor_utils then has to undo.
function workspace_utils.move_windows(addresses, id)
	for _, address in ipairs(addresses) do
		hl.dispatch(hl.dsp.window.move({
			window = "address:" .. address,
			workspace = tostring(id),
			follow = false,
		}))
	end
end

-- SUPER+CTRL+1..0: send every window on the current workspace to workspace
-- `id`, and go with them. The key is the workspace number, so `0` is workspace
-- 10, exactly as it is for SUPER+N and SUPER+SHIFT+N.
--
-- FOCUS FOLLOWS HERE AND DELIBERATELY DOES NOT FOR SUPER+M, and the difference
-- is what is left on screen. SUPER+M puts the windows on the other monitor and
-- shows them there, so staying put still leaves them in sight; this sends them
-- to a workspace that is by definition not the one being displayed, so staying
-- put would blank the screen. A key that appears to have closed everything you
-- had open is a bad key even when it is recoverable, and the recovery -- SUPER
-- plus the same number -- is exactly the press this saves. It is also the
-- shape of the bind next door: SUPER+SHIFT+N moves one window to workspace N
-- and follows it, so SUPER+CTRL+N moving all of them and following is the
-- parallel that needs no explaining.
--
-- Nothing is asserted about WHERE workspace `id` is. If it already exists on
-- another monitor the windows go there and the focus follows onto that monitor
-- (verified: focusing a workspace that lives on another output focuses that
-- output rather than dragging the workspace across), which is the honest
-- reading of "move them to workspace 5" when workspace 5 is over there.
function workspace_utils.move_all_to(id)
	local workspace = hl.get_active_workspace()
	if not workspace or not workspace.id or workspace.id == id then
		return -- already there: every window would be moved onto itself
	end
	local addresses = workspace_utils.window_addresses(workspace.id)
	if #addresses == 0 then
		return -- an empty workspace: nothing to move, and nowhere worth going
	end
	workspace_utils.move_windows(addresses, id)
	hl.dispatch(hl.dsp.focus({ workspace = id }))
end

return workspace_utils
