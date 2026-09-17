---
name: paperctl
description: "Build and query a local research-paper library — add papers by title, arXiv id, DOI or URL; search arXiv/Crossref/OpenAlex; harvest every paper shared in an email thread; emit BibTeX for a Quarto project. Use whenever a paper needs finding, filing, citing, or pulling out of mail, instead of downloading PDFs by hand."
---

# paperctl

One CLI, on PATH, stdlib-only Python. It files papers into `~/Library/<Folder>/`
with the PDF, a README index and a BibTeX file, and it reads email through
whatever mail client the machine actually has.

Run `paperctl doctor` first on an unfamiliar machine. It reports what works
**here** — which mail backend resolved, whether the Graph token is live, which
sources are reachable — and exits 0 even when things are missing. Nothing else
in this document is worth trusting until doctor agrees.

## Adding papers

```bash
paperctl add "Attention is all you need"          # title
paperctl add 2506.19243                           # arXiv id
paperctl add 10.1016/j.cma.2025.118308            # DOI
paperctl add https://arxiv.org/abs/2506.19243     # URL
paperctl add "..." --to PINN_Blowup               # a named folder
```

All four forms resolve to the same record shape. A title is fuzzy-matched across
sources and **the match is reported with its score** — when the best score is
below 0.55 it says so rather than filing the wrong paper silently. Check it.

`add` is idempotent: re-adding a paper already in the folder updates the metadata
and does not re-download. A paper with no legal open-access copy is filed
`link-only` — the record and citation are kept, the PDF is not, and
`paperctl retry` re-attempts those later when a preprint may have appeared.

## Email

```bash
paperctl mail thread --subject "PINN-based finite time blow up" --dry-run
paperctl mail thread --subject "..." --links-only
paperctl mail thread --subject "..." --to Euler_Blowup
paperctl mail search "diffusion model"
```

`--dry-run` prints the count at every filter stage and writes nothing. Run it
first — it is how you confirm the right thread matched before anything lands on
disk.

The backend is chosen per machine (`mail.backend = "auto"` probes; the WSL laptop
gets Microsoft Graph, Omarchy gets himalaya). You do not pick it, and no command
takes a backend flag — that is the whole point of the abstraction.

**If a run warns that messages parsed as HTML but contained no anchors, stop and
do not trust the counts.** That is the signature of a text-flattening body path,
not an empty thread. Links live in `href` attributes; the visible text is usually
the paper's title. A flattening path once returned zero URLs for 4 of 22 messages
— including the originating mail carrying the two most important links.

## alphaXiv bookmarks

```bash
# once, in ~/.config/shell/secrets.env (gitignored, sourced by every shell):
#     export ALPHAXIV_API_KEY="axv1_..."   # alphaxiv.org -> Settings -> API Keys
paperctl pull --dry-run                 # what would be filed, and where
paperctl pull                           # one library folder per alphaXiv folder
paperctl pull --folder blowup --to PINN_Blowup
```

**alphaXiv is the only source here that needs a credential.** arXiv, Crossref
and OpenAlex are open APIs with no key and no registration; `unpaywall_email` is
a contact address their terms ask for, not a secret. So there is exactly one key
to set, and it is an env var — never a `config.toml` or `local.toml` setting,
because those live inside the repo and an ignore rule is weaker than being
outside it. `paperctl doctor` reports whether it is set and whether alphaXiv
accepts it.

One direction, always: alphaXiv is where papers are *found*, the library is
where they live. `pull` never writes back, and never touches `references.bib`.
A bookmark is "read this later", which is not the same claim as a bibliography
entry — auto-filing them into Zotero would put unread papers in a citation list.

Re-running is the sync. Bookmarks already filed **with a PDF** are skipped
without a network call; anything `link-only` is re-attempted, same as
`paperctl retry`. A private (non-arXiv) upload has no id to resolve, so it falls
back to a title search and is reported `UNRESOLVED` if nothing matches — that is
a report, not a failure, and the run continues.

## Searching

```bash
paperctl search "transformer"                    # the local library
paperctl search-web "neural operator" --source arxiv,crossref
```

`search` is the local index and is instant. `search-web` is discovery and hits
the network; results merge across sources, filling each other's gaps.

## Citing, into a Quarto project

```bash
paperctl bib --folder PINN_Blowup --out ~/research/paper/library.bib
```

Then in `_quarto.yml`:

```yaml
bibliography: [references.bib, library.bib]
```

**`paperctl bib` refuses to write a file named `references.bib` and exits 2.**
That file is Better BibTeX's auto-export in an Obsidian vault and hand edits to
it are silently overwritten on the next sync. Two files, cited as a list, is the
non-destructive arrangement — and it still works on a machine with no Zotero at
all. Citekeys approximate BBT's `auth.lower + shorttitle(3,3) + year` so the two
files stay mergeable.

## Housekeeping

```bash
paperctl retry              # re-attempt link-only papers
paperctl tidy               # duplicate PDFs by content hash — REPORT ONLY
paperctl tidy --apply       # actually remove them
```

`tidy` without `--apply` deletes nothing. It reports duplicate *content*, found
by hash, not by filename.

## Flags that apply everywhere

| flag | effect |
|---|---|
| `--json` | machine-readable output, on every read command |
| `--dry-run` | show what would happen, write nothing |
| `--library DIR` | redirect the library root for one run |
| `--config FILE` | ignore the usual config and use this one |
| `--source a,b` | restrict which metadata sources run |

## Configuration

`~/.config/paperctl/config.toml` is committed and contains **no secrets**.
Anything private — an email address, a machine-specific path — goes in
`local.toml` beside it, which is gitignored.

Layers, later wins, every one optional: defaults → `config.toml` →
its `[target.<name>]` section → `local.toml` → `PAPERCTL_*` env → CLI flags.
A machine with no config at all still works. `paperctl doctor` prints each
resolved value **and where it came from**, which is the fastest way to answer
"why is it doing that".
