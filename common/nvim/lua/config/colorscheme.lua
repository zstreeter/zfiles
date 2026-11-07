-- Applies the omarchy theme when present (via the config.omarchy adapter),
-- falling back to catppuccin on non-omarchy systems or unknown themes.
local colorscheme = require("config.omarchy").get_colorscheme() or "catppuccin"

if not pcall(vim.cmd.colorscheme, colorscheme) then
	vim.notify("Colorscheme '" .. colorscheme .. "' not found, using catppuccin", vim.log.levels.WARN)
	pcall(vim.cmd.colorscheme, "catppuccin")
end
