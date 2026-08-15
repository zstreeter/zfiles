# Agent guidance for this research vault

Read by both **opencode** and **Claude Code** as system instructions when invoked
from this directory. Keep it short and concrete — agents waste tokens on long preambles.

## Layout

- `literature/` — one note per Zotero item, filename `@<citekey>.md`. Auto-generated
  by the Obsidian Zotero Integration plugin. **Don't edit metadata fields here**;
  edit in Zotero and re-sync.
- `notes/` — freeform research notes. Cross-reference literature with `[[@citekey]]`.
- `drafts/` — `.qmd` blog drafts in progress. Each draft must have YAML frontmatter:
  ```yaml
  ---
  title: "..."
  author: "Zachary Streeter"
  date: YYYY-MM-DD
  categories: [<project-name>, <topic>, ...]
  description: "..."
  ---
  ```
  The first category should match the vault name; that's how the blog groups posts.
- `assets/` — images attached to notes/drafts.
- `references.bib` — auto-exported by Better BibTeX. **Read-only; never edit by hand.**

## Citations

- In `.qmd` / `.md` / `.tex`: cite as `@smith2024deep`. Resolved by `zotcite` directly
  from `~/Zotero/zotero.sqlite` — no `.bib` lookup needed for nvim users.
- For pure LaTeX (`\cite{}`), the BibTeX key matches the `@` key.
- Citation key format is `auth.lower + shorttitle(3, 3) + year` (e.g. `smithdeeplea2024`).

## Publishing

- **Never edit `~/Documents/Repos/zstreeter.github.io/posts/` directly.** Source of
  truth is `drafts/<slug>.qmd` in this vault.
- To publish: `publish-post drafts/<file>.qmd [slug]` — copies the draft + adjacent
  images into `posts/YYYY-MM-DD-<slug>/index.qmd` in the blog repo.
- Then `cd ~/Documents/Repos/zstreeter.github.io && quarto publish gh-pages` to deploy.

## Tasks you're often asked to do

- **Summarise a paper**: read `literature/@key.md` (and the PDF at `~/Zotero/Zotero-Library/`
  if the lit note is thin), output a 3-bullet summary into the lit note's body.
- **Draft a section**: pull from `notes/` + cited literature, write into `drafts/<file>.qmd`.
  Use `@key` for citations inline.
- **Review a draft**: check frontmatter completeness, citation resolvability (every
  `@key` exists in `references.bib`), prose clarity. Don't rewrite voice.
- **Sync notes ↔ Zotero**: if a `[[@key]]` link is broken, the lit note may need
  re-sync from Obsidian Zotero Integration plugin (manual step in Obsidian, not scriptable).

## Constraints

- Don't add code execution to `.qmd` cells unless explicitly asked — the freeze cache
  in the blog repo means executed cells get cached and committed.
- Don't create new top-level directories in this vault. Stick to the four above.
- Don't modify `_quarto.yml` unless asked — it's pre-tuned for this vault.
- Don't touch `.obsidian/` config files — those are managed by the Obsidian app.
