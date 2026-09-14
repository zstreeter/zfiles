---
name: latex
description: "LaTeX engines, TinyTeX, reading a failed .tex, and writing math that survives the pipeline. Use when a PDF render fails, a package is missing, math renders wrong, or producing .tex for arXiv or a journal."
---

# LaTeX

LaTeX is the output stage, never the authoring stage. Notes are markdown; the
`.tex` is generated. **Don't hand-edit generated `.tex`** — the next render
overwrites it. Fix the note, or the filter.

The exception is a journal that demands a specific class: render `--to latex`,
then treat the `.tex` as a one-time deliverable.

## Engine

The default paper format is **`typst`**, which ships inside Quarto and needs no
TeX at all; reach for LaTeX when a venue wants a `.tex` or a LaTeX-only
package. Quarto's `pdf` format here uses **lualatex**. On a machine with no
texlive and no sudo:

```bash
quarto install tinytex     # user-local, ~/.TinyTeX, no root
```

TinyTeX installs packages **on demand** during a render — the first build of a
document using a new construct pauses to fetch (`installing luacolor…`). That is
normal, not an error. It needs network; on an offline box, pre-install.

TinyTeX's binaries live in `~/.TinyTeX/bin/x86_64-linux`. Quarto finds them
itself, but a shell that calls `lualatex` directly needs that on `PATH`.

## Reading a failed render

`keep-tex: true` is set in the vault template, so the `.tex` survives next to
the output. It is the ground truth for what LaTeX saw.

The reported line number is where LaTeX *gave up*, not where the problem is.

```
Missing \endcsname inserted.
l.230 ...ics[keepaspectratio]{theory\#Conditioning}}
```

Read the *content* of the line: here, an `\includegraphics` of
`theory#Conditioning` — a note transclusion that was never expanded and fell
through to the image path. The fix was in the filter, not in the LaTeX. Search
the `.tex` for the surprising construct and work backwards to which markdown
produced it.

Common shapes:

| symptom in `.tex`                      | actual cause                          |
| -------------------------------------- | ------------------------------------- |
| `\includegraphics{Note#Section}`        | transclusion didn't resolve — vault not found by the filter |
| callout text present, no `tcolorbox`    | filter ran too late; needs `at: pre-ast` (see `quarto`) |
| citation printed literally as `@key`    | reader extension or bibliography missing (see `zotero`) |
| mangled formula                         | something did a text-level rewrite — see `pandoc` |

## Writing math that survives

Math is safe by construction: Pandoc parses `$…$` and `$$…$$` into opaque
`Math` nodes before any filter runs, so `==`, `^`, `[[ ]]` and `\\` inside a
formula are untouchable. Verified end-to-end on:

```latex
$$
\begin{bmatrix} a^2 & b \\ c & d \end{bmatrix} \quad x == y \quad \eta^2
$$
```

which renders correctly through Obsidian → Quarto → lualatex → PDF.

So: **write ordinary LaTeX.** No escaping workarounds, no avoiding characters.

Two rules that are about Obsidian, not LaTeX:

- Put `$$` blocks on their own lines with a blank line above and below, or
  Obsidian won't parse them.
- Obsidian renders with MathJax (a superset of KaTeX), so `align`, `bmatrix`
  and friends work in the editor as well as in the PDF.

### Spacing macros in chat vs. in files

`\,` `\!` `\;` `\:` are **fine in every file** — notes, `.qmd`, `.tex`. They are
corrupted only when displayed in terminal chat output, which is a rendering
quirk of that path and has nothing to do with the document pipeline. Never
degrade a real document to work around it. Likewise `\\` is the row separator;
never write `@nl`, which is LaTeX-invalid and breaks a real engine.

## Producing .tex for submission

```bash
quarto render drafts/paper.md --to latex
```

Leaves `paper.tex` beside the source. Check before submitting:

- Figures are referenced at paths the journal's build will have.
- The bibliography is embedded or the `.bib` ships alongside.
- The class matches what was asked for; `_quarto.yml` defaults to `article`.

## Related

`quarto` (formats, filter phases), `pandoc` (why math is safe), `zotero`
(bibliography), `obsidian` (authoring).
