-- nvim-lspconfig is used purely as a DATA SOURCE: its bundled lsp/ directory
-- provides the base config for every server in config/servers.lua; this repo's
-- after/lsp/*.lua merge on top (after/ so they win the rtp merge).
-- No setup() call exists or is needed — vim.lsp.enable() (config/lsp.lua)
-- resolves configs from the runtimepath at FileType time.
-- Loaded eagerly so its lsp/ dir is on the rtp before any buffer opens.
return {
	"neovim/nvim-lspconfig",
	lazy = false,
}
