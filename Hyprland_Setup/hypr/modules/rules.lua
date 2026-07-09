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

hl.window_rule({
	name = "float-nmtui",
	match = { class = "nmtui-floating" },
	size = "600 500",
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
	name = "gnome-text-editor",
	match = { class = "org.gnome.TextEditor" },
	opacity = "0.9 0.8",
})

hl.window_rule({
	name = "thunar",
	match = { class = "thunar" },
	opacity = "0.9 0.8",
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

hl.window_rule({
	name = "float-terminal-weathr",
	match = { class = "weathr-float" },
	size = "1000 600",
	center = true,
	float = true,
})
