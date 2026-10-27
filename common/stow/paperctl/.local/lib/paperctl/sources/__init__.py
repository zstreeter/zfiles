"""Metadata sources, behind one shape.

Every source module exposes the same shape:

    API                                            endpoint, for `doctor`
    ANSWERS                                        id kinds fetch_one takes: "arxiv", "doi"
    search(fetch, query, limit) -> [Record]        discovery, may be empty
    fetch_one(fetch, ident)     -> Record | None   exact lookup

Callers never pick a source themselves: they ask this module -- search_all,
exact, enrich -- and `--source` / `sources.enabled` decide which ones run.
Adding a journal API is one new file plus one line in REGISTRY.

Source modules may raise (they are thin HTTP clients). This module catches,
says so on stderr and moves on: losing Crossref costs the Crossref results,
never the run. Results from several sources merge by one rule, _merge.
"""

from __future__ import annotations

import json
import sys

from ..record import Record, score_title
from . import arxiv, crossref, openalex

REGISTRY = {
    "arxiv": arxiv,
    "crossref": crossref,
    "openalex": openalex,
}

__all__ = ["Record", "score_title", "REGISTRY", "enabled", "search_all", "exact", "enrich"]


def enabled(names, configured) -> list[str]:
    """Resolve --source / sources.enabled to real module names, loudly."""
    wanted = names or configured or list(REGISTRY)
    if isinstance(wanted, str):
        wanted = [p.strip() for p in wanted.split(",") if p.strip()]
    out, unknown = [], []
    for n in wanted:
        (out if n in REGISTRY else unknown).append(n)
    if unknown:
        print(f"paperctl: unknown source(s): {', '.join(unknown)} "
              f"(have: {', '.join(REGISTRY)})", file=sys.stderr)
    return out


def _merge(into: Record, other: Record) -> Record:
    """Fill `into`'s empty fields from `other`. The first source to report a field wins."""
    for f in Record.__dataclass_fields__:
        if f != "score" and not getattr(into, f) and getattr(other, f):
            setattr(into, f, getattr(other, f))
    into.score = max(into.score, other.score)
    return into


def _ask(name: str, what: str, call):
    try:
        return call()
    except Exception as e:
        print(f"paperctl: {name} {what} failed: {type(e).__name__}: {e}", file=sys.stderr)
        return None


def search_all(fetch, query: str, names: list[str], limit: int = 10) -> list[Record]:
    """Query several sources and merge results for the same paper."""
    merged: dict[str, Record] = {}
    for name in names:
        for rec in _ask(name, "search", lambda: REGISTRY[name].search(fetch, query, limit)) or []:
            key = rec.ident
            merged[key] = _merge(merged[key], rec) if key in merged else rec
    return sorted(merged.values(), key=lambda r: -r.score)


def exact(fetch, kind: str, value: str, names: list[str]) -> Record | None:
    """The record for one arXiv id or DOI (`kind`), from the first enabled source that answers it."""
    for name in names:
        mod = REGISTRY[name]
        if value and kind in mod.ANSWERS:
            rec = _ask(name, "lookup", lambda: mod.fetch_one(fetch, value))
            if rec:
                return rec
    return None


# What a record needs to be both citable and readable: a venue and a PDF.
_WANTED = ("venue", "pdf_url")


def enrich(fetch, rec: Record, names: list[str]) -> Record:
    """Fill gaps in a record from the other enabled sources that know its DOI.

    arXiv knows the PDF but often not the journal it later appeared in;
    Crossref knows the journal but has no PDF. A record that has been through
    both cites correctly *and* reads locally.
    """
    placeholder = rec.venue if rec.venue == arxiv.PREPRINT else ""
    if rec.doi and placeholder:
        rec.venue = ""                  # published since: let a DOI source name the journal
    for name in names:
        mod = REGISTRY[name]
        if not rec.doi or name == rec.source or "doi" not in mod.ANSWERS:
            continue
        if all(getattr(rec, f) for f in _WANTED):
            break
        other = _ask(name, "lookup", lambda: mod.fetch_one(fetch, rec.doi))
        if other:
            score = rec.score
            _merge(rec, other).score = score
    rec.venue = rec.venue or placeholder
    return rec


def _selftest() -> None:
    """Parsers hand identity raw ids; exact/enrich/search_all honour --source, merge once, survive a dead source.

    Each source's parser hands identity the raw id shape it gets, and gets back one form."""
    import contextlib
    import io

    from . import page  # noqa: F401  (imported so a syntax error here fails the selftest)
    from .. import links

    atom = ("<feed><title>ArXiv Query: x</title><entry><id>http://arxiv.org/abs/solv-int/9901001v1</id>"
            "<title>Old Style</title><published>1999-01-05</published></entry></feed>")
    rec = arxiv._parse(arxiv._entries(atom)[0])
    assert (rec.arxiv_id, rec.url) == ("solv-int/9901001", "https://arxiv.org/abs/solv-int/9901001"), rec

    w = {"title": "T", "ids": {"doi": "https://doi.org/10.1234/ABC"},
         "best_oa_location": {"landing_page_url": "https://arxiv.org/abs/2506.19243v3"}}
    rec = openalex._parse(w)
    assert (rec.doi, rec.arxiv_id) == ("10.1234/abc", "2506.19243"), rec

    assert links.normalize("http://arxiv.org/pdf/2506.19243v2.pdf") == "https://arxiv.org/abs/2506.19243"
    assert links.normalize("https://www.arxiv.org/abs/hep-th/9901001v2?context=x") == \
        "https://arxiv.org/abs/hep-th/9901001"

    class Fake:
        """Canned responses by URL substring; an Exception value is raised."""

        def __init__(self, routes):
            self.routes, self.asked = routes, []

        def get_text(self, url, **k):
            self.asked.append(url)
            for frag, out in self.routes.items():
                if frag in url:
                    if isinstance(out, Exception):
                        raise out
                    return out
            raise AssertionError(f"unexpected fetch: {url}")

    xref = json.dumps({"message": {"DOI": "10.1234/ABC", "title": ["A Paper"],
                                   "container-title": ["J. Things"]}})
    oalex = json.dumps({"title": "A Paper", "ids": {"doi": "https://doi.org/10.1234/abc"},
                        "best_oa_location": {"pdf_url": "https://oa.org/a.pdf"}})
    net = Fake({"api.crossref.org": xref, "api.openalex.org": oalex})
    rec = exact(net, "doi", "10.1234/abc", ["arxiv", "crossref", "openalex"])
    assert (rec.source, rec.venue, rec.pdf_url) == ("crossref", "J. Things", ""), rec
    enrich(net, rec, ["arxiv", "crossref", "openalex"])
    assert (rec.venue, rec.pdf_url, rec.score) == ("J. Things", "https://oa.org/a.pdf", 1.0), rec
    assert sum("crossref" in u for u in net.asked) == 1         # enrich never re-asks the record's own source

    pre = Record(title="A Paper", doi="10.1234/abc", arxiv_id="2506.19243", venue=arxiv.PREPRINT,
                 pdf_url="https://arxiv.org/pdf/2506.19243", source="arxiv", score=1.0)
    enrich(Fake({"api.crossref.org": xref}), pre, ["arxiv", "crossref"])
    assert pre.venue == "J. Things", pre                         # published: the journal replaces the placeholder
    alone = Record(title="A Paper", doi="10.1234/abc", venue=arxiv.PREPRINT, source="arxiv")
    with contextlib.redirect_stderr(io.StringIO()):
        enrich(Fake({"api.crossref.org": OSError("down")}), alone, ["arxiv", "crossref"])
    assert alone.venue == arxiv.PREPRINT                         # nobody knew better: placeholder kept

    net = Fake({"api.openalex.org": oalex})                       # --source openalex: crossref is never asked
    assert exact(net, "doi", "10.1234/abc", ["openalex"]).source == "openalex"
    assert exact(net, "arxiv", "2506.19243", ["openalex"]) is None and len(net.asked) == 1

    down = Fake({"export.arxiv.org": OSError("down"),
                 "api.crossref.org": json.dumps({"message": {"items": [
                     {"DOI": "10.1234/abc", "title": ["A Paper"]}]}}),
                 "api.openalex.org": json.dumps({"results": [
                     {"title": "A Paper", "ids": {"doi": "10.1234/ABC"}, "publication_year": 2024}]})})
    with contextlib.redirect_stderr(io.StringIO()) as err:
        found = search_all(down, "A Paper", ["arxiv", "crossref", "openalex"])
    assert "arxiv search failed" in err.getvalue()             # a dead source costs only its results
    assert [(r.doi, r.year, r.source) for r in found] == [("10.1234/abc", "2024", "crossref")], found
    print("sources selftest: ok")
