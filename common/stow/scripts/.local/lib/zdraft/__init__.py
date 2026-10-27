"""zdraft -- how a vault draft is read, in one place.

Every publish and check script used to parse drafts for itself, and the copies
drifted: the lint gate and publish-confluence disagreed on what counts as maths,
vault-doctor's citekey pattern missed Better BibTeX keys (smith_2003) that
publish-lint caught, and publish-confluence guessed the Quarto project as
dirname(dirname(draft)), which is wrong for drafts/2026/oct/x.qmd.

    frontmatter(text)   -> (fields, body_start)
    spans(text)         -> [Span]       code and maths, in document order
    masked(text)        -> text         code + maths blanked, offsets/lines kept
    citekeys(text)      -> [(offset, key)]
    vault_of(path)      -> Path | None  the dir holding .obsidian/
    project_of(path)    -> Path         where `quarto render` must run

The scripts are callers; bash ones go through `python3 -m zdraft` (__main__.py).
"""
import re
from dataclasses import dataclass
from pathlib import Path

# One scan, leftmost-first: whichever of code / display maths / inline maths
# starts earliest wins, so a `$` inside code is never maths and `$$` is never
# two inline spans. Inline maths may not touch another `$` on either side.
_SPAN = re.compile(
    r"(?P<fence>```.*?```)"
    r"|(?P<code>`[^`\n]+`)"
    r"|\$\$(?P<display>.+?)\$\$"
    r"|(?<!\$)\$(?P<inline>[^$\n]+?)\$(?!\$)",
    re.S)

# Better BibTeX keys: a letter, then word characters and : . -  (smith_2003, a:b).
_KEY = r"[A-Za-z][\w:.-]*"
# [[@key]] / [[@key|alias]], or a pandoc citation: @key at a word start, or
# after [ ; ( -- so a@b.com (an address) is never a key.
_CITE = re.compile(rf"\[\[@(?P<wiki>{_KEY})[^\]]*\]\]|(?:^|(?<=[\s\[;(]))-?@(?P<bare>{_KEY})", re.M)


@dataclass(frozen=True)
class Span:
    start: int
    end: int
    kind: str          # "code" | "display" | "inline"
    tex: str = ""      # the maths, stripped; empty for code


def frontmatter(text: str) -> tuple[dict, int]:
    """Top-level `key: value` fields of a leading --- block, and where the body starts.

    No front matter (line 1 is not ---, or it never closes) is ({}, 0). Values are
    the raw scalar with surrounding quotes removed; a key with a nested or list
    value maps to its inline text, possibly "" -- presence is what callers test.
    """
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        return {}, 0
    fields, pos = {}, len(lines[0])
    for line in lines[1:]:
        pos += len(line)
        s = line.rstrip("\r\n")
        if s in ("---", "..."):
            return fields, pos
        m = re.match(r"([A-Za-z_][\w-]*):(.*)$", s)
        if m:
            v = m.group(2).strip()
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "\"'":
                v = v[1:-1]
            fields[m.group(1)] = v
    return {}, 0


def spans(text: str) -> list[Span]:
    out = []
    for m in _SPAN.finditer(text):
        if m.group("fence") or m.group("code"):
            out.append(Span(m.start(), m.end(), "code"))
        elif m.group("display") is not None:
            out.append(Span(m.start(), m.end(), "display", m.group("display").strip()))
        else:
            out.append(Span(m.start(), m.end(), "inline", m.group("inline").strip()))
    return out


def masked(text: str) -> str:
    """Code and maths blanked to spaces, newlines kept: offsets and line numbers survive."""
    parts, last = [], 0
    for s in spans(text):
        parts += [text[last:s.start], re.sub(r"[^\n]", " ", text[s.start:s.end])]
        last = s.end
    return "".join(parts) + text[last:]


def citekeys(text: str) -> list[tuple[int, str]]:
    """Every citation outside code and maths, as (offset, key), in order.

    A trailing . : - is sentence punctuation, not key (`see @smith2003.`).
    """
    out = []
    for m in _CITE.finditer(masked(text)):
        key = (m.group("wiki") or m.group("bare")).rstrip(".:-")
        out.append((m.start(), key))
    return out


def vault_of(path) -> Path | None:
    """The nearest directory at or above `path` holding .obsidian/, else None."""
    p = Path(path).resolve()
    for d in ([p] if p.is_dir() else []) + list(p.parents):
        if (d / ".obsidian").is_dir():
            return d
    return None


def project_of(path) -> Path:
    """Where `quarto render` must run for this draft: its vault when that vault is a
    Quarto project (has _quarto.yml), however deep the draft sits; else the draft's
    own directory, where it renders as a loose file."""
    v = vault_of(path)
    if v and (v / "_quarto.yml").is_file():
        return v
    return Path(path).resolve().parent


def _selftest() -> None:
    import tempfile
    doc = ("---\ntitle: \"A: b\"\ndate: 2026-01-03\nbibliography:\n  - r.bib\n---\n"
           "Code `$x$` and\n```\nls $HOME @notakey\n```\n"
           "maths $[[n,k,d]]$ and $$\\sum_i a_i$$ and $5 then $6$x.\n"
           "See [[@smith_2003]], [@a:b; -@Doe.2020], @kakaralaBisSouPha2009. "
           "Mail a@b.com.\n")
    fm, start = frontmatter(doc)
    assert fm == {"title": "A: b", "date": "2026-01-03", "bibliography": ""}, fm
    assert doc[start:].startswith("Code"), doc[start:start + 10]
    assert frontmatter("no\n---\n") == ({}, 0) and frontmatter("---\ntitle: x\n") == ({}, 0)

    kinds = [(s.kind, s.tex) for s in spans(doc)]
    assert kinds == [("code", ""), ("code", ""), ("inline", "[[n,k,d]]"),
                     ("display", "\\sum_i a_i"), ("inline", "5 then")], kinds
    m = masked(doc)
    assert len(m) == len(doc) and m.count("\n") == doc.count("\n")
    assert "[[n,k,d]]" not in m and "$HOME" not in m and "@notakey" not in m

    keys = [k for _, k in citekeys(doc)]
    assert keys == ["smith_2003", "a:b", "Doe.2020", "kakaralaBisSouPha2009"], keys
    assert [k for _, k in citekeys("@x at start")] == ["x"]

    with tempfile.TemporaryDirectory() as t:
        v = Path(t, "vault")
        (v / ".obsidian").mkdir(parents=True)
        (v / "drafts/2026/oct").mkdir(parents=True)
        draft = v / "drafts/2026/oct/x.qmd"
        draft.write_text("x")
        loose = Path(t, "loose.md")
        loose.write_text("x")
        assert vault_of(draft) == v.resolve() and vault_of(v) == v.resolve()
        assert vault_of(loose) is None
        assert project_of(draft) == draft.resolve().parent       # vault, but no _quarto.yml
        (v / "_quarto.yml").write_text("project: {}\n")
        assert project_of(draft) == v.resolve()                  # not dirname(dirname(draft))
        assert project_of(loose) == loose.resolve().parent
