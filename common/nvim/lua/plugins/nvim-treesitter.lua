-- nvim-treesitter `main` branch. The old `master` API (nvim-treesitter.configs,
-- ensure_installed, highlight/indent modules) is gone: `main` installs parsers
-- imperatively and leaves highlighting to core's `vim.treesitter.start`.
--
-- `main` shells out to the `tree-sitter` CLI to build every parser, so that
-- binary is a hard prerequisite. Not via mason: its prebuilt CLI needs GLIBC
-- 2.39 and this box is on 2.35. `cargo install tree-sitter-cli` builds against
-- the local libc and lands in ~/.cargo/bin.
local MAX_FILESIZE = 100 * 1024 -- 100 KB

-- ponytail: one flat list, no per-language opts — nothing here needs them yet.
local PARSERS = {
	"bash",
	"c",
	"clingo", -- potassco grammar, registered in lang/clingo.lua
	"cpp",
	"css",
	"dockerfile",
	"gitignore",
	"go",
	"graphql",
	"html",
	"javascript",
	"json",
	"latex", -- markdown_inline injects `latex` into $...$; markview renders it
	"lua",
	"markdown",
	"markdown_inline",
	"prisma",
	"python",
	"query",
	"rust",
	"svelte",
	"tsx",
	"typescript",
	"vim",
	"vimdoc",
	"yaml",
}

--- Big files stay on regex syntax: parsing them blocks the UI.
---@param buf integer
local function too_big(buf)
	local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(buf))
	return ok and stats and stats.size > MAX_FILESIZE
end

return {
	"nvim-treesitter/nvim-treesitter",
	branch = "main",
	build = ":TSUpdate",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		require("nvim-treesitter").setup()

		-- Installing is async and skips parsers already present (silently, in
		-- install_lang), so this is safe on every startup — it only does work
		-- on a new machine or when PARSERS grows.
		require("nvim-treesitter").install(PARSERS)

		-- `main` has no highlight module — core starts per buffer. Errors are
		-- expected for any filetype whose parser isn't installed, so this must
		-- stay quiet rather than notifying on every unhandled filetype.
		vim.api.nvim_create_autocmd("FileType", {
			desc = "Start treesitter highlighting when a parser exists",
			callback = function(ev)
				if too_big(ev.buf) then
					return
				end
				pcall(vim.treesitter.start, ev.buf)
			end,
		})
	end,
}
