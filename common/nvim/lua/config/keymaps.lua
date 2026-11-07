local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

keymap("n", "<Space>", "", opts)
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

keymap("n", "<C-i>", "<C-i>", opts)

keymap("n", "<leader>w", "<cmd>w<cr>", opts)

keymap("n", "<m-tab>", "<c-6>", opts)

local open_shell = function()
	require("config.herdr").open_pane()
end
keymap("n", "<c-/>", open_shell, { desc = "Open Herdr Pane" })
keymap("n", "<c-_>", open_shell, { desc = "Open Herdr Pane" })
keymap("n", "<leader>gg", function()
	require("config.herdr").open_pane({ "lazygit" })
end, { desc = "Lazygit in Herdr Pane" })

keymap("n", "n", "nzz", opts)
keymap("n", "N", "Nzz", opts)
keymap("n", "*", "*zz", opts)
keymap("n", "#", "#zz", opts)
keymap("n", "g*", "g*zz", opts)
keymap("n", "g#", "g#zz", opts)

-- Stay in indent mode
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

keymap("x", "p", "P") -- replace selection without clobbering the register
keymap("n", "x", '"_x')

-- Comment toggle using built-in gc (Neovim 0.12)
keymap("n", "<leader>/", "gcc", { remap = true, desc = "Comment line" })
keymap("x", "<leader>/", "gc", { remap = true, desc = "Comment selection" })

vim.cmd([[:amenu 10.100 mousemenu.Goto\ Definition <cmd>lua vim.lsp.buf.definition()<CR>]])
vim.cmd([[:amenu 10.110 mousemenu.References <cmd>lua vim.lsp.buf.references()<CR>]])
-- vim.cmd [[:amenu 10.120 mousemenu.-sep- *]]

vim.keymap.set("n", "<RightMouse>", "<cmd>:popup mousemenu<CR>")
vim.keymap.set("n", "<Tab>", "<cmd>:popup mousemenu<CR>")

-- more good
-- keymap({ "n", "o", "x" }, "<s-h>", "^", opts)
-- keymap({ "n", "o", "x" }, "<s-l>", "g_", opts)

-- tailwind bearable to work with
-- Display lines only without a count, so `5j` still matches relativenumber.
keymap({ "n", "x" }, "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true })
keymap({ "n", "x" }, "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true })
-- keymap("n", "<leader>w", ":lua vim.wo.wrap = not vim.wo.wrap<CR>", opts)

-- Tab navigation
keymap("n", "<s-tab>", "<cmd>tabnew %<cr>", opts)
keymap({ "n" }, "<s-h>", "<cmd>tabp<cr>", opts)
keymap({ "n" }, "<s-l>", "<cmd>tabn<cr>", opts)
