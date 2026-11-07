-- Only where Zotero is installed: zotcite warns about a missing profiles.ini otherwise.
local sqlite = vim.fn.expand("~/Zotero/zotero.sqlite")

return {
	"jalvesaq/zotcite",
	cond = vim.uv.fs_stat(sqlite) ~= nil,
	ft = { "markdown", "quarto", "rmd", "pandoc", "tex", "typst" },
	dependencies = {
		"nvim-treesitter/nvim-treesitter",
	},
	config = function()
		require("zotcite").setup({
			SQL_path = sqlite,
			tmpdir = vim.fn.stdpath("cache") .. "/zotcite",
			hl_cite_key = true,
			conceallevel = 2,
			wait_attachment = false,
			open_in_zotero = false,
		})
	end,
}
