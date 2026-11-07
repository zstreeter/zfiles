return {
	"pablopunk/pi.nvim",
	cmd = { "PiAsk", "PiAskSelection", "PiCancel", "PiLog" },
	opts = {
		-- provider/model unset: :PiAsk follows pi's own defaults
		-- (~/.config/pi/agent/settings.json), so the two never drift apart.
		thinking = "off",

		context = {
			max_bytes = 24000,
			ask = { surrounding_lines = 80 },
			selection = { surrounding_lines = 40 },
			-- Send LSP/linter diagnostics along with the buffer.
			diagnostics = { enabled = true },
		},

		-- :PiAsk is a one-shot; skill descriptions and extensions are dead
		-- weight in its system prompt. Use the CLI when you want those.
		skills = false,
		extensions = false,
	},
	config = function(_, opts)
		require("pi").setup(opts)
	end,
	keys = {
		{ "<leader>ap", "<cmd>PiAsk<cr>", mode = "n", desc = "AI: Pi ask" },
		{ "<leader>ap", "<cmd>PiAskSelection<cr>", mode = "v", desc = "AI: Pi ask (selection)" },
	},
}
