return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = {
		{
			"m",
			function()
				require("harpoon"):list():add()
				vim.notify("󱡅  marked file")
			end,
			desc = "Harpoon: mark file",
		},
		{
			"<S-m>",
			function()
				local harpoon = require("harpoon")
				harpoon.ui:toggle_quick_menu(harpoon:list())
			end,
			desc = "Harpoon: toggle quick menu",
		},
	},
	config = function()
		require("harpoon"):setup()
	end,
}
