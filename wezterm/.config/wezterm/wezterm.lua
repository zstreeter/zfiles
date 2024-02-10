local wezterm = require("wezterm")

local config = wezterm.config_builder()

local mux = wezterm.mux

wezterm.on("gui-startup", function()
	local tab, pane, window = mux.spawn_window({})
	window:gui_window():maximize()
end)

config.enable_wayland = true

config.color_scheme = "Catppuccin Macchiato"
config.font_size = 12
config.font = wezterm.font("FiraCode Nerd Font")

config.window_close_confirmation = 'NeverPrompt'
config.window_decorations = "RESIZE"
config.hide_mouse_cursor_when_typing = true
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 0.9
config.audible_bell = "Disabled"
config.cursor_blink_rate = 0

return config
