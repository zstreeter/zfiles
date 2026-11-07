return {
	"mason-org/mason.nvim",
	dependencies = {
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		-- Never setup() on purpose: mason-tool-installer needs it installed to
		-- map LSP-client names (config/servers.lua) to mason package names.
		"mason-org/mason-lspconfig.nvim",
	},
	config = function()
		local servers = require("config.servers")

		require("mason").setup({
			ui = {
				border = "rounded",
			},
		})

		-- Combine LSP servers with formatters/linters for installation
		local ensure_installed =
			vim.list_extend(vim.list_extend({}, servers.lsp_servers), servers.formatters_and_linters)

		require("mason-tool-installer").setup({
			ensure_installed = ensure_installed,
		})
	end,
}
