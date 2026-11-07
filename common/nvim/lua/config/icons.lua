-- Shared icon tables. Single source of truth for every glyph in the config.
-- Callers: blink.lua (appearance.kind_icons), ui/breadcrumbs.lua (navic), config/lsp.lua
-- (diagnostic signs), ui/lualine.lua (statusline diagnostics).
local M = {}

M.kind = {
	Array = " ",
	Boolean = " ",
	Class = " ",
	Color = " ",
	Constant = " ",
	Constructor = " ",
	Enum = " ",
	EnumMember = " ",
	Event = " ",
	Field = " ",
	File = " ",
	Folder = "󰉋 ",
	Function = " ",
	Interface = " ",
	Key = " ",
	Keyword = " ",
	Method = " ",
	Module = " ",
	Namespace = " ",
	Null = "󰟢",
	Number = " ",
	Object = " ",
	Operator = " ",
	Package = " ",
	Property = " ",
	Reference = " ",
	Snippet = " ",
	String = " ",
	Struct = " ",
	Text = " ",
	TypeParameter = " ",
	Unit = " ",
	Value = " ",
	Variable = " ",
	Codeium = "󰚩 ",
	LazyDev = "b ",
}

M.diagnostics = {
	Error = " ",
	Warn = " ",
	Hint = " ",
	Info = " ",
}

return M
