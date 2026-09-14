---
name: pandoc
description: "Pandoc reader extensions, the Obsidian Lua filter, and how to write AST filters that cannot corrupt math. Use when editing obsidian.lua, adding markdown syntax support, debugging a wikilink/callout/citation conversion, or writing any Pandoc filter."
---

# Pandoc

Pandoc is not invoked directly here — Quarto bundles it and drives it. What you
edit is the **filter**.

```bash
# The bundled binary, when you need to take Quarto out of the loop.
# `quarto pandoc` finds it wherever Quarto is installed; never hardcode its path.
quarto pandoc note.md --from markdown+wikilinks_title_after_pipe+mark \
     --lua-filter _extensions/obsidian/obsidian.lua --to native   # AST
```

`--to native` prints the syntax tree. **Read the AST before writing a rule** —
it is the difference between a five-line filter and a day of guessing.

## Never preprocess markdown with regexes

This is the load-bearing rule of the whole pipeline.

The obvious way to bridge Obsidian and Pandoc is to rewrite the text before
Pandoc sees it. It does not work, because every rule you would write is a regex
over prose and LaTeX is built from exactly the characters those regexes hunt
for:

| character | Obsidian means      | LaTeX means                 |
| --------- | ------------------- | --------------------------- |
| `==`      | `==highlight==`     | comparison in an equation   |
| `^`       | `^block-id`         | superscript                 |
| `[[ ]]`   | wikilink            | bracket matrix delimiters   |
| `%%`      | comment             | (a literal percent pair)    |

A text pass cannot tell them apart, so it silently corrupts formulas and the
damage surfaces as a LaTeX error far from its cause.

A **filter** runs after parsing. By then math is a `Math` node and code is a
`Code` node — opaque, and unreachable by any rule you write. The bug class is
designed out rather than defended against.

## What Pandoc 3.x already does

Verified empirically against the bundled Pandoc, not from documentation (web
sources are out of date on this):

| Obsidian          | Pandoc produces                            | needs               |
| ----------------- | ------------------------------------------ | ------------------- |
| `[[Note]]`        | `Link` with class `wikilink`               | `+wikilinks_title_after_pipe` |
| `[[Note\|alias]]` | same, alias in the link text               | same                |
| `![[figure.png]]` | `Figure > Plain > Image`, class `wikilink` | same                |
| `==highlight==`   | `Span` with class `mark`                   | `+mark`             |
| `$…$` / `$$…$$`   | `Math InlineMath` / `Math DisplayMath`     | — (always)          |

So the reader extension line is:

```
markdown+wikilinks_title_after_pipe+mark
```

## What the filter has to add

Only four things, which is why `obsidian.lua` is small:

| syntax             | why Pandoc can't                                     |
| ------------------ | ---------------------------------------------------- |
| `[[@citekey]]`     | it's a citation, not a link — becomes `Cite`         |
| `![[Note#Section]]` | transclusion; Pandoc has no such concept            |
| `> [!warning]`     | a callout, not a blockquote — becomes a callout Div  |
| `%%comment%%`      | a comment, not text                                  |

The citation case is the one that costs real work if you skip it, and it fails
**silently**: the link renders as plain text, the reference never reaches the
bibliography, and the paper's reference list comes out quietly short. This
repo's vaults file literature notes as `@<citekey>.md` and link them
`[[@citekey]]`, so a wikilink starting with `@` is a bibliography entry.

## Writing a rule

Pipeline order in `obsidian.lua` is load-bearing and documented in the file:

1. **Transclusion first** — so inlined content gets every later pass exactly
   like the host note's own (an embedded note's callouts and citations work).
2. **Comments next** — so a commented-out callout never becomes one.
3. Everything else.

Gotchas that already cost debugging time:

- **A `--[[` block comment closes on `]]`.** Any header text mentioning
  `[[Note]]` terminates it early. Use long brackets: `--[==[ … ]==]`.
- **Pandoc promotes lone-image alt text to a figure caption**, so every
  `![[figure.png]]` captions itself "figure.png" (or "400" for
  `![[figure.png|400]]`). Clear `fig.caption`.
- **Stripping an inline `%%` strands the space that followed it**, and a
  `%%…%%` on its own line leaves an empty `Para`. Trim both.
- **Obsidian has far more callout types than Quarto**, and Quarto renders an
  unrecognized callout class as *nothing at all*. Map every alias, and fall back
  to a visible blockquote for anything unmapped — losing the author's text is
  worse than losing the box.
- **Obsidian addresses files by name, not path.** Resolving links means indexing
  the vault once; doing it per link is O(links × files).

## Verifying a change

Round-trip to markdown — it shows the transformation without LaTeX noise:

```bash
quarto pandoc note.md --from markdown+wikilinks_title_after_pipe+mark \
     --lua-filter obsidian.lua --to markdown
```

Check specifically that a formula containing `==`, `^` and `\\` came through
untouched. That is the regression this architecture exists to prevent.

Filter warnings go to stderr:
`quarto render x.md --to typst 2>&1 | grep obsidian.lua`

## Related

`quarto` — filter **phases** (`at: pre-ast`) and why Quarto stages your input
into `/tmp`. Both matter as much as the filter's contents.
