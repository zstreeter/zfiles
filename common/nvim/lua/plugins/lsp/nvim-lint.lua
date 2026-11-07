return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")

		-- Configure linters by filetype
		lint.linters_by_ft = {
			-- javascript = { "eslint_d" },
			-- typescript = { "eslint_d" },
			-- javascriptreact = { "eslint_d" },
			-- typescriptreact = { "eslint_d" },
			-- svelte = { "eslint_d" },
			python = { "pylint" },
			-- markdown = { "markdownlint" },
			-- json = { "jsonlint" },
			-- yaml = { "yamllint" },
			-- dockerfile = { "hadolint" },
			-- terraform = { "tflint" },
			-- go = { "golangcilint" },
			-- lua = { "luacheck" },
			sh = { "shellcheck" },
			bash = { "shellcheck" },
			zsh = { "shellcheck" },
		}

		-- Create autocommand to trigger linting
		local lint_augroup = vim.api.nvim_create_augroup("lint", { clear = true })

		-- Not BufEnter: that re-ran pylint on every buffer switch.
		vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost", "InsertLeave" }, {
			group = lint_augroup,
			callback = function()
				lint.try_lint()
			end,
		})

		-- Create a keymap to manually trigger linting
		vim.keymap.set("n", "<leader>cl", function()
			lint.try_lint()
		end, { desc = "Trigger linting for current file" })
	end,
}
