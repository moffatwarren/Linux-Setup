-- The catch-all: applies to every output, on any machine. A monitor-SPECIFIC
-- rule written later (utils/monitor_utils.lua does, for the panel toggle and
-- the monitor swap) overrides this one WHOLESALE rather than merging with it,
-- so anything that matters has to be restated there too -- see config.monitorMode.
local config = require("modules.config")

hl.monitor({
	output = "",
	mode = config.monitorMode,
	position = "auto",
	scale = "1",
})
