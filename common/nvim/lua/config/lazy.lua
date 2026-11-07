-- Silence the "import order" warning for custom configs
vim.g.lazyvim_check_order = false

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.uv.fs_stat(lazypath) then
	vim.fn.system({
		"git",
		"clone",
		"--filter=blob:none",
		"https://github.com/folke/lazy.nvim.git",
		"--branch=stable",
		lazypath,
	})
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
	spec = {
		{ import = "plugins" }, -- root: editor + foundational (snacks, which-key, etc.)
		{ import = "plugins.ai" }, -- sidekick, opencode, pi
		{ import = "plugins.lsp" }, -- mason, lspconfig, conform, nvim-lint, lazydev
		{ import = "plugins.lang" }, -- per-language plugins (unreal, latex, obsidian, …)
		{ import = "plugins.ui" }, -- visual: theme, transparent, lualine, …
	},
	install = {
		colorscheme = { "default" },
	},
	ui = {
		border = "rounded",
	},
	change_detection = {
		enabled = true,
		notify = false,
	},
})
