-- WezTerm config for the Windows host of the WSL work laptop (zfiles issue #13).
--
-- This file is the source of truth. wsl/windows/install.ps1 copies it to
-- %USERPROFILE%\.wezterm.lua -- edits made directly to that copy will be
-- overwritten on the next bootstrap run.
--
-- Designed to match the Omarchy/Ghostty feel: same font family, zero padding,
-- and the same static Catppuccin Mocha the other non-Omarchy targets use
-- (herdr's [theme.custom], yazi's zfiles->catppuccin-mocha flavor, sioyek's
-- static prefs). Theme parity is STATIC by decision: there is no Omarchy
-- theme engine on Windows, so nothing re-renders on theme-set -- change the
-- scheme here if the fleet ever moves off Catppuccin.

local wezterm = require 'wezterm'

local config = wezterm.config_builder()

-- Opening WezTerm drops straight into WSL rather than PowerShell.
config.default_domain = 'WSL:Ubuntu-24.04'

local mux = wezterm.mux

wezterm.on("gui-startup", function()
  local tab, pane, window = mux.spawn_window{}
  window:gui_window():maximize()
end)

config.color_scheme = "Catppuccin Mocha"

-- Omarchy runs JetBrainsMono NF at 9pt; 16pt is the equivalent optical size
-- on this laptop's Windows DPI scaling (carried over from the pre-zfiles
-- config, which was tuned on the actual hardware).
config.font_size = 16
config.font = wezterm.font_with_fallback {
  'JetBrainsMono Nerd Font',
  'FiraCode Nerd Font',
  'Source Code Pro',
}

-- Ghostty/Omarchy feel: no chrome, no padding, no noise.
config.window_decorations = 'RESIZE'
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.hide_mouse_cursor_when_typing = true
config.hide_tab_bar_if_only_one_tab = true
config.window_background_opacity = 1.0
config.audible_bell = "Disabled"
config.cursor_blink_rate = 0

-- Graphics (zfiles issue #8): herdr re-emits the classic kitty protocol and
-- WezTerm implements exactly that subset -- but only nightly builds carry the
-- 2024+ fixes (last stable is Feb 2024), and install.ps1 only copies configs,
-- so the nightly is a manual install on the laptop for now.
-- enable_kitty_graphics already defaults to true; set explicitly so a future
-- default flip can't silently kill yazi previews.
config.enable_kitty_graphics = true
-- If previews mis-scale or break over the default wsl.exe/ConPTY route (WSL2
-- reports a zero pixel size), the documented fix is sshd in WSL plus
-- `wezterm ssh 127.0.0.1` -- add an ssh_domains entry here once sshd is set
-- up on the laptop and make it the default_domain if it proves out.

-- Nav chain: deliberately NO keybindings here. Caps+hjkl arbitration happens
-- outside the terminal -- caps.ahk asks herdr-navd (127.0.0.1:6224), which
-- walks nvim splits -> herdr panes -> GlazeWM windows. WezTerm just passes
-- keys through; binding hjkl chords here would shadow the daemon's view.

return config
