-- Commenting is the built-in gc/gcc (Neovim 0.10+); Comment.nvim was a
-- 65-line pass-through around it and silently stole <leader>/ from
-- keymaps.lua. ts-context-commentstring stays: its autocmd keeps
-- 'commentstring' correct inside JSX/TSX so built-in gc comments the
-- right syntax at the cursor.
return {
	"JoosepAlviste/nvim-ts-context-commentstring",
	event = "VeryLazy",
	opts = {},
}
