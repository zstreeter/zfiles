return {
	"stevearc/oil.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	lazy = false, -- must own directory buffers from startup (`nvim <dir>`)
	keys = {
		{ "-", "<cmd>Oil --float<cr>", desc = "Open parent directory" },
	},
	opts = {
		default_file_explorer = true,
		float = {
			max_height = 20,
			max_width = 60,
		},
		view_options = {
			show_hidden = true,
		},
	},
}
