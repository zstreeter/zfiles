-- Replaces zadirion/Unreal.nvim (unmaintained since 2021).
--
-- UnrealDev.nvim is a meta-plugin: it wraps the Unreal suite (UEP/UEA/UBT/UCM/
-- ULG/USH/UNX/UDB/USX) under a single `:UDEV` command. Each sub-plugin can be
-- removed from `dependencies` if you don't need it.
--
-- One-time setup required:
--   :checkhealth UnrealDev          -- verify external deps (`fd`, `rg`, `cargo`)
--   UNL.nvim auto-builds via `cargo build --release` on install.
return {
	"taku25/UnrealDev.nvim",
	-- Only inside an Unreal project: otherwise every C/C++ file loaded the whole suite.
	cond = vim.fs.root(vim.fn.getcwd(), function(name)
		return name:match("%.uproject$") ~= nil
	end) ~= nil,
	ft = { "cpp", "c", "h", "hpp", "ush", "usf", "verse" },
	cmd = "UDEV",
	dependencies = {
		{
			"taku25/UNL.nvim",
			build = "cargo build --release --manifest-path scanner/Cargo.toml",
		},
		"taku25/UEP.nvim", -- project explorer
		"taku25/UEA.nvim", -- asset / blueprint inspector
		"taku25/UBT.nvim", -- build tool
		"taku25/UCM.nvim", -- class manager
		"taku25/ULG.nvim", -- log viewer
		"taku25/USH.nvim", -- shell
		{
			"taku25/UNX.nvim",
			dependencies = { "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
		},
		"taku25/UDB.nvim", -- debug
		"taku25/USX.nvim", -- syntax highlighting
	},
	opts = {
		setup_modules = {
			UBT = true,
			UEP = true,
			ULG = true,
			USH = true,
			UCM = true,
			UEA = true,
			UNX = true,
		},
	},
}
