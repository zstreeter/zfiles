"""Crossref -- the publisher-authoritative record for anything with a DOI.

Best metadata of the three sources and almost never a PDF, which is exactly the
opposite of arXiv. Between them most papers end up both correctly described and
locally readable.
"""

from __future__ import annotations

import json
import re
import urllib.parse

from ..record import Record, score_title

API = "https://api.crossref.org/works"

DOI_RE = re.compile(r"\b(10\.\d{4,9}/[^\s\"'<>]+)", re.I)


def doi_of(text: str) -> str:
    """Pull a DOI out of a bare DOI, a doi.org URL, or a publisher URL."""
    m = DOI_RE.search(urllib.parse.unquote(text or ""))
    if not m:
        return ""
    # Trailing punctuation is almost always sentence punctuation that got
    # swept up, not part of the DOI.
    return m.group(1).rstrip(".,;)»\"'").lower()


def _parse(msg: dict) -> Record | None:
    title = " ".join((msg.get("title") or [""])[0].split())
    if not title:
        return None
    authors = [" ".join(x for x in (a.get("given"), a.get("family")) if x)
               for a in (msg.get("author") or [])]
    parts = ((msg.get("issued") or {}).get("date-parts") or [[None]])[0]
    pdf = ""
    for link in msg.get("link") or []:
        if link.get("content-type") == "application/pdf":
            pdf = link.get("URL", "")
            break
    doi = (msg.get("DOI") or "").lower()
    return Record(
        title=title,
        authors=authors,
        year=str(parts[0]) if parts and parts[0] else "",
        venue=(msg.get("container-title") or [""])[0],
        doi=doi,
        url=msg.get("URL") or (f"https://doi.org/{doi}" if doi else ""),
        pdf_url=pdf,
        abstract=re.sub(r"<[^>]+>", "", msg.get("abstract") or "").strip(),
        volume=msg.get("volume", ""),
        pages=msg.get("page", ""),
        publisher=msg.get("publisher", ""),
        source="crossref",
    )


def search(fetch, query: str, limit: int = 10) -> list[Record]:
    # query.bibliographic rather than query: the general index matches on
    # abstract and references too, so a survey that cites the target paper
    # outranks the paper itself.
    q = urllib.parse.urlencode({
        "query.bibliographic": query,
        "rows": limit,
        "select": "DOI,title,author,issued,container-title,volume,page,"
                  "publisher,URL,abstract,link",
    })
    data = json.loads(fetch.get_text(f"{API}?{q}", accept="application/json"))
    out = []
    for msg in (data.get("message") or {}).get("items", []):
        rec = _parse(msg)
        if rec:
            rec.score = score_title(query, rec.title)
            out.append(rec)
    return out


def fetch_one(fetch, ident: str) -> Record | None:
    doi = doi_of(ident)
    if not doi:
        return None
    data = json.loads(fetch.get_text(f"{API}/{urllib.parse.quote(doi)}",
                                     accept="application/json"))
    rec = _parse(data.get("message") or {})
    if rec:
        rec.score = 1.0
    return rec
