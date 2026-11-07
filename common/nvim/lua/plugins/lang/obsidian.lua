-- A file belongs to a vault iff an ancestor holds `.obsidian/` -- that is what makes a
-- vault, so no path is hardcoded and no vault list is needed. The plugin loads only for
-- such files (other markdown never pays its ~0.5 s setup), and its single dynamic
-- workspace is always the current buffer's vault.
local function vault_root(buf)
	return vim.fs.root(buf or 0, ".obsidian")
end

return {
	"epwalsh/obsidian.nvim",
	version = "*",
	lazy = true,
	dependencies = { "nvim-lua/plenary.nvim" },
	init = function()
		vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile" }, {
			pattern = { "*.md", "*.qmd" },
			callback = function(ev)
				if vault_root(ev.buf) then
					require("lazy").load({ plugins = { "obsidian.nvim" } })
					return true -- loaded; drop the autocmd
				end
			end,
		})
	end,
	opts = {
		workspaces = {
			{
				name = "vault",
				path = function()
					return vault_root() or vim.fs.dirname(vim.api.nvim_buf_get_name(0))
				end,
			},
		},
		notes_subdir = "notes",
		new_notes_location = "notes_subdir",
		-- zotcite handles @citekey completion against zotero.sqlite
		completion = { nvim_cmp = false, blink = false, min_chars = 2 },
		picker = { name = "snacks.pick" },
		-- markview handles in-buffer rendering
		ui = { enable = false },
		attachments = { img_folder = "assets" },
	},
	keys = {
		{ "<leader>on", "<cmd>ObsidianNew<cr>", desc = "Obsidian: New note" },
		{ "<leader>oo", "<cmd>ObsidianQuickSwitch<cr>", desc = "Obsidian: Quick switch" },
		{ "<leader>ob", "<cmd>ObsidianBacklinks<cr>", desc = "Obsidian: Backlinks" },
		{ "<leader>ot", "<cmd>ObsidianTags<cr>", desc = "Obsidian: Tags" },
		{ "<leader>og", "<cmd>ObsidianSearch<cr>", desc = "Obsidian: Grep" },
		{ "<leader>of", "<cmd>ObsidianFollowLink<cr>", desc = "Obsidian: Follow link" },
	},
}
