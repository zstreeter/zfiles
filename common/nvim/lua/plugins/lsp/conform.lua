return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local conform = require("conform")

		conform.setup({
			formatters_by_ft = {
				-- Web development
				javascript = { "prettier" },
				typescript = { "prettier" },
				javascriptreact = { "prettier" },
				typescriptreact = { "prettier" },
				css = { "prettier" },
				html = { "prettier" },
				json = { "prettier" },
				yaml = { "prettier" },
				markdown = { "prettier" },
				graphql = { "prettier" },

				-- Lua
				lua = { "stylua" },

				-- Python
				python = { "isort", "black" },

				-- Go
				go = { "goimports" }, -- goimports also gofmts

				-- Rust
				rust = { "rustfmt" },

				-- Shell
				sh = { "shfmt" },
				bash = { "shfmt" },
				zsh = { "shfmt" },

				-- TOML
				toml = { "taplo" },

				-- Use the "*" filetype to run formatters on all filetypes
				["*"] = { "trim_whitespace" },
			},
			default_format_opts = {
				lsp_format = "fallback",
			},
			-- Prose is never rewritten on save: prettier and trim_whitespace mangle
			-- math, [[wikilinks]] and two-space hard breaks. <leader>cf still formats.
			format_on_save = function(buf)
				if vim.tbl_contains({ "markdown", "quarto" }, vim.bo[buf].filetype) then
					return
				end
				return { timeout_ms = 500, lsp_format = "fallback" }
			end,
			-- Customize formatters
			formatters = {
				shfmt = {
					prepend_args = { "-i", "2" }, -- 2 spaces indentation
				},
			},
		})

		-- Keybindings
		vim.keymap.set({ "n", "v" }, "<leader>cf", function()
			conform.format({
				lsp_format = "fallback",
				async = false,
				timeout_ms = 500,
			})
		end, { desc = "Format file or range (in visual mode)" })
	end,
}
