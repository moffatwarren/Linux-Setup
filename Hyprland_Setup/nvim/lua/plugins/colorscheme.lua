-- Catppuccin Mocha, matching the rest of the desktop (quickshell/Theme.qml,
-- kitty, hyprlock). Without this LazyVim loads its own default, tokyonight --
-- catppuccin.nvim is already pinned in lazy-lock.json because LazyVim ships it
-- as an optional colorscheme, so this only has to select it.
return {
  {
    "catppuccin/nvim",
    -- The repo is "nvim"; without this the plugin directory, and the name
    -- `colorscheme` resolves against, would be the ambiguous "nvim".
    name = "catppuccin",
    opts = {
      flavour = "mocha",
      -- kitty runs at background_opacity 1.0, so the editor paints its own
      -- base rather than letting the terminal show through.
      transparent_background = false,
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      -- "catppuccin-mocha" rather than plain "catppuccin": the plugin registers
      -- one colorscheme per flavour, and naming the flavour means the editor
      -- cannot drift to another one if `flavour` above is ever changed or if
      -- background is toggled.
      colorscheme = "catppuccin-mocha",
    },
  },
}
