-- WezTerm config for the Windows host of the WSL work laptop.
--
-- This file is the source of truth. windows/install.ps1 copies it to
-- %USERPROFILE%\.wezterm.lua -- edits made directly to that copy will be
-- overwritten on the next bootstrap run.
--
-- Adopted from the pre-zfiles ~/.wezterm.lua, unchanged apart from this header.

local wezterm = require 'wezterm'

local config = wezterm.config_builder()

-- Opening WezTerm drops straight into WSL rather than PowerShell.
config.default_domain = 'WSL:Ubuntu-24.04'

local mux = wezterm.mux

wezterm.on("gui-startup", function()
  local tab, pane, window = mux.spawn_window{}
  window:gui_window():maximize()
end)

config.color_scheme = "Catppuccin Macchiato"

config.font_size = 16
config.font = wezterm.font_with_fallback {
  'FiraCode Nerd Font',
  'Source Code Pro',
  'JetBrains Mono',
}

config.window_decorations = 'RESIZE'
config.hide_mouse_cursor_when_typing = true
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 1.0
config.audible_bell="Disabled"
config.cursor_blink_rate = 0

return config