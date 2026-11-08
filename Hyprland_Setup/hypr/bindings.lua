-- Superwhisper's dictation shortcuts (push to talk, toggle, cancel).
--
-- The binds are not written here: Superwhisper generates them into
-- ~/.config/superwhisper/shortcuts.lua every time its shortcut settings are
-- saved, so the keys are chosen in Superwhisper (Configuration > Keyboard
-- shortcuts, or `superwhisper shortcuts set hold RightControl`). install.sh
-- seeds them once, from SUPERWHISPER_SHORTCUTS, on a machine that has none.
--
-- This file exists for two reasons:
--   1. Superwhisper assumes Omarchy's layout and refuses to save shortcuts at
--      all unless ~/.config/hypr/bindings.lua exists.
--   2. On saving, it appends a "Superwhisper managed shortcuts" block below
--      that dofile()s the generated file by an absolute /home/<user> path. The
--      loader here does the same by a path that is not tied to one machine, so
--      the binds survive a deploy (which overwrites this file and drops that
--      block). The generated file guards itself, so the block loading it a
--      second time is a no-op. Leave the block out of a commit after --pull.
--
-- Required last in hyprland.lua: an error in the generated file then cannot
-- stop the rest of the config from loading.
local config_home = os.getenv("XDG_CONFIG_HOME")
if not config_home or config_home == "" then
  config_home = os.getenv("HOME") .. "/.config"
end
local shortcuts = config_home .. "/superwhisper/shortcuts.lua"
local f = io.open(shortcuts, "r")
if f then
  f:close()
  dofile(shortcuts)
end
