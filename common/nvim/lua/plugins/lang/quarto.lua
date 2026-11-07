local M = {
	"quarto-dev/quarto-nvim",
	ft = "quarto", -- also gates molten, image.nvim and otter, which loaded at every startup
	dependencies = {
		"jmbuhr/otter.nvim",
		"nvim-treesitter/nvim-treesitter",
		{ "benlubas/molten-nvim", build = ":UpdateRemotePlugins" },
		{ "3rd/image.nvim", lazy = true, opts = {} },
	},
}

function M.config()
	-- 1. Setup Molten Globals
	vim.g.molten_image_provider = "image.nvim"
	vim.g.molten_output_win_max_height = 20
	vim.g.molten_auto_open_output = false
	vim.g.molten_wrap_output = true
	vim.g.molten_virt_text_output = true
	vim.g.molten_virt_lines_off_by_1 = true

	-- 2. Setup Quarto
	require("quarto").setup({
		debug = false,
		closePreviewOnExit = true,
		lspFeatures = {
			enabled = true,
			chunks = "curly",
			languages = { "r", "python", "julia", "bash", "html" },
			diagnostics = {
				enabled = true,
				triggers = { "BufWritePost" },
			},
			completion = {
				enabled = true,
			},
		},
		codeRunner = {
			enabled = true,
			default_method = "molten",
			ft_runners = { python = "molten" },
			never_run = { "yaml" },
		},
	})

	-- 3. Register Keys via Which-Key
	-- Using <leader>Q (Shift+q) to avoid conflict with Quickfix (<leader>q)
	local runner = require("quarto.runner")
	local wk = require("which-key")

	wk.add({
		-- Group labels live in config/keys.lua; bindings registered here.

		-- Running Code
		{ "<leader>Qc", runner.run_cell, desc = "Run Cell" },
		{ "<leader>Qa", runner.run_above, desc = "Run Cell & Above" },
		{ "<leader>QA", runner.run_all, desc = "Run All Cells" },
		{ "<leader>Ql", runner.run_line, desc = "Run Line" },
		{ "<leader>Qv", runner.run_range, desc = "Run Visual Range", mode = "v" },

		-- Molten / Jupyter Specific
		{ "<leader>Qmi", "<cmd>MoltenInit<cr>", desc = "Init Kernel" },
		{ "<leader>Qmo", "<cmd>MoltenEvaluateOperator<cr>", desc = "Evaluate Operator" },
		{ "<leader>Qmr", "<cmd>MoltenReevaluateCell<cr>", desc = "Re-evaluate Cell" },
		{ "<leader>Qmd", "<cmd>MoltenDelete<cr>", desc = "Delete Output" },
		{ "<leader>Qmh", "<cmd>MoltenHideOutput<cr>", desc = "Hide Output" },
		{ "<leader>Qms", "<cmd>MoltenShowOutput<cr>", desc = "Show Output" },

		-- Preview
		{ "<leader>Qp", "<cmd>QuartoPreview<cr>", desc = "Quarto Preview" },
	})
end

return M
