"""Work out what the user meant by one string, then go and find it.

`paperctl add` takes a title, an arXiv id, a DOI or a URL and must do the right
thing with all four without being told which it got. Sniffing beats a --type
flag here: the four shapes are unambiguous, and requiring the flag would make
the common case (paste a link) the awkward one.
"""

from __future__ import annotations

import re
import sys

from . import links
from .record import Record
from .sources import arxiv, crossref, openalex, page, search_all


def kind_of(text: str) -> str:
    """One of: arxiv, doi, url, title."""
    t = (text or "").strip()
    if arxiv.id_of(t):
        return "arxiv"
    if re.match(r"^(doi:)?10\.\d{4,9}/", t, re.I):
        return "doi"
    if re.match(r"^(https?://|www\.)", t, re.I):
        return "url"
    return "title"


def resolve(fetch, text: str, sources: list[str],
            limit: int = 8) -> tuple[Record | None, list[Record]]:
    """Return (best, alternatives).

    `alternatives` is only populated for a title search, where the caller may
    want to disambiguate. The three exact forms either resolve or do not.
    """
    text = (text or "").strip()
    kind = kind_of(text)

    if kind == "arxiv":
        return _first(fetch, [(arxiv, arxiv.id_of(text))]), []

    if kind == "doi":
        doi = crossref.doi_of(text)
        return _first(fetch, [(crossref, doi), (openalex, doi)]), []

    if kind == "url":
        url = links.normalize(text)
        # Order matters: an arXiv URL carries an id that gives the best record,
        # a publisher URL usually carries a DOI, and scraping the page is the
        # fallback that always technically works and is always worst.
        aid = arxiv.id_of(url)
        if aid:
            rec = _first(fetch, [(arxiv, aid)])
            if rec:
                return rec, []
        doi = crossref.doi_of(url)
        if doi:
            rec = _first(fetch, [(crossref, doi), (openalex, doi)])
            if rec:
                return rec, []
        if links.is_shortener(url):
            expanded = fetch.final_url(url)
            if links.normalize(expanded) != url:
                return resolve(fetch, expanded, sources, limit)
        rec = page.fetch_one(fetch, url)
        if rec:
            return rec, []
        # Nothing could describe it, but the URL is still worth keeping: a
        # bare record indexes and links it, just without metadata.
        return Record(title="", url=url, source="unresolved"), []

    found = search_all(fetch, text, sources, limit)
    if not found:
        return None, []
    best = found[0]
    # A weak best match is worse than none for `add`: it silently files the
    # wrong paper. The caller decides what to do, but it needs to know.
    if best.score < 0.55:
        print(f"paperctl: best match scored {best.score:.2f}, which is weak:\n"
              f"          {best.title}\n"
              f"          Use `paperctl search-web` to pick deliberately.",
              file=sys.stderr)
    return best, found[1:]


def _first(fetch, attempts) -> Record | None:
    """First source that answers wins; a source that errors is skipped."""
    for module, ident in attempts:
        if not ident:
            continue
        try:
            rec = module.fetch_one(fetch, ident)
        except Exception as e:
            print(f"paperctl: {module.__name__.rsplit('.', 1)[-1]} lookup "
                  f"failed: {type(e).__name__}", file=sys.stderr)
            continue
        if rec:
            return rec
    return None


def enrich(fetch, rec: Record, sources: list[str]) -> Record:
    """Fill gaps in a record from the other sources.

    arXiv knows the PDF but often not the journal it later appeared in;
    Crossref knows the journal but has no PDF. A record that has been through
    both cites correctly *and* reads locally.
    """
    if rec.doi and not rec.venue and "crossref" in sources:
        other = _first(fetch, [(crossref, rec.doi)])
        if other:
            for f in Record.__dataclass_fields__:
                if f != "score" and not getattr(rec, f) and getattr(other, f):
                    setattr(rec, f, getattr(other, f))
    if not rec.pdf_url and rec.doi and "openalex" in sources:
        other = _first(fetch, [(openalex, rec.doi)])
        if other and other.pdf_url:
            rec.pdf_url = other.pdf_url
    return rec
