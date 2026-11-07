-- Clingo / ASP, straight from potassco's official tree-sitter grammar (no
-- wrapper plugin). The parser itself is installed with the others via
-- PARSERS in nvim-treesitter.lua; `queries` makes nvim-treesitter install the
-- grammar's highlights/indents/injections/textobjects too. *.cl is
-- deliberately absent: core detects it as OpenCL or Lisp by content.
return {
	"nvim-treesitter/nvim-treesitter",
	optional = true,
	init = function()
		vim.filetype.add({ extension = { lp = "clingo", asp = "clingo" } })
		vim.api.nvim_create_autocmd("User", {
			pattern = "TSUpdate",
			callback = function()
				require("nvim-treesitter.parsers").clingo = {
					install_info = { url = "https://github.com/potassco/tree-sitter-clingo", queries = "queries" },
				}
			end,
		})
		vim.api.nvim_create_autocmd("FileType", {
			pattern = "clingo",
			callback = function(ev)
				vim.bo[ev.buf].commentstring = "% %s"
				vim.bo[ev.buf].comments = ":%"
			end,
		})
	end,
}
