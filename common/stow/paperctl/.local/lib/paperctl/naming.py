"""Turning titles and authors into filenames, citekeys and BibTeX.

Three separate jobs that all look like "clean up a string" and all have
different rules, so they are three functions and not one with flags.
"""

from __future__ import annotations

import html
import re
import unicodedata

RE_PREFIX = re.compile(r"^\s*((re|fwd?|fw|aw|sv)\s*:\s*)+", re.I)

# Filenames only. Illegal on NTFS, and ":" and "\" are a nuisance on ext4 too
# because half the tooling that touches ~/Library is Windows-side.
ILLEGAL = re.compile(r'[:/\\*?"<>|]')

# Words BBT drops when building shorttitle. Same list, same order of operations,
# so a citekey generated here matches one Zotero would generate for the same
# paper and the two .bib files can coexist without colliding or duplicating.
STOPWORDS = {
    "a", "an", "the", "and", "or", "but", "of", "for", "on", "in", "to",
    "with", "from", "by", "at", "as", "is", "are", "be", "using", "via",
}


def strip_re_prefix(subject: str) -> str:
    return RE_PREFIX.sub("", subject or "").strip()


def clean(text: str) -> str:
    """Collapse whitespace and resolve HTML entities.

    Entity resolution happens here, once, at the edge -- not in the BibTeX
    writer. Doing it late is what produced `J\\&#233;r\\&#244;me` in the old
    refs.bib: the LaTeX escaper saw a raw `&` in `&#233;`, escaped it to `\\&`,
    and froze the entity in place where nothing would ever decode it again.
    """
    return " ".join(html.unescape(text or "").split())


def title_case_filename(title: str, limit: int = 100) -> str:
    """Title_Case_With_Underscores -- the existing ~/Library convention.

    Preserves the source's own casing and internal hyphens, so PINN-based stays
    PINN-based rather than becoming Pinn_Based.
    """
    s = strip_re_prefix(clean(title))
    s = ILLEGAL.sub(" ", s)
    s = re.sub(r"[^\w\s.-]", " ", s, flags=re.U)
    s = re.sub(r"\s+", "_", s.strip()).strip("._-")
    if len(s) > limit:
        # Back to a word boundary. Cutting mid-word produces filenames like
        # Finite_Time_Blow_Up_Of_Eul, which read as corrupt rather than as
        # abbreviated.
        s = s[:limit].rsplit("_", 1)[0]
    return s or "untitled"


def kebab(title: str, limit: int = 100) -> str:
    s = re.sub(r"[^\w\s-]", "", clean(title)).strip().lower()
    s = re.sub(r"[-\s]+", "-", s)
    if len(s) > limit:
        s = s[:limit].rsplit("-", 1)[0]
    return s or "untitled"


def filename(title: str, style: str = "title_case", limit: int = 100) -> str:
    if style == "kebab":
        return kebab(title, limit)
    if style == "as_is":
        return ILLEGAL.sub(" ", clean(title))[:limit].strip() or "untitled"
    return title_case_filename(title, limit)


def _ascii(s: str) -> str:
    """Fold accents away. Citekeys must be typeable from a US keyboard."""
    return "".join(c for c in unicodedata.normalize("NFKD", s)
                   if not unicodedata.combining(c))


def surname(author: str) -> str:
    """Last name from either "Jane Q. Doe" or "Doe, Jane Q."."""
    a = clean(author)
    if "," in a:
        return a.split(",", 1)[0].strip()
    parts = a.split()
    return parts[-1] if parts else ""


def citekey(authors: list[str], title: str, year: str) -> str:
    """Approximate Better BibTeX's auth.lower + shorttitle(3,3) + year.

    Approximate, not identical -- BBT has years of special cases for particles
    ("van der Waals") and institutional authors. Close enough that the keys are
    recognisable and stable, which is what matters when library.bib sits beside
    a BBT-generated references.bib.
    """
    first = _ascii(surname(authors[0]) if authors else "").lower()
    first = re.sub(r"[^a-z]", "", first) or "anon"
    words = [w for w in re.findall(r"[A-Za-z0-9]+", _ascii(clean(title)))
             if w.lower() not in STOPWORDS]
    short = "".join(w[:3].capitalize() for w in words[:3])
    return f"{first}{short}{year or ''}"


# BibTeX/LaTeX specials. Backslash is absent on purpose: values reaching here
# have already been HTML-unescaped and are plain text, so a backslash in one is
# vanishingly rare, while escaping it would break any that is deliberate.
LATEX_SPECIALS = {"&": r"\&", "%": r"\%", "$": r"\$", "#": r"\#",
                  "_": r"\_", "~": r"\textasciitilde{}", "^": r"\textasciicircum{}"}


def bib_escape(value: str) -> str:
    """Make a plain string safe inside a BibTeX field.

    UTF-8 is emitted as itself. Pandoc's citeproc reads .bib as UTF-8 and both
    the typst and LaTeX writers handle accented characters, so converting
    Jérôme into \\'{e} machinery would be work that buys nothing and loses
    fidelity if the .bib is ever read by anything else.
    """
    out = []
    for ch in clean(value):
        if ch in "{}":
            continue           # braces are BibTeX syntax, never content
        out.append(LATEX_SPECIALS.get(ch, ch))
    return "".join(out)


def bibtex(rec, key: str) -> str:
    """One BibTeX entry from a Record.

    Entry type is chosen rather than hardcoded to @article: a preprint is not
    an article, and a conference paper cited as one loses its venue in every
    citation style that distinguishes them.
    """
    fields: list[tuple[str, str]] = []
    kind = "article"
    venue = rec.venue or ""
    if rec.arxiv_id and not rec.doi:
        kind, fields = "misc", [("eprint", rec.arxiv_id),
                                ("archivePrefix", "arXiv"),
                                ("howpublished", "arXiv preprint")]
    elif re.search(r"\b(proc|conference|symposium|workshop|meeting)\b", venue, re.I):
        kind = "inproceedings"

    if rec.title:
        # Double-braced: BibTeX lowercases titles in many styles, and a paper
        # about PINNs or GPUs must not become Pinns or Gpus.
        fields.insert(0, ("title", "{{" + bib_escape(rec.title) + "}}"))
    if rec.authors:
        fields.append(("author", "{" + bib_escape(" and ".join(rec.authors)) + "}"))
    if rec.year:
        fields.append(("year", "{" + bib_escape(rec.year) + "}"))
    if venue:
        field = {"inproceedings": "booktitle", "misc": "note"}.get(kind, "journal")
        fields.append((field, "{" + bib_escape(venue) + "}"))
    for name, val in (("volume", rec.volume), ("pages", rec.pages),
                      ("publisher", rec.publisher), ("doi", rec.doi)):
        if val:
            fields.append((name, "{" + bib_escape(val) + "}"))
    if rec.url:
        # Not escaped: a URL is verbatim, and \_ inside one breaks the link.
        fields.append(("url", "{" + rec.url + "}"))

    body = ",\n".join(f"  {k} = {v}" for k, v in fields)
    return "@%s{%s,\n%s\n}\n" % (kind, key, body)
