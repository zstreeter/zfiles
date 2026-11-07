return {
	"saghen/blink.cmp",
	dependencies = { "rafamadriz/friendly-snippets" },
	version = "1.*",
	-- blink's plugin/ file registers its LSP capabilities via vim.lsp.config("*").
	opts = {
		appearance = { kind_icons = require("config.icons").kind },
		cmdline = {
			keymap = {
				preset = "inherit",
				["<C-j>"] = { "select_next", "fallback" },
				["<C-k>"] = { "select_prev", "fallback" },
			},
		},
		keymap = {
			preset = "default",
			["<C-k>"] = { "select_prev", "fallback" },
			["<C-j>"] = { "select_next", "fallback" },
			["<CR>"] = { "select_and_accept", "fallback" },
		},
		fuzzy = { implementation = "prefer_rust_with_warning" },
		completion = { documentation = { auto_show = true } },
		sources = {
			default = { "lazydev", "lsp", "path", "buffer" },
			providers = {
				lazydev = { name = "LazyDev", module = "lazydev.integrations.blink", score_offset = 100 },
			},
		},
	},
}
