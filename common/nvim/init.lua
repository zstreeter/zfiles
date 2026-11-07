-- Load order matters: options/keymaps/autocommands run before lazy bootstraps,
-- so plugin specs can read final globals; colorscheme + lsp run after lazy
-- registers specs so theme/LSP enable can reference loaded plugins.
local modules = {
	"config.options",
	"config.keymaps",
	"config.autocommands",
	"config.lazy", -- ↑ pre-lazy   ↓ post-lazy
	"config.colorscheme",
	"config.lsp",
}

for _, mod in ipairs(modules) do
	require(mod)
end

-- Background services with an explicit lifecycle (stop on VimLeavePre).
-- also feeds the dashboard counts; polls are async, so start almost at once
require("config.mail-notify").start({ accounts = { "gmail", "work" }, initial_delay_ms = 200 })
require("config.mail-browse").setup() -- :Mail and <leader>m
