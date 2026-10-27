"""Metadata sources, behind one shape.

Every source module exposes the same two functions:

    search(fetch, query, limit) -> [Record]       discovery, may be empty
    fetch_one(fetch, ident)     -> Record | None  exact lookup by id/doi/url

Adding a journal API is one new file plus one line in REGISTRY. No caller
changes, and `--source` / `sources.enabled` pick which ones run without anybody
editing an if/elif chain.

A source that is down returns nothing and says so on stderr. It never raises
into the caller: losing Crossref should cost the Crossref results, not the run.
"""

from __future__ import annotations

import sys

from ..record import Record, score_title
from . import arxiv, crossref, openalex

REGISTRY = {
    "arxiv": arxiv,
    "crossref": crossref,
    "openalex": openalex,
}

__all__ = ["Record", "score_title", "REGISTRY", "enabled", "search_all"]


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


def search_all(fetch, query: str, names: list[str], limit: int = 10) -> list[Record]:
    """Query several sources and merge. First source to report a field wins."""
    merged: dict[str, Record] = {}
    for name in names:
        try:
            found = REGISTRY[name].search(fetch, query, limit)
        except Exception as e:
            print(f"paperctl: {name} search failed: {type(e).__name__}: {e}",
                  file=sys.stderr)
            continue
        for rec in found:
            key = rec.ident
            if key not in merged:
                merged[key] = rec
                continue
            have = merged[key]
            for f in rec.__dataclass_fields__:
                if f == "score":
                    continue
                if not getattr(have, f) and getattr(rec, f):
                    setattr(have, f, getattr(rec, f))
            have.score = max(have.score, rec.score)
    return sorted(merged.values(), key=lambda r: -r.score)


def _selftest() -> None:
    """Each source's parser hands identity the raw id shape it gets, and gets back one form."""
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
    print("sources selftest: ok")
