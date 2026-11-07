return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	opts = {
		preset = "helix",
		plugins = {
			marks = true,
			registers = true,
			spelling = {
				enabled = true,
				suggestions = 20,
			},
			presets = {
				operators = false,
				motions = false,
				text_objects = false,
				windows = false,
				nav = false,
				z = false,
				g = false,
			},
		},
		win = {
			border = "rounded",
			no_overlap = false,
			padding = { 0, 2 }, -- extra window padding [top/bottom, right/left]
			title = false,
			title_pos = "center",
			zindex = 1000,
		},
		show_help = false,
		show_keys = false,
		disable = {
			buftypes = {},
		},
	},
	config = function(_, opts)
		local wk = require("which-key")
		wk.setup(opts)

		-- Group labels come from the keymap registry (config/keys.lua) — the
		-- single source for prefix ownership. Direct bindings get their
		-- description from the keymap callsite.
		wk.add(require("config.keys").groups)
	end,
}
