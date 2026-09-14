"""Pulling links out of mail, and deciding which ones are papers.

The lesson this module exists to encode: a hyperlink in mail lives in the
`href` attribute, and the visible text is usually the paper's *title*, not a
URL. Any pipeline that reads a flattened text rendering of a message body
silently loses every anchored link -- measured, not assumed: routing bodies
through a text-flattening API returned zero URLs for 4 of 22 messages in a real
thread, including the originating mail carrying its two most important links.

So callers must feed this module raw HTML. Mail backends promise that (see
mail/__init__.py), and `paperctl doctor` reports a backend that cannot.
"""

from __future__ import annotations

import html
import re
import urllib.parse
from collections.abc import Sequence
from dataclasses import dataclass, field
from html.parser import HTMLParser

# --------------------------------------------------------------------------
# Shapes we never want in the index
# --------------------------------------------------------------------------

# NOTE: written without a trailing slash. normalize() strips those, so a
# pattern spelled "/owa/" matches nothing. That bug shipped once already.
NOISE_PATTERNS = [
    r"^https?://outlook\.office(365)?\.com/owa\b",
    r"^https?://outlook\.office\.com/mail\b",
    r"^https?://aka\.ms/",
    r"/unsubscribe",
    r"^https?://[^/]*\.?list-manage\.com/",
    r"^https?://clicktime\.symantec\.com/",
    r"\.(gif|png|jpg|jpeg|svg|ico)(\?|$)",
    r"^https?://[^/]*\.?linkedin\.com/(comm|e)/",
]

# Resolved before classification, because the destination decides paper-vs-not.
# lnkd.in dominates in forwarded LinkedIn posts.
SHORTENERS = {
    "lnkd.in", "bit.ly", "t.co", "tinyurl.com", "ow.ly", "buff.ly",
    "goo.gl", "dlvr.it", "trib.al", "rb.gy", "shorturl.at",
}

PAPER_HOST_PATTERNS = [
    (r"arxiv\.org/(abs|pdf)/", "arxiv"),
    (r"^https?://(dx\.)?doi\.org/10\.", "doi"),
    (r"biorxiv\.org/content/", "biorxiv"),
    (r"medrxiv\.org/content/", "medrxiv"),
    (r"openreview\.net/(forum|pdf)", "openreview"),
    (r"ieeexplore\.ieee\.org/(document|abstract/document)/", "ieee"),
    (r"dl\.acm\.org/doi/", "acm"),
    (r"link\.springer\.com/(article|chapter)/", "springer"),
    (r"nature\.com/articles/", "nature"),
    (r"sciencedirect\.com/science/article/", "elsevier"),
    # ACS journal tokens can contain digits (e.g. /aeacb3/article/...), so a
    # bare [a-z]+ misses them.
    (r"pubs\.acs\.org/doi/|pubs\.acs\.org/[a-z0-9]+/article", "acs"),
    (r"pubs\.aip\.org/.*/article", "aip"),
    (r"iopscience\.iop\.org/article/", "iop"),
    (r"journals\.aps\.org/.*/abstract/", "aps"),
    (r"onlinelibrary\.wiley\.com/doi/", "wiley"),
    (r"tandfonline\.com/doi/", "taylorfrancis"),
    (r"royalsocietypublishing\.org/doi/", "royalsociety"),
    (r"jstor\.org/stable/", "jstor"),
    (r"ncbi\.nlm\.nih\.gov/pmc/articles/", "pmc"),
    (r"semanticscholar\.org/paper/", "semanticscholar"),
    (r"proceedings\.mlr\.press/", "pmlr"),
    (r"papers\.nips\.cc/", "neurips"),
    (r"\.pdf(\?|$)", "pdf"),
]

# Clearly worth keeping, clearly not papers.
NONPAPER_KIND_PATTERNS = [
    (r"(youtube\.com/watch|youtu\.be/)", "video"),
    (r"scholar\.google\.[a-z.]+/citations", "author-profile"),
    (r"(mastodon|fosstodon|mathstodon)\.[a-z.]+/", "social"),
    (r"(twitter\.com|x\.com)/[^/]+/status/", "social"),
    (r"linkedin\.com/(posts|feed|pulse)/", "social"),
    (r"github\.com/", "code"),
    (r"gitlab\.com/", "code"),
    (r"huggingface\.co/", "model"),
    (r"(news|blog|substack\.com|medium\.com)", "article"),
]

SAFELINKS_HOST = re.compile(r"safelinks\.protection\.outlook\.com$", re.I)

TRACKING_KEYS = {
    "si", "fbclid", "gclid", "mc_cid", "mc_eid", "ref", "ref_src",
    "originalsubdomain", "trk", "trkinfo", "rss", "feature",
    "exvsurl", "viewmodel",
}


@dataclass
class Link:
    """One deduplicated URL, with provenance back to the mail that shared it."""

    url: str
    anchor: str = ""
    kind: str = "other"
    is_paper: bool = False
    resolved_from: str = ""        # original short URL, if expanded
    first_seen_msg: str = ""
    first_seen_from: str = ""
    first_seen_at: str = ""
    contexts: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "url": self.url, "anchor": self.anchor, "kind": self.kind,
            "is_paper": self.is_paper, "resolved_from": self.resolved_from,
            "first_seen_msg": self.first_seen_msg,
            "first_seen_from": self.first_seen_from,
            "first_seen_at": self.first_seen_at, "contexts": self.contexts,
        }


class _AnchorParser(HTMLParser):
    """Collect (href, anchor_text) pairs plus the plain text of the document."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.pairs: list[tuple[str, str]] = []
        self.text_parts: list[str] = []
        self.saw_any_tag = False
        self._href: str | None = None
        self._buf: list[str] = []
        self._skip = 0

    def handle_starttag(self, tag, attrs):
        self.saw_any_tag = True
        if tag in ("script", "style", "head"):
            self._skip += 1
            return
        if tag == "a":
            for k, v in attrs:
                if k.lower() == "href" and v:
                    self._href = v.strip()
                    self._buf = []
                    break

    def handle_endtag(self, tag):
        if tag in ("script", "style", "head"):
            self._skip = max(0, self._skip - 1)
            return
        if tag == "a" and self._href is not None:
            self.pairs.append((self._href, " ".join("".join(self._buf).split())))
            self._href = None
            self._buf = []
        if tag in ("p", "div", "br", "tr", "li"):
            self.text_parts.append("\n")

    def handle_data(self, data):
        if self._skip:
            return
        if self._href is not None:
            self._buf.append(data)
        self.text_parts.append(data)

    @property
    def text(self) -> str:
        return "".join(self.text_parts)


_BARE_URL_RE = re.compile(r"""(?xi)
    \bhttps?://
    [^\s<>"'()\[\]{}]+
    [^\s<>"'()\[\]{}.,;:!?]
""")


def unwrap_safelinks(url: str) -> str:
    """Defender SafeLinks rewrites every href in inbound mail; recover the target.

    Must happen before anything else looks at the URL. Un-unwrapped, every
    link in a corporate mailbox has the same host, so classification says
    "not a paper" for all of them and dedupe merges links that differ only
    inside the wrapped query parameter.
    """
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:
        return url
    if SAFELINKS_HOST.search(p.netloc or ""):
        inner = urllib.parse.parse_qs(p.query).get("url", [""])[0]
        if inner:
            return urllib.parse.unquote(inner)
    return url


def normalize(url: str) -> str:
    """Canonical form, so the same target dedupes to one entry."""
    url = html.unescape((url or "").strip())
    url = url.rstrip(".,;:)>”’\"'")
    if url.startswith("//"):
        url = "https:" + url
    url = unwrap_safelinks(url)
    try:
        p = urllib.parse.urlsplit(url)
    except ValueError:
        return url

    scheme = "https" if p.scheme in ("http", "https") else p.scheme
    netloc = p.netloc.lower()
    if netloc.startswith("www."):
        netloc = netloc[4:]
    if (scheme == "https" and netloc.endswith(":443")) or \
       (scheme == "http" and netloc.endswith(":80")):
        netloc = netloc.rsplit(":", 1)[0]

    keep = [(k, v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True)
            if not (k.lower().startswith("utm_") or k.lower() in TRACKING_KEYS)]
    query = urllib.parse.urlencode(keep)
    path = p.path.rstrip("/") or "/"

    # arXiv: collapse versioned and pdf forms onto the abs page, so /pdf/2506.1v2
    # and /abs/2506.1 are recognised as one paper.
    m = re.match(r"^/(abs|pdf)/(.+?)(v\d+)?$", path)
    if netloc == "arxiv.org" and m:
        path, query = f"/abs/{m.group(2)}", ""
    if netloc in ("dx.doi.org", "doi.org"):
        netloc, path = "doi.org", path.lower()

    return urllib.parse.urlunsplit((scheme, netloc, path, query, ""))


def is_noise(url: str) -> bool:
    if not url.lower().startswith(("http://", "https://")):
        return True
    return any(re.search(p, url, re.I) for p in NOISE_PATTERNS)


def is_shortener(url: str) -> bool:
    host = urllib.parse.urlsplit(url).netloc.lower()
    return host[4:] in SHORTENERS if host.startswith("www.") else host in SHORTENERS


def classify(url: str, internal: Sequence[str] = ()) -> tuple[str, bool]:
    """Return (kind, is_paper).

    `internal` is a list of regexes for hosts private to whoever is running
    this -- an intranet, a wiki behind SSO. They are checked before the public
    patterns because an internal host can also look like a blog, and they are
    passed in rather than listed here because which hosts are internal is a
    property of the operator, not of paperctl: see links.internal_domains in
    local.toml.
    """
    for pat in internal:
        if re.search(pat, url, re.I):
            return "internal", False
    for pat, kind in PAPER_HOST_PATTERNS:
        if re.search(pat, url, re.I):
            return kind, True
    for pat, kind in NONPAPER_KIND_PATTERNS:
        if re.search(pat, url, re.I):
            return kind, False
    return "other", False


def drop_truncated(urls: list[str]) -> list[str]:
    """Remove URLs that are mid-segment fragments of a longer sibling.

    Mail clients hard-wrap long URLs in plain-text bodies, so a text sweep
    yields 'sciencedirect.com/science/ar' beside the intact
    '.../science/article/pii/S0893608025008640'. Only fragments cut *inside* a
    path segment are dropped -- 'github.com/o/repo' survives even though
    'github.com/o/repo/blob/main' also appears, because that is a real page.
    """
    keep = []
    for u in urls:
        u_parts = urllib.parse.urlsplit(u).path.split("/")
        truncated = False
        for v in urls:
            if v == u or not v.startswith(u):
                continue
            v_parts = urllib.parse.urlsplit(v).path.split("/")
            if len(v_parts) < len(u_parts):
                continue
            tail_u, tail_v = u_parts[len(u_parts) - 1], v_parts[len(u_parts) - 1]
            if tail_u != tail_v and tail_v.startswith(tail_u):
                truncated = True
                break
        if not truncated:
            keep.append(u)
    return keep


def extract_from_html(body_html: str) -> tuple[list[tuple[str, str]], str, bool]:
    """Return ([(url, anchor_text)], plain_text, looks_flattened).

    Anchors first so their more informative link text wins on dedupe, then a
    bare-URL sweep for links that were pasted rather than anchored.

    `looks_flattened` is the alarm: HTML that contains URLs as text but has no
    anchors at all is the signature of a text-flattening body path, not of a
    link-free reply. Gated on URLs actually being present, because a genuine
    reply with no links would otherwise raise it on every run.
    """
    parser = _AnchorParser()
    try:
        parser.feed(body_html)
        parser.close()
    except Exception:
        pass       # malformed markup from some clients; the regex sweep still runs

    flattened = (parser.saw_any_tag and not parser.pairs
                 and "http" in (body_html or "").lower())

    found: list[tuple[str, str]] = []
    seen: set[str] = set()

    for href, anchor in parser.pairs:
        if href.lower().startswith(("mailto:", "tel:", "#", "javascript:")):
            continue
        url = normalize(href)
        if not url.lower().startswith("http") or url in seen:
            continue
        seen.add(url)
        if anchor and anchor.strip().lower().rstrip("/") == url.lower().rstrip("/"):
            anchor = ""        # anchor text that is just the URL adds nothing
        found.append((url, anchor))

    for m in _BARE_URL_RE.finditer(parser.text or body_html):
        url = normalize(m.group(0))
        if url not in seen:
            seen.add(url)
            found.append((url, ""))

    return found, parser.text, flattened


def extract_from_text(text: str) -> list[tuple[str, str]]:
    """Bare-URL sweep for plain-text bodies. Anchors do not exist here."""
    out: list[tuple[str, str]] = []
    seen: set[str] = set()
    for m in _BARE_URL_RE.finditer(text or ""):
        url = normalize(m.group(0))
        if url not in seen:
            seen.add(url)
            out.append((url, ""))
    return out
