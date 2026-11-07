# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

Personal Neovim configuration: lazy.nvim plugin manager, native LSP
(`vim.lsp.enable`), snacks.nvim pickers, and heavy personal tooling (himalaya
mail, obsidian/zotero/quarto research stack, omarchy theme integration, AI
CLIs). See `CONTEXT.md` for the domain glossary — use its module names.

## Architecture

```
init.lua                  # Entry point — loads config/* in order, starts mail-notify
lua/config/
  ├── options.lua         # vim.opt settings
  ├── keymaps.lua         # Global keymaps (leader=space, localleader=\)
  ├── keys.lua            # Keymap registry: which-key groups + prefix ownership
  ├── autocommands.lua    # Autocmds (highlight yank, trim whitespace, mkdir)
  ├── lazy.lua            # lazy.nvim bootstrap (imports lua/plugins/**)
  ├── colorscheme.lua     # Applies theme via the omarchy adapter
  ├── omarchy.lua         # Omarchy theme adapter: get_colorscheme() → string|nil
  ├── herdr.lua           # herdr adapter: sidekick session backend, AI CLIs in real panes
  ├── icons.lua           # Single source of truth for glyphs (kind, diagnostics)
  ├── mail-notify.lua     # Background mail poller: start()/stop(), injectable runner
  ├── servers.lua         # LSP server + mason tool lists (the LSP data interface)
  └── lsp.lua             # LSP module: capabilities, diagnostics, LspAttach keymaps
after/lsp/                # Per-server overrides — PURE settings tables, no require(); after/ so they beat nvim-lspconfig
lua/plugins/              # lazy.nvim specs (subdirs: ai/, lang/, lsp/, ui/)
  └── theme.lua           # Quattro symlink into active Omarchy state — do not edit
tests/smoke.{sh,lua}      # Headless boot + assertion suite
```

## Rules that keep the architecture honest

- **Glyphs** live only in `lua/config/icons.lua` (smoke test enforces).
- **`after/lsp/*.lua` stay pure data** — no `require()` of plugins (smoke enforces).
- **which-key group labels** live only in `lua/config/keys.lua`; plugin files
  own their handlers/`keys={}` specs.
- **Goto pickers** (`gd/gD/gr/gI/gy`) are global maps owned by
  `lua/plugins/snacks.lua`; `config/lsp.lua` must not duplicate them.
- **Commenting** is built-in `gc`/`gcc` (`<leader>/` in keymaps.lua);
  ts-context-commentstring keeps JSX/TSX commentstrings correct.
- **Interactive shells and TUIs** open through `config.herdr.open_pane()`;
  embedded Neovim/Snacks terminals are forbidden (smoke enforces).
- **Navigation** is system-wide `SUPER+hjkl`, arbitrated by zfiles across
  Neovim splits, Herdr panes, and windows; do not add local `<m-hjkl>` maps.
- Run `tests/smoke.sh` after structural changes; add a check when you add a
  seam. It must pass before committing.

## Common Development Tasks

### Adding a new plugin
1. Create a spec file in `lua/plugins/` (or the fitting subdir: `ai/`,
   `lang/`, `lsp/`, `ui/`) — the directory is auto-imported by lazy.nvim
2. If it binds a new `<leader>` prefix, register the group in
   `lua/config/keys.lua`
3. Lazy.nvim auto-installs on next startup

### Modifying core settings
- Editor options: `lua/config/options.lua`
- Key mappings: `lua/config/keymaps.lua` (global) / plugin specs (plugin-local)
- LSP servers: `lua/config/servers.lua` (list) + `after/lsp/<name>.lua` (settings)

### Configuration Flow
1. `init.lua`: options → keymaps → autocommands → lazy → colorscheme → lsp,
   then `mail-notify.start()`
2. lazy.nvim imports every spec under `lua/plugins/**`
3. Theme: `colorscheme.lua` asks the omarchy adapter, falls back to catppuccin

## Important Notes

- `tests/smoke.sh` is the test infrastructure — headless, no framework
- The configuration auto-creates directories when saving files
- On save, conform formats and trims trailing whitespace — except markdown/quarto, which are never rewritten on save (`<leader>cf` formats manually)
- Icon glyphs may not survive AI text generation — edit `icons.lua` glyphs
  manually in nvim, or copy bytes with sed
