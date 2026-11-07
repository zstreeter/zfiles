local M = {
	"LunarVim/breadcrumbs.nvim",
	dependencies = {
		{ "SmiteshP/nvim-navic" },
		-- { "neovim/nvim-lspconfig" },
	},
}

function M.config()
	local kinds = require("config.icons").kind

	require("nvim-navic").setup({
		icons = kinds,
		highlight = true,
		lsp = {
			auto_attach = true,
			preference = {
				"templ",
				"ts_ls",
			},
		},
		click = true,
		separator = "  ",
		depth_limit = 0,
		depth_limit_indicator = "..",
	})

	require("breadcrumbs").setup()

	-- Update winbar immediately on buffer enter and LSP attach
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "LspAttach" }, {
		callback = function()
			pcall(require("breadcrumbs").get_winbar)
		end,
	})
end

return M
