# Research Workflow

How Zotero, Sioyek, Obsidian, Neovim, Quarto, and the blog fit together — and the
day-to-day commands that move work through them.

## The pieces

| Tool | Role | Source of truth for… |
|------|------|----------------------|
| **Zotero** + Better BibTeX | Reference manager, auto-organises PDFs via Zotmove | citations + PDFs (`~/Zotero/zotero.sqlite`, `~/Zotero/Zotero-Library/`) |
| **Sioyek** | PDF reader, default for `application/pdf` | — |
| **Obsidian** | Per-project vault GUI: literature notes, `[[wikilinks]]`, plugin ecosystem | each vault under `~/research/<project>/` |
| **Neovim** | Primary editor — drafts, notes, citations | — |
| **Quarto** | Renders `.qmd` to HTML/PDF; powers the blog | `_quarto.yml` |
| **Sidekick (Claude)** | AI CLI integrated into nvim | — |
| **Blog** | Quarto website at `~/Documents/Repos/zstreeter.github.io/` → `zstreeter.github.io` | published `posts/` |

Citations resolve directly from `~/Zotero/zotero.sqlite` via the `zotcite` nvim
plugin — the per-vault `references.bib` exported by Better BibTeX is a *secondary*
source used by Obsidian's Citations plugin and by standalone LaTeX docs.

## Directory layout

```
~/Zotero/                          # Zotero data — don't touch directly
├── zotero.sqlite                  # citation database (zotcite reads this)
└── Zotero-Library/                # PDFs (Zotmove organises here)

~/research/                        # all research vaults live here
├── README.md                      # this file
└── <project>/                     # one Obsidian vault per project
    ├── .obsidian/                 # vault config
    ├── literature/                # auto-generated lit notes (one per Zotero item)
    ├── notes/                     # freeform research notes
    ├── drafts/                    # .qmd drafts in progress
    ├── assets/                    # images / attachments
    ├── references.bib             # Better BibTeX auto-export target
    ├── _quarto.yml                # local Quarto config (renders drafts/)
    └── AGENTS.md                  # vault-specific guidance for opencode / Claude Code

~/Documents/Repos/zstreeter.github.io/   # the blog — published Quarto site
└── posts/YYYY-MM-DD-slug/index.qmd      # one folder per post
```

## Starting a new project

```sh
new-research-project my-topic           # creates ~/research/my-topic/
```

Then, **once per vault**:

1. Open the new folder in Obsidian → **Settings → Community plugins → Browse** and install:
   - **Zotero Integration** (mgmeyers) — pulls Zotero items into `literature/` with annotations
   - **Citations** (hans) — `@citekey` autocomplete from `references.bib`
   - **Dataview** — query notes by tag/field
   - **Templater** — note templates
2. In Zotero: **Edit → Preferences → Better BibTeX → Automatic export** → target this vault's
   `references.bib` (Format: **Better BibLaTeX**, On change). This is the only step that can't be scripted.

## Daily workflow

### Capture a paper
Add to Zotero (browser connector, drag-drop, etc.). Better BibTeX assigns a key like
`smith2024deep`; Zotmove files the PDF under `~/Zotero/Zotero-Library/`. Done.

### Read a PDF
- From nvim: `<leader>fz` → fuzzy-pick a PDF → opens in Sioyek.
- From Zotero: double-click an item; Zotero opens it in Sioyek (since `application/pdf`
  default = `sioyek.desktop`).

### Make a literature note
In Obsidian, run **Zotero Integration: Insert literature note**. It pulls metadata +
annotations into `literature/@smith2024deep.md` with a `zotero://` link back.

### Take research notes
In `notes/`, write freeform markdown. Cross-link to literature with `[[@smith2024deep]]`.
Use `:ObsidianBacklinks` (or `<leader>ob`) to see what links *to* a note.

### Draft a blog post
```sh
nvim ~/research/my-topic/drafts/2026-04-19-my-post.qmd
```
Frontmatter:
```yaml
---
title: "Post title"
author: "Zachary Streeter"
date: 2026-04-19
categories: [my-topic, deep-learning]
description: "Brief summary."
---
```
The `categories:` field is what groups posts on the blog by project. Live preview:
`quarto preview` from the vault root.

### Cite while writing
Type `@` in any `.md` / `.qmd` / `.tex` buffer — `zotcite` autocompletes from
`zotero.sqlite`. Press `<C-x>` to insert. Works regardless of vault.

### Use an AI agent

Both Claude Code and opencode work in this workspace. Each vault ships with an
`AGENTS.md` (auto-discovered by both agents) that gives them vault-specific guidance —
file layout, citation key format, publishing rules, what *not* to touch.

- `<leader>ac` — toggle **Claude** in a side pane (Sidekick).
- `<leader>ao` — toggle **opencode** in a side pane.
- `<leader>aa` — generic CLI picker (lists every AI CLI on PATH).
- `<leader>as` (visual) — send selection to the active agent.
- `<leader>ap` — pick a saved prompt.

In the agent prompt, use `@path/to/file.md` to add files as context. Plain `.md`
and `.qmd` work identically. Common asks the AGENTS.md primes for:

- Summarise `literature/@key.md` (read the PDF if needed)
- Draft a section in `drafts/<file>.qmd` from cited notes
- Review a draft for frontmatter completeness + citation resolvability

### Publish a draft
```sh
publish-post ~/research/my-topic/drafts/2026-04-19-my-post.qmd
```
Copies the draft + adjacent images into
`~/Documents/Repos/zstreeter.github.io/posts/2026-04-19-my-post/index.qmd`.
Preview the full site:
```sh
cd ~/Documents/Repos/zstreeter.github.io
quarto preview
```
Deploy:
```sh
quarto publish gh-pages
```

## Key bindings (nvim)

| Keys           | Action                                   |
|----------------|------------------------------------------|
| `<leader>fz`   | Find Zotero PDF → open in Sioyek         |
| `<leader>oo`   | Obsidian quick switch (notes)            |
| `<leader>on`   | Obsidian new note                        |
| `<leader>ob`   | Show backlinks to current note           |
| `<leader>og`   | Grep across vault                        |
| `<leader>of`   | Follow `[[wikilink]]` under cursor       |
| `<leader>ot`   | Browse tags                              |
| `<leader>ow`   | Switch Obsidian workspace                |
| `<leader>Qp`   | Quarto preview                           |
| `<leader>Qc`   | Quarto: run current code cell            |
| `<leader>QA`   | Quarto: run all cells                    |
| `<leader>ac`   | Toggle Claude pane                       |
| `<leader>ao`   | Toggle opencode pane                     |
| `<leader>aa`   | Pick any AI CLI on PATH                  |
| `<leader>as`   | Sidekick: send selection to AI           |
| `<leader>ap`   | Sidekick: pick saved prompt              |

## LaTeX and math

- **Inline math** in `.qmd` / `.md` / `.tex`: `$E = mc^2$`. Renders in Quarto preview,
  Obsidian preview (MathJax), and PDF output.
- **Display math**: `$$ \int_0^\infty e^{-x} dx = 1 $$`.
- **Standalone `.tex` documents**: vimtex compiles on save; sioyek opens the PDF and
  syncs cursor position via SyncTeX (`<leader>lv` for forward search).
- **`.qmd` to PDF**: add `format: pdf` to frontmatter; pandoc + LaTeX renders it.
- **BibTeX `\cite{key}`** in `.tex` resolves against the vault's `references.bib`.

## Theming

Sioyek's colors track the active Omarchy theme — switching themes runs the
`~/.config/omarchy/hooks/theme-set` hook, which rewrites the `# zfiles-theme` block in
`~/.config/sioyek/prefs_user.config`. Edit your non-color sioyek prefs *above* that
marker; everything below is auto-generated.

## Troubleshooting

| Symptom | Check |
|---------|-------|
| `@citekey` autocomplete missing | `~/Zotero/zotero.sqlite` exists and `zotcite` plugin loaded for buffer's filetype |
| BBT `references.bib` stale | Zotero → BBT → Auto-Export → set "On change" |
| Sioyek colors look wrong | Re-run hook: `~/.config/omarchy/hooks/theme-set "$(basename "$(readlink -f ~/.config/omarchy/current)")"` |
| Blog post missing after publish | Did you `quarto publish gh-pages`? The `publish-post` helper only copies the file. |
| `[[wikilink]]` won't follow | Buffer must be inside a vault under `~/research/`; obsidian.nvim auto-detects via the workspace path |

## Pieces installed by zfiles

`bootstrap.sh` installs the toolchain (sioyek, quarto, texlive-meta, obsidian,
ripgrep-all, jupyter), stows configs (`sioyek/`, `scripts/`, etc.), creates
`~/research/`, and prints these manual steps. See `~/Documents/Repos/zfiles/README.md`
for the overlay's full docs.
