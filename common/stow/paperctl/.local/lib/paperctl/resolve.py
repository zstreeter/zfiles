"""Work out what the user meant by one string, then go and find it.

`paperctl add` takes a title, an arXiv id, a DOI or a URL and must do the right
thing with all four without being told which it got. Sniffing beats a --type
flag here: the four shapes are unambiguous, and requiring the flag would make
the common case (paste a link) the awkward one.
"""

from __future__ import annotations

import re
import sys

from . import identity, links, sources
from .record import Record
from .sources import page


def kind_of(text: str) -> str:
    """One of: arxiv, doi, url, title."""
    t = (text or "").strip()
    if identity.arxiv_id(t):
        return "arxiv"
    if re.match(r"^(doi:)?10\.\d{4,9}/", t, re.I):
        return "doi"
    if re.match(r"^(https?://|www\.)", t, re.I):
        return "url"
    return "title"


def resolve(fetch, text: str, names: list[str],
            limit: int = 8) -> tuple[Record | None, list[Record]]:
    """Return (best, alternatives).

    `alternatives` is only populated for a title search, where the caller may
    want to disambiguate. The three exact forms either resolve or do not.
    """
    text = (text or "").strip()
    kind = kind_of(text)

    if kind == "arxiv":
        return sources.exact(fetch, "arxiv", identity.arxiv_id(text), names), []

    if kind == "doi":
        return sources.exact(fetch, "doi", identity.doi(text), names), []

    if kind == "url":
        url = links.normalize(text)
        rec = (sources.exact(fetch, "arxiv", identity.arxiv_id(url), names)
               or sources.exact(fetch, "doi", identity.doi(url), names))
        if rec:
            return rec, []
        if links.is_shortener(url):
            expanded = fetch.final_url(url)
            if links.normalize(expanded) != url:
                return resolve(fetch, expanded, names, limit)
        rec = page.fetch_one(fetch, url)
        if rec:
            return rec, []
        return Record(title="", url=url, source="unresolved"), []

    found = sources.search_all(fetch, text, names, limit)
    if not found:
        return None, []
    best = found[0]
    if best.score < 0.55:
        print(f"paperctl: best match scored {best.score:.2f}, which is weak:\n"
              f"          {best.title}\n"
              f"          Use `paperctl search-web` to pick deliberately.",
              file=sys.stderr)
    return best, found[1:]


def _selftest() -> None:
    """kind_of routes every `paperctl add` input; pin each shape it must tell apart."""
    cases = {
        "2506.19243": "arxiv", "arXiv:2506.19243v2": "arxiv",
        "https://arxiv.org/abs/2506.19243": "arxiv",
        "10.1038/nature14539": "doi", "doi:10.1038/nature14539": "doi",
        "https://doi.org/10.1038/nature14539": "url", "www.example.com/paper": "url",
        "Attention is all you need": "title", "2506.19243 transformers": "title", "": "title",
    }
    for text, kind in cases.items():
        assert kind_of(text) == kind, (text, kind_of(text))
    print("resolve selftest: ok")
