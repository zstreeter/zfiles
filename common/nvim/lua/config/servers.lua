-- The server/tool interface of the LSP module. Two consumers:
--   config/lsp.lua      enables lsp_servers via vim.lsp.enable()
--   plugins/lsp/mason.lua installs both lists via mason-tool-installer
-- Two vocabularies, deliberately: lsp_servers are LSP-client names (resolved
-- from nvim-lspconfig's bundled lsp/ dir, then this repo's after/lsp/*.lua on top);
-- mason-tool-installer accepts those same names only because mason-lspconfig
-- is installed to provide the name mapping. formatters_and_linters are mason
-- package names. Formatters NOT listed here (gofmt, goimports, rustfmt) ship
-- with their language toolchains — conform.lua may reference more than mason
-- installs.
local M = {}

-- Add back if needed: css_variables, cssmodules_ls, lemminx (XML), nginx_language_server.
M.lsp_servers = {
	"ts_ls",
	"lua_ls",
	"tailwindcss",
	"eslint",
	"rust_analyzer",
	"gopls",
	"html",
	"cssls",
	"basedpyright",
	"bashls",
	"dockerls",
	"jsonls",
	"marksman",
	"taplo",
	"yamlls",
}

M.formatters_and_linters = {
	"prettier",
	"stylua",
	"black",
	"isort",
	"pylint",
	"shellcheck",
	"shfmt",
}

return M
