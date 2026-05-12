hl.monitor({
	output = "",
	mode = "highrr",
	position = "auto",
	scale = "1",
})

local function move_all_workspaces(target_monitor)
	for i = 1, 4 do
		hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(i), monitor = target_monitor }))
	end
end

local function handle_new_monitor(monitor_name)
	if not monitor_name then
		return
	end
	local new_monitor = monitor_name.name

	hl.timer(function()
		move_all_workspaces(new_monitor)
		--	hl.monitor({ output = "eDP-1", disabled = true })
	end, { timeout = 500, type = "oneshot" })
end

local function handle_remove_monitor(monitor_name)
	if not monitor_name then
		return
	end

	--hl.monitor({ output = "eDP-1", mode = "highrr", position = "auto", scale = "1" })
	move_all_workspaces("eDP-1")
end

hl.on("monitor.added", handle_new_monitor)
hl.on("monitor.removed", handle_remove_monitor)
