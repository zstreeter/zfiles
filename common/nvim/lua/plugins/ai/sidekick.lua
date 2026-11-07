return {
	"folke/sidekick.nvim",
	event = "VeryLazy",
	opts = {
		cli = {
			mux = {
				enabled = true,
				-- "terminal" embeds the CLI in an nvim :terminal, whose libvterm drops
				-- the kitty graphics that @fadouse/pi-math emits for rendered LaTeX.
				-- "split" hands the tool to the multiplexer, which actually draws them.
				create = "split",
				split = { vertical = true, size = 0.45 },
			},
		},
	},
	config = function(_, opts)
		require("sidekick").setup(opts)
		-- Swaps the backend to herdr when nvim is running inside one. Outside
		-- herdr this is a no-op and sidekick keeps its tmux/zellij default.
		require("config.herdr").setup()
	end,
	keys = {
		{
			"<leader>as",
			function()
				require("sidekick.cli").select()
			end,
			mode = "n",
			desc = "AI: Sidekick (CLI picker)",
		},
		{
			"<leader>as",
			function()
				require("sidekick.cli").send({ selection = true })
			end,
			mode = "v",
			desc = "AI: Sidekick send selection",
		},
		{
			"<leader>ai",
			function()
				require("sidekick.cli").toggle({ name = "pi", focus = true })
			end,
			mode = "n",
			desc = "AI: Toggle pi (interactive)",
		},
		{
			"<leader>ac",
			function()
				require("sidekick.cli").prompt()
			end,
			mode = { "n", "v" },
			desc = "AI: Sidekick prompt picker (explain/fix/review/tests)",
		},
		{
			"<leader>af",
			function()
				require("sidekick.cli").send({ msg = "{file}" })
			end,
			mode = "n",
			desc = "AI: Send current file as context",
		},
	},
}
