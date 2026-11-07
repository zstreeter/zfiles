-- lua/plugins/cdb.lua
return {
	"JBITools/cdb.nvim",
	cond = vim.fn.isdirectory(vim.fn.stdpath("data") .. "/lazy/cdb.nvim") == 1,
	ft = { "cdb", "cql" },
	config = function()
		require("cdb").setup({
			server = {
				host = "localhost",
				port = 9010,
			},
		})
	end,
}
