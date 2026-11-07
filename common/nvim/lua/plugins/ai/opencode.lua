return {
	"nickjvandyke/opencode.nvim",
	version = "*",
	dependencies = {
		{
			"folke/snacks.nvim",
			optional = true,
			opts = {
				input = {},
				picker = {
					actions = {
						opencode_send = function(...)
							return require("opencode").snacks_picker_send(...)
						end,
					},
					win = {
						input = {
							keys = {
								["<a-a>"] = { "opencode_send", mode = { "n", "i" } },
							},
						},
					},
				},
			},
		},
	},
	config = function()
		---@type opencode.Opts
		vim.g.opencode_opts = {}
	end,
	keys = {
		{
			"<leader>ao",
			function()
				require("opencode").ask("@this: ", { submit = true })
			end,
			mode = { "n", "x" },
			desc = "AI: OpenCode ask",
		},
	},
}
