
local wezterm = require 'wezterm'

local config = wezterm.config_builder()

config.default_domain = 'WSL:Ubuntu-24.04'

local mux = wezterm.mux

wezterm.on("gui-startup", function()
  local tab, pane, window = mux.spawn_window{}
  window:gui_window():maximize()
end)

config.color_scheme = "Catppuccin Mocha"

config.font_size = 16
config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'FiraCode Nerd Font',
  'Source Code Pro',
}

config.window_decorations = 'RESIZE'
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.hide_mouse_cursor_when_typing = true
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 1.0
config.audible_bell = "Disabled"
config.cursor_blink_rate = 0

config.enable_kitty_graphics = true


return config
