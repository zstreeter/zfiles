"""arXiv, through the Atom export API.

The only source of the three that reliably hands back a PDF, so it is tried
first everywhere. No key, no registration; the one rule is a request every few
seconds, which net.Fetch's backoff already respects.
"""

from __future__ import annotations

import html
import re
import urllib.parse

from ..record import Record, score_title

API = "http://export.arxiv.org/api/query"

# 2506.19243, 2506.19243v2, or the pre-2007 form math.AP/0701001.
ID_RE = re.compile(r"(?:arxiv[:/]|abs/|pdf/)?"
                   r"(\d{4}\.\d{4,5}|[a-z-]+(?:\.[A-Z]{2})?/\d{7})(v\d+)?",
                   re.I)


def id_of(text: str) -> str:
    """Pull an arXiv id out of an id, a URL, or a citation string."""
    if "arxiv" not in (text or "").lower() and not re.fullmatch(
            r"\s*\d{4}\.\d{4,5}(v\d+)?\s*", text or ""):
        return ""
    m = ID_RE.search(text or "")
    return m.group(1) if m else ""


def _entries(xml: str) -> list[str]:
    """Each <entry> body.

    Scoping to <entry> is not tidiness. The Atom feed carries its own <title>
    -- "ArXiv Query: search_query=all:..." -- before the first entry, and an
    unscoped title regex grabs that instead of the paper's. It then poisons the
    heading, the BibTeX entry and the PDF filename all at once, and looks like
    a search bug rather than a parsing one.
    """
    return re.findall(r"<entry>(.*?)</entry>", xml, re.S)


def _tag(body: str, name: str) -> str:
    m = re.search(rf"<{name}\b[^>]*>(.*?)</{name}>", body, re.S)
    return html.unescape(" ".join(m.group(1).split())) if m else ""


def _parse(body: str) -> Record | None:
    title = _tag(body, "title")
    if not title:
        return None
    aid = ""
    m = re.search(r"<id>.*?abs/([^<v]+)", body, re.S)
    if m:
        aid = m.group(1).strip()
    return Record(
        title=title,
        authors=[html.unescape(" ".join(a.split()))
                 for a in re.findall(r"<name>(.*?)</name>", body, re.S)],
        year=_tag(body, "published")[:4],
        venue=_tag(body, "arxiv:journal_ref") or "arXiv preprint",
        doi=_tag(body, "arxiv:doi"),
        arxiv_id=aid,
        url=f"https://arxiv.org/abs/{aid}" if aid else "",
        pdf_url=f"https://arxiv.org/pdf/{aid}" if aid else "",
        abstract=_tag(body, "summary"),
        source="arxiv",
    )


def search(fetch, query: str, limit: int = 10) -> list[Record]:
    # ti: rather than all: -- searching every field turns a title query into a
    # full-text query, and a paper that merely cites the one being looked for
    # then outranks it.
    q = urllib.parse.urlencode({
        "search_query": f'ti:"{query}"' if " " in query else f"all:{query}",
        "start": 0,
        "max_results": limit,
    })
    xml = fetch.get_text(f"{API}?{q}", accept="application/atom+xml")
    out = []
    for body in _entries(xml):
        rec = _parse(body)
        if rec:
            rec.score = score_title(query, rec.title)
            out.append(rec)
    # A quoted-title search that finds nothing is common for slightly misquoted
    # titles; fall back to the loose form rather than reporting no such paper.
    if not out and " " in query:
        q = urllib.parse.urlencode({"search_query": f"all:{query}",
                                    "start": 0, "max_results": limit})
        for body in _entries(fetch.get_text(f"{API}?{q}",
                                            accept="application/atom+xml")):
            rec = _parse(body)
            if rec:
                rec.score = score_title(query, rec.title)
                out.append(rec)
    return out


def fetch_one(fetch, ident: str) -> Record | None:
    aid = id_of(ident) or ident.strip()
    if not aid:
        return None
    xml = fetch.get_text(f"{API}?id_list={urllib.parse.quote(aid)}",
                         accept="application/atom+xml")
    for body in _entries(xml):
        rec = _parse(body)
        if rec:
            rec.score = 1.0
            return rec
    return None
