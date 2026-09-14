---
name: obsidian-note
description: "Save material from the current conversation into the user's Obsidian vault as a cohesive reference note. Use when the user says /obsidian-note, or asks to save, capture, or write something to Obsidian, to their vault, or to their notes."
---

# /obsidian-note

Write material from this conversation into Zach's Obsidian vault as an edited reference document.

## Vault location

```bash
obsidian-vault path      # the default vault, on any target
obsidian-vault list      # every vault this machine knows about
```

Never hardcode a vault path here: on WSL the default vault is a Windows path under the user's profile, and on Omarchy or a remote box it is not. The default vault may live in a corporate OneDrive folder, so anything written syncs. Don't put secrets, credentials, or proprietary source in a note.

## Usage

```
/obsidian-note <what to save>
/obsidian-note the Green's function derivation
/obsidian-note everything about the variational bound, append to the correction vectors note
```

With no argument, save the substantive material from the current conversation and pick a sensible title.

## Procedure

1. **Choose the target note.** Prefer appending to an existing note on the same topic over creating a near-duplicate. List the vault (`ls`) and check for a match before creating. Filename: `Title Case With Spaces.md` — Obsidian convention, and it makes `[[wikilinks]]` read naturally.

2. **Decide append vs. create.** If appending, Read the file first, match its heading depth and voice, and add a new `##` section rather than restating context the note already has.

3. **Write an edited document, not a transcript.** This is the part that matters. The user wants a reference they can come back to, so:
   - Drop the conversational scaffolding — no "you asked", "as I mentioned", "great question"
   - Merge things discussed across several turns into one coherent section
   - Silently fix anything that was corrected mid-conversation; record the correct version only
   - Keep derivations in logical order, not the order they came up
   - Number equations `(1)`, `(2)`, ... when the note refers back to them

4. **Confirm** with the full path written and a one-line summary of what went in.

## Formatting

For Obsidian Flavored Markdown syntax — callouts, wikilinks, embeds, properties, block refs — defer to the `obsidian-markdown` skill from `kepano/obsidian-skills` if it's installed. Don't duplicate its reference material here. This skill covers the workflow; that one covers the syntax.

**LaTeX is unrestricted here.** File writes are literal — `\,`, `\!`, `\;`, `\\` all survive intact, unlike the terminal display path (a terminal display quirk that applies to chat output only, NOT to notes). Obsidian renders math with MathJax, which is a superset of KaTeX. Write proper LaTeX.

- `$...$` inline, `$$...$$` for display
- Put `$$` blocks on their own lines with a blank line above and below, or Obsidian won't parse them
- `\\` for matrix rows and `align` breaks works normally — the `@nl` workaround is LaTerM-specific and must never appear in a note

Frontmatter on every new note:

```markdown
---
tags:
  - claude-code
  - <topic-tag>
created: YYYY-MM-DD
updated: YYYY-MM-DD
source: Claude Code session (<project name>)
---
```

Bump `updated:` when appending. Use `[[Wikilinks]]` to connect related notes, and add a `## See also` section when two notes are related — a link that points at a note not yet written is fine and useful.

## Scope

Save what the user asked for. If they name a topic, don't sweep in unrelated material from elsewhere in the conversation; if they ask for everything, be thorough rather than writing a summary.
