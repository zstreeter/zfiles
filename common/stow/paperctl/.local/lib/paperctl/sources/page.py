"""Last resort: read the publisher's own page for citation_* meta tags.

Google Scholar's indexing tags are near-universal on journal pages, so this
rescues papers that have no DOI and no arXiv id -- workshop PDFs, lab pages,
institutional repositories. Tried only after the real sources have failed,
because it is a full page fetch to maybe learn a title.
"""

from __future__ import annotations

import html
import re

from ..record import Record


def _meta(doc: str, name: str) -> str:
    """One citation_* value. Attribute order varies by publisher."""
    for pat in (rf'<meta[^>]+name=["\']{name}["\'][^>]*content=["\'](.*?)["\']',
                rf'<meta[^>]+content=["\'](.*?)["\'][^>]*name=["\']{name}["\']'):
        m = re.search(pat, doc, re.I | re.S)
        if m:
            return html.unescape(" ".join(m.group(1).split()))
    return ""


def _metas(doc: str, name: str) -> list[str]:
    return [html.unescape(" ".join(v.split())) for v in re.findall(
        rf'<meta[^>]+name=["\']{name}["\'][^>]*content=["\'](.*?)["\']',
        doc, re.I | re.S)]


def fetch_one(fetch, url: str) -> Record | None:
    # A .pdf link has no HTML to scrape, and fetching it would pull the whole
    # binary just to fail a regex.
    if url.lower().split("?")[0].endswith(".pdf"):
        return None
    try:
        doc = fetch.get_text(url, accept="text/html")
    except Exception:
        return None

    title = _meta(doc, "citation_title")
    if not title:
        m = re.search(r"<title[^>]*>(.*?)</title>", doc, re.I | re.S)
        title = html.unescape(" ".join(m.group(1).split()))[:200] if m else ""
    if not title:
        return None

    pdf = _meta(doc, "citation_pdf_url")
    return Record(
        title=title,
        authors=_metas(doc, "citation_author"),
        year=(_meta(doc, "citation_publication_date")
              or _meta(doc, "citation_date"))[:4],
        venue=_meta(doc, "citation_journal_title")
              or _meta(doc, "citation_conference_title"),
        doi=_meta(doc, "citation_doi").lower(),
        url=url,
        pdf_url=pdf,
        source="page",
        score=0.5,      # scraped, so never outranks a real source's answer
    )
