hl.window_rule({
	name = "suppressevent-maximize",
	match = { class = ".*" },
	suppress_event = "maximize",
})

-- Window specific rules
hl.window_rule({
	name = "google-chrome",
	match = { class = "google-chrome-stable" },
	no_blur = true,
})

hl.window_rule({
	name = "float-pavucontrol",
	match = { class = "org.pulseaudio.pavucontrol" },
	size = "800 1000",
	center = true,
	float = true,
})

hl.window_rule({
	name = "btop-terminal-rule",
	match = { class = "btop-float" },
	size = "1200 800",
	center = true,
	float = true,
})

-- PiaPill's right-click opens a terminal purely to hold a sudo password
-- prompt; a tiled full-size window for one line of input is jarring.
hl.window_rule({
	name = "pia-start-rule",
	match = { class = "pia-start" },
	size = "700 200",
	center = true,
	float = true,
})

hl.window_rule({
	name = "float-nmtui",
	match = { class = "nmtui-floating" },
	size = "600 500",
	center = true,
	float = true,
})

hl.window_rule({
	name = "float-update",
	match = { class = "update-floating" },
	size = "900 650",
	center = true,
	float = true,
})

hl.window_rule({
	name = "float-blueman",
	match = { class = "blueman-manager" },
	size = "800 700",
	center = true,
	float = true,
})

hl.window_rule({
	name = "kcalc",
	match = { class = "org.kde.kcalc" },
	size = "500 700",
	center = true,
	float = true,
})

hl.window_rule({
	name = "calc_gnome",
	match = { class = "org.gnome.Calculator" },
	size = "700 870",
	center = true,
	float = true,
})

hl.window_rule({
	name = "float-swayimg",
	match = { class = "swayimg" },
	size = "(monitor_w*0.5) (monitor_h*0.5)",
	center = true,
	float = true,
})

hl.window_rule({
	name = "float-localsend",
	match = { class = "localsend" },
	size = "(monitor_w*0.5) (monitor_h*0.5)",
	center = true,
	float = true,
})

hl.window_rule({
	name = "chrome-picture-in-picture",
	match = { title = "^(Picture-in-picture)$" },
	float = true,
	pin = true,
})

hl.window_rule({
	name = "rustdesk",
	match = { class = "rustdesk" },
	no_shortcuts_inhibit = true,
})

-- Steam launches every game with class `steam_app_<appid>`, so one regex covers
-- the lot. `immediate` opts the window into tearing; `general.allow_tearing`
-- (look.lua) is the master switch it needs beside it, and the game itself still
-- has to request tearing through the tearing-control protocol -- so a game that
-- does not ask is unaffected and nothing outside this class can ever tear.
-- Wanted for frame generation: with the compositor holding every frame to
-- vsync, interpolated frames arrive in pairs against a fixed refresh and pace
-- as micro-stutter rather than as motion.
hl.window_rule({
	name = "steam-tearing",
	match = { class = "^steam_app_.*$" },
	immediate = true,
})
