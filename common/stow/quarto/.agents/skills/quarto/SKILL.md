---
name: quarto
description: "Render research notes, papers and blog posts with Quarto — PDF/LaTeX/HTML from one source, Obsidian notes as direct input, filter ordering, and the blog publish path. Use when rendering a paper or post, debugging a Quarto build, or editing _quarto.yml."
---

# Quarto

Quarto is the **only renderer** in this setup. One source file becomes the blog
post and the paper; nothing else converts between formats.

```bash
quarto render notes/method.md --to typst    # paper (PDF via Typst, no TeX)
quarto render notes/method.md --to pdf      # paper via lualatex, when a venue needs it
quarto render notes/method.md --to latex    # .tex for arXiv / a journal
quarto render notes/method.md --to html     # blog-shaped
quarto preview notes/method.md              # live reload while editing
quarto render                               # everything in the project
```

`quarto preview` is the workhorse for drafting: keep it running, edit the note
in Obsidian or the terminal, watch it re-render.

## Obsidian notes are valid input

A vault scaffolded by `new-research-project` is a Quarto project. Its
`_quarto.yml` makes `.md` notes render as-is:

```yaml
from: markdown+wikilinks_title_after_pipe+mark
filters:
  - at: pre-ast
    path: _extensions/obsidian/obsidian.lua
```

So `quarto render notes/x.md --to typst` works on a note written in Obsidian,
with `[[wikilinks]]`, `![[embeds]]`, callouts and `[[@citekey]]` intact. There
is no conversion step to run first, and no intermediate file to inspect.

## Filter ordering is the thing that bites

Quarto runs filters in phases. A filter declared with a bare path runs **after**
Quarto has normalized the document, which is too late to produce anything Quarto
itself needs to act on. Declare the phase explicitly:

```yaml
filters:
  - at: pre-ast
    path: _extensions/obsidian/obsidian.lua
```

In `_quarto.yml`, not in an extension's `_extension.yml`: the `at:` form under
`contributes.filters` fails YAML validation on Quarto 1.8 (`path: obsidian.lua
failed to be a string`), while the project-level form works on 1.8 and 1.10.

And the file being rendered must be in the project's `render:` list. Quarto
applies `_quarto.yml` **only** to listed files -- one outside the list renders
with no reader extensions, no filter and no PDF format, with no error to say
so. The vault template lists `drafts/` and `notes/`.

Valid values, from `share/schema/definitions.yml`:
`pre-ast, post-ast, pre-quarto, post-quarto, pre-render, post-render, pre-finalize, post-finalize`.

Measured on Quarto 1.10.18, rendering a note whose filter emits a
`.callout-warning` Div, checking for `tcolorbox` in the generated `.tex`:

| `at:`        | callout renders in PDF |
| ------------ | ---------------------- |
| `pre-ast`    | **yes**                |
| `post-ast`   | no                     |
| `pre-quarto` | no, despite the name   |

The failure mode is nasty: HTML still looks right (the HTML writer renders the
class regardless), the build succeeds, and only the PDF silently loses the
callout box **and** its title — the title lives in a Div attribute, so it
vanishes with the box. If a callout looks fine in `--to html` and wrong in
`--to pdf`, this is why.

**Anything that must be recognized by Quarto — callouts, cross-references,
figure handling — has to be produced at `pre-ast`.**

## Debugging a failed render

1. `keep-tex: true` is already set in the vault template, so read the `.tex`
   next to the output. That is what LaTeX actually saw.
2. A LaTeX error usually points at a line far from its cause. Search the `.tex`
   for the surprising construct, not for the line number.
3. Filter warnings go to stderr and Quarto does not highlight them:
   `quarto render x.md --to typst 2>&1 | grep obsidian.lua`
4. To take Quarto out of the picture, run the bundled Pandoc directly:
   ```bash
   quarto pandoc x.md --from markdown+wikilinks_title_after_pipe+mark \
        --lua-filter _extensions/obsidian/obsidian.lua --to markdown
   ```
   If it works here but not under Quarto, the difference is phase or paths.

## Quarto does not hand Pandoc your file

It stages a copy into `/tmp/quarto-session-XXXX/quarto-input-XXXX.md`. Inside a
filter, `PANDOC_STATE.input_files[1]` therefore points into `/tmp`, and anything
that walks up from it to find a project or vault root finds nothing. Use the
environment instead:

| variable                | value                                |
| ----------------------- | ------------------------------------ |
| `QUARTO_DOCUMENT_PATH`  | the real directory of the source file |
| `QUARTO_PROJECT_DIR`    | the project root                     |

Quarto also `chdir`s into the document's directory, so the working directory is
a usable fallback. Plain `pandoc` sets neither but does give a real input path —
a filter that must work under both should try all of them.

## Formats

`_quarto.yml` in the vault template defines `html`, `typst` and `pdf`.

- **`typst` is the paper.** Typst ships inside Quarto, so it needs no TeX
  install and compiles in seconds. Measured on 1.8.27: callouts, citations,
  transclusion and math all render. The obsidian filter wraps `==highlight==`
  in `#highlight[]` because Pandoc's Typst writer drops the `.mark` class.
  Citations are numeric by default; set `csl:` for author-year.
- **`pdf`** is the same paper through lualatex (article, `keep-tex: true`), for
  a journal template or a LaTeX-only package. Needs texlive or
  `quarto install tinytex`. See the `latex` skill.
- A bare `quarto render` builds all three, so render one with `--to`.

## Blog

The blog is a separate Quarto project at `~/Documents/Repos/zstreeter.github.io`.

- **Never edit `posts/` directly.** Source of truth is `drafts/<slug>.qmd` in
  the vault.
- `publish-post drafts/<file>.qmd [slug]` copies the draft and its images into
  `posts/YYYY-MM-DD-<slug>/index.qmd`.
- Deploy: `cd ~/Documents/Repos/zstreeter.github.io && quarto publish gh-pages`.

Don't add executable cells to a draft unless asked — the blog repo commits its
freeze cache, so executed output gets committed too.

## Install

Omarchy has `quarto-cli-bin` in `pkglist.txt`; `wsl/setup.sh` installs the
official `.deb`. Wherever it landed, `quarto pandoc` reaches the bundled Pandoc.

## Related

`obsidian` (authoring and opening), `pandoc` (what Quarto delegates to, and how
the filter works), `latex` (engines and packages), `zotero` (`references.bib`).
