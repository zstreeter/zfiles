return {
	"lewis6991/gitsigns.nvim",
	event = "BufReadPre",
	cmd = "Gitsigns",
	opts = {
		signs = {
			add = { text = "┃" },
			change = { text = "┋" },
			delete = { text = "" },
			topdelete = { text = "" },
			changedelete = { text = "┃" },
		},
		watch_gitdir = {
			interval = 1000,
			follow_files = true,
		},
		attach_to_untracked = true,
		current_line_blame_formatter = "<author>, <author_time:%Y-%m-%d> - <summary>",
		update_debounce = 200,
		max_file_length = 40000,
		preview_config = {
			border = "rounded",
			style = "minimal",
			relative = "cursor",
			row = 0,
			col = 1,
		},
	},
}
