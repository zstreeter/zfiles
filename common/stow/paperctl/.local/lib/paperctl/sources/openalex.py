"""OpenAlex -- the widest net, and the one that knows where the free copy is.

Covers preprints, theses and conference papers that Crossref misses, and its
`best_oa_location` often finds an open copy when Unpaywall's DOI lookup has
nothing. Its titles are the least clean of the three, so it merges last.
"""

from __future__ import annotations

import json
import urllib.parse

from ..record import Record, score_title

API = "https://api.openalex.org/works"


def _abstract(inverted: dict | None) -> str:
    """OpenAlex ships abstracts as {word: [positions]}, for licensing reasons.

    Rebuilding costs nothing and the abstract is what makes a search result
    judgeable without opening it.
    """
    if not inverted:
        return ""
    slots: dict[int, str] = {}
    for word, positions in inverted.items():
        for p in positions:
            slots[p] = word
    return " ".join(slots[i] for i in sorted(slots))


def _parse(w: dict) -> Record | None:
    title = " ".join((w.get("title") or w.get("display_name") or "").split())
    if not title:
        return None
    ids = w.get("ids") or {}
    doi = (ids.get("doi") or "").replace("https://doi.org/", "").lower()
    loc = w.get("best_oa_location") or w.get("primary_location") or {}
    source = loc.get("source") or {}
    arxiv_id = ""
    landing = loc.get("landing_page_url") or ""
    if "arxiv.org/abs/" in landing:
        arxiv_id = landing.rsplit("/", 1)[-1]
    return Record(
        title=title,
        authors=[(a.get("author") or {}).get("display_name", "")
                 for a in (w.get("authorships") or [])
                 if (a.get("author") or {}).get("display_name")],
        year=str(w.get("publication_year") or ""),
        venue=source.get("display_name", "") or "",
        doi=doi,
        arxiv_id=arxiv_id,
        url=landing or (f"https://doi.org/{doi}" if doi else ""),
        pdf_url=loc.get("pdf_url") or "",
        abstract=_abstract(w.get("abstract_inverted_index")),
        volume=(w.get("biblio") or {}).get("volume") or "",
        pages="-".join(p for p in ((w.get("biblio") or {}).get("first_page"),
                                   (w.get("biblio") or {}).get("last_page")) if p),
        publisher=source.get("host_organization_name", "") or "",
        source="openalex",
    )


_SELECT = ("id,ids,title,display_name,publication_year,authorships,biblio,"
           "primary_location,best_oa_location,abstract_inverted_index")


def search(fetch, query: str, limit: int = 10) -> list[Record]:
    # search on title_and_abstract, not the default fulltext index, for the
    # same reason as Crossref: citing papers should not outrank the cited one.
    q = urllib.parse.urlencode({
        "filter": f"title_and_abstract.search:{query}",
        "per-page": limit,
        "select": _SELECT,
    })
    data = json.loads(fetch.get_text(f"{API}?{q}", accept="application/json"))
    out = []
    for w in data.get("results") or []:
        rec = _parse(w)
        if rec:
            rec.score = score_title(query, rec.title)
            out.append(rec)
    return out


def fetch_one(fetch, ident: str) -> Record | None:
    """Accepts a DOI, an OpenAlex id, or an arXiv id."""
    from . import crossref
    key = ""
    doi = crossref.doi_of(ident)
    if doi:
        key = f"doi:{doi}"
    elif ident.strip().upper().startswith("W"):
        key = ident.strip()
    if not key:
        return None
    data = json.loads(fetch.get_text(
        f"{API}/{urllib.parse.quote(key)}?select={_SELECT}",
        accept="application/json"))
    rec = _parse(data)
    if rec:
        rec.score = 1.0
    return rec
