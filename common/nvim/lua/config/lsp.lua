-- Enable LSP servers (list defined in config/servers.lua)
local servers = require("config.servers")
local icons = require("config.icons")
vim.lsp.enable(servers.lsp_servers)

-- Configure diagnostic display with custom signs
vim.diagnostic.config({
	float = {
		focusable = true,
		style = "minimal",
		border = "rounded",
		source = true, -- Show source in diagnostic popup window
		header = "",
		prefix = "",
	},
	virtual_text = false,
	virtual_lines = false,
	signs = {
		text = {
			[vim.diagnostic.severity.ERROR] = icons.diagnostics.Error,
			[vim.diagnostic.severity.WARN] = icons.diagnostics.Warn,
			[vim.diagnostic.severity.HINT] = icons.diagnostics.Hint,
			[vim.diagnostic.severity.INFO] = icons.diagnostics.Info,
		},
	},
	underline = true,
	update_in_insert = false,
	severity_sort = true,
	jump = { float = true }, -- built-in ]d / [d open the diagnostic float
})

-- Enable inlay hints
vim.lsp.inlay_hint.enable(false)

vim.api.nvim_create_autocmd("LspAttach", {
	group = vim.api.nvim_create_augroup("UserLspConfig", {}),
	callback = function(ev)
		-- Goto/reference pickers (gd/gD/gr/gI/gy) are global maps owned by
		-- snacks.lua. K (hover) and ]d/[d (diagnostic jumps, float via
		-- diagnostic.config jump) are Neovim built-ins. Code actions live under
		-- <leader>c with format/lint (conform.lua, nvim-lint.lua).
		local function map(mode, lhs, rhs, desc)
			vim.keymap.set(mode, lhs, rhs, { buffer = ev.buf, silent = true, desc = desc })
		end
		map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "Code action")
		map("n", "<leader>cr", vim.lsp.buf.rename, "Rename symbol")
		map("n", "gl", vim.diagnostic.open_float, "Line diagnostics")
	end,
})
