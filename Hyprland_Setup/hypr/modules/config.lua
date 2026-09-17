local config = {}

-- Status bar to launch (the command name of the bar)
config.bar = "quickshell"
config.mainMod = "SUPER"
config.terminal = "kitty"

-- How a mode is chosen for every monitor, on every machine. One of Hyprland's
-- keywords: "highrr" (highest refresh rate), "highres" (highest resolution) or
-- "preferred" (whatever the display asks for).
--
-- THESE TWO CONFLICT, and on real hardware the difference is large. A monitor
-- offering both 3840x2160@60 and 2560x1440@240 -- verified live on one here --
-- lands on 1440p240 under "highrr" and on 4K60 under "highres". There is no
-- keyword for "highest of both" because no such mode need exist. "highrr" is
-- the choice: motion over pixels, and it costs nothing on a monitor with only
-- one refresh rate, which still gets its full resolution.
--
-- Read by modules/monitors.lua, which applies it to every output, and by
-- utils/monitor_utils.lua, which has to restate it whenever it writes a
-- monitor-specific rule -- a specific rule overrides the catch-all wholesale,
-- so a rule that did not name a mode would silently drop that monitor to
-- Hyprland's default. One value, so those cannot drift apart.
config.monitorMode = "highrr"

return config
