-- Keymap registry: the single place that answers "what lives under a prefix".
-- which-key.lua consumes M.groups; plugin files own their handlers (lazy
-- `keys={}` specs stay in plugin files so lazy-loading keeps working).
--
-- Prefix ownership (where the handlers live):
--   <leader>a   ai/{opencode,pi,sidekick}.lua
--   <leader>b   snacks.lua (bufdelete)
--   <leader>c   lsp.lua (action, rename), lsp/{conform,nvim-lint}.lua (format, lint),
--               snacks.lua (rename file)
--   <leader>f   snacks.lua (pickers), lang/zotero-pdf.lua (<leader>fz)
--   <leader>g   snacks.lua (git pickers), keymaps.lua (lazygit in Herdr)
--   <leader>m   config/mail-browse.lua (setup() from init.lua; no plugin)
--   <leader>o   lang/obsidian.lua
--   <leader>q   bqf.lua (quickfix)
--   <leader>Q   lang/quarto.lua (also registers its own bindings via wk.add)
--   <leader>s   snacks.lua (symbols/grep)
--   <leader>u   snacks.lua (toggles)
--   m / <S-m>   harpoon.lua — deliberately shadows the built-in mark command
--
-- ponytail: groups-only registry; full binding centralization would fight
-- lazy.nvim's keys={} lazy-loading. Revisit if collisions keep appearing.
local M = {}

M.groups = {
	{ "<leader>a", group = "AI" },
	{ "<leader>b", group = "buffer" },
	{ "<leader>c", group = "code/LSP" },
	{ "<leader>f", group = "find" },
	{ "<leader>g", group = "git" },
	{ "<leader>m", group = "mail" },
	{ "<leader>o", group = "obsidian" },
	{ "<leader>s", group = "search/symbols" },
	{ "<leader>u", group = "ui/toggles" },
	{ "<leader>Q", group = "quarto", icon = "" },
	{ "<leader>Qm", group = "molten", icon = "" },
	{ "<leader>q", group = "quickfix" },
}

-- Collision detection at the interface: duplicate prefixes fail loudly at boot.
local seen = {}
for _, g in ipairs(M.groups) do
	if seen[g[1]] then
		error("config.keys: duplicate group prefix " .. g[1])
	end
	seen[g[1]] = true
end

return M
