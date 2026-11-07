# Domain glossary

Terms with a specific meaning in this config. Architecture reviews and
refactors should use these names.

- **Icons module** (`lua/config/icons.lua`) — single source of truth for every
  glyph: LSP `kind` symbols and `diagnostics` severity signs. All four glyph
  consumers (blink kind_icons, navic breadcrumbs, diagnostic sign column, lualine)
  require it; hand-copied glyph tables are forbidden.
- **LSP module** — `lua/config/lsp.lua` owns the seam: capabilities (computed
  once, blink-extended), diagnostics display, LspAttach keymaps, and
  `vim.lsp.enable()` over the server list. `lua/config/servers.lua` is its
  data interface (server + tool names). `after/lsp/*.lua` are adapters: pure
  settings tables, no `require`s, merged over nvim-lspconfig's bundled `lsp/`
  configs (they must live in `after/`: a plain `lsp/` dir sorts before the
  plugin on the rtp and is silently overridden).
- **Keymap registry** (`lua/config/keys.lua`) — single source for which-key
  group labels and prefix ownership; errors at boot on duplicate prefixes.
  Plugin handlers stay in plugin files (lazy `keys={}` keeps lazy-loading);
  full binding centralization was deliberately not done.
- **Omarchy theme adapter** (`lua/config/omarchy.lua`) — the only code that
  knows omarchy hands us a LazyVim-shaped spec via the
  `lua/plugins/theme.lua` symlink. Interface:
  `get_colorscheme() → string|nil` (validated against available colorschemes,
  repo-ish names normalized). `colorscheme.lua` consumes it; catppuccin is
  the non-omarchy fallback.
- **Mail notify module** (`lua/config/mail-notify.lua`) — background new-mail
  polling with an explicit lifecycle: `start(opts)` / `stop()`, started
  eagerly from init.lua, stopped on VimLeavePre. The job runner is
  injectable. Counts come from IMAP STATUS (exact, ~1 s even for huge
  inboxes); read side is `unread(account)` / `accounts()`, and a
  `User MailUnread` event fires on change (the dashboard's per-account rows
  redraw on it, hook in config/autocommands.lua).
  Distinct from the mail browse module, which owns `:Mail` and `<leader>m`.
- **Mail compose module** (`lua/config/mail-compose.lua`) — compose, reply,
  reply-all, forward and draft resume as a plain `mail` buffer (header block +
  body); `:w` asks Send / Save draft / Cancel. himalaya's flag composer builds
  the MIME; the module only restores display names and adds threading headers,
  then pipes to `message send` / `message add`. `M.himalaya` is the single CLI
  seam (replaced in tests).
- **Mail browse module** (`lua/config/mail-browse.lua`) — `:Mail [account]`
  lists a mailbox in the current window (normal windows, no floats, so window
  navigation works); `<CR>` reads into a reused split below. Paging, search,
  mailbox/account switching, move/delete/attachments; compose keys hand off to
  the compose module. No plugin: `setup()` runs from init.lua.
- **Smoke suite** (`tests/smoke.lua` via `tests/smoke.sh`) — headless boot +
  assertion suite; every structural refactor adds checks here and must pass
  before commit.
