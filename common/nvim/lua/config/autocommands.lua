local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

local general = augroup("General", { clear = true })

autocmd("VimResized", {
	group = general,
	callback = function()
		local tab = vim.fn.tabpagenr()
		vim.cmd("tabdo wincmd =")
		vim.cmd("tabnext " .. tab) -- tabdo leaves you on the last tab
	end,
	desc = "Auto-resize splits across all tabs",
})

-- Not in snacks.lua's init: lang/zotero-pdf.lua's snacks fragment defines its
-- own init, and lazy keeps only one.
autocmd("User", {
	group = general,
	pattern = "MailUnread", -- config/mail-notify: an unread count changed
	callback = function()
		if package.loaded["snacks.dashboard"] then
			Snacks.dashboard.update()
		end
	end,
	desc = "Redraw dashboard mail counts",
})

autocmd("BufReadPost", {
	group = general,
	callback = function()
		local mark = vim.api.nvim_buf_get_mark(0, '"')
		if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(0) then
			vim.api.nvim_win_set_cursor(0, mark)
		end
	end,
	desc = "Return to last edit position",
})

autocmd("BufWritePre", {
	group = general,
	callback = function(event)
		if event.match:match("^%w%w+://") then
			return
		end
		local file = vim.uv.fs_realpath(event.match) or event.match
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":p:h"), "p")
	end,
	desc = "Auto-create directories on save",
})

autocmd("BufWinEnter", {
	group = general,
	callback = function()
		vim.opt_local.formatoptions:remove({ "c", "r", "o" })
	end,
	desc = "Disable auto-comment continuation",
})

autocmd("FileType", {
	group = general,
	pattern = { "qf", "git", "help", "man", "lspinfo", "oil", "query", "checkhealth" },
	callback = function(event)
		vim.bo[event.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
	end,
	desc = "Quick-close transient buffers with q",
})

autocmd("CmdWinEnter", {
	group = general,
	command = "quit",
	desc = "Disable command-line window",
})

autocmd("FocusGained", {
	group = general,
	command = "checktime",
	desc = "Reload buffers changed externally",
})

autocmd({ "VimEnter", "DirChanged" }, {
	group = general,
	callback = function()
		vim.opt.titlestring = vim.fn.getcwd():match("([^/]+)$")
	end,
	desc = "Set window title to project name",
})

autocmd("TextYankPost", {
	group = general,
	callback = function()
		vim.hl.on_yank({ higroup = "Visual", timeout = 40 })
	end,
	desc = "Highlight on yank",
})

autocmd("FileType", {
	group = general,
	pattern = { "gitcommit", "markdown", "quarto", "tex", "NeogitCommitMessage" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
	end,
	desc = "Wrap and spell-check prose buffers",
})
