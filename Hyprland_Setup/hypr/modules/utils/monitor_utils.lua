local monitor_utils = {}
local mainMonitor = "DP-2"

function monitor_utils.turn_off_monitor()
	hl.monitor({ output = mainMonitor, disabled = true })
end

function monitor_utils.turn_on_monitor()
	hl.monitor({ output = mainMonitor, mode = "highrr", position = "auto", scale = "1" })
	hl.dispatch(hl.dsp.exec_cmd("hyprctl reload"))
end

-- function monitor_utils.move_all_workspaces(target_monitor)
-- 	for i = 1, 4 do
-- 		hl.dispatch(hl.dsp.workspace.move({ workspace = tostring(i), monitor = target_monitor }))
-- 	end
-- end

-- function monitor_utils.handle_new_monitor(monitor_name)
-- 	if not monitor_name then
-- 		return
-- 	end
-- 	local new_monitor = monitor_name.name
--
-- 	hl.timer(function()
-- 		move_all_workspaces(new_monitor)
-- 	end, { timeout = 500, type = "oneshot" })
-- end
--
-- function monitor_utils.handle_remove_monitor(monitor_name)
-- 	if not monitor_name then
-- 		return
-- 	end
--
-- 	move_all_workspaces(mainMonitor)
-- end

return monitor_utils