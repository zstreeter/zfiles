# Research vault convention

Every Obsidian vault has a matching paper directory: vault `<Name>` ->
`$HOME/Library/<Name>/`.

- **Creating a vault**: `new-research-project <Name>`. It scaffolds the
  Quarto/Obsidian template and creates the matching library directory in the
  same step, so the two cannot drift. It also resolves the vault root itself --
  that differs per target, so do not hardcode a root or reimplement the choice.
- **Adding a paper**: `paperctl add <title|arxiv-id|doi|url> --to <Name>`.
  Never download a PDF by hand -- paperctl files the PDF, writes a README index
  and BibTeX, is idempotent, and records link-only papers it cannot fetch.
- **Citing**: `paperctl bib --folder <Name> --out <vault>/library.bib`, then
  `bibliography: [references.bib, library.bib]` in `_quarto.yml`.
  `references.bib` is Better BibTeX's auto-export -- never hand-edit it.
- **Publishing**: `publish-post <vault>/drafts/<file>.qmd` (blog),
  `publish-confluence <file.md>` (wiki, needs `CONFLUENCE_*` in the
  environment).

Resolve paths, never assume them: `obsidian-vault path <Name>` for a vault,
`$HOME/Library` for the library. Anything target-specific belongs inside the
script that needs it, behind a runtime check -- not in this file, which is
loaded on every machine.

## Paths in this repo

This repo is public. Do not write absolute paths containing a username,
employer, internal hostname, or work directory into any tracked file -- use
`$HOME`, `${XDG_*}`, or a discovery command. Employer-specific tooling and
tenant identifiers stay out of the repo entirely: `$HOME/.local/bin` and
`~/.config/shell/secrets.env` are untracked and are where they go.

`common/githooks/pre-push` blocks the identifiers in
`${XDG_CONFIG_HOME:-$HOME/.config}/zfiles/leak-patterns`, but treat it as a
backstop, not permission.
