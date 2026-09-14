"""The one paper-shaped value, and how well a result matches what was asked.

Separate from sources/ so that sources/__init__.py can import the source
modules while the source modules import Record, without the two forming a
cycle.
"""

from __future__ import annotations

import difflib
import re
from dataclasses import asdict, dataclass, field


@dataclass
class Record:
    """One paper, however it was found. Every field optional but `title`."""

    title: str = ""
    authors: list[str] = field(default_factory=list)
    year: str = ""
    venue: str = ""
    doi: str = ""
    arxiv_id: str = ""
    url: str = ""
    pdf_url: str = ""
    abstract: str = ""
    volume: str = ""
    pages: str = ""
    publisher: str = ""
    source: str = ""
    score: float = 0.0

    def to_dict(self) -> dict:
        return asdict(self)

    @property
    def ident(self) -> str:
        """Stable identity for dedupe across sources.

        DOI outranks arXiv id: a preprint and its published version share a DOI
        but not an arXiv id, and merging those two is correct.
        """
        return (self.doi.lower() if self.doi
                else f"arxiv:{self.arxiv_id}" if self.arxiv_id
                else (self.url.lower() or self.title.lower()))


def _norm(s: str) -> str:
    return " ".join(re.sub(r"[^\w\s]", " ", (s or "").lower()).split())


def score_title(query: str, title: str) -> float:
    """How well a result title answers the query. 0..1, higher is better.

    The subtitle split is load-bearing. Searching "Attention is all you need"
    once ranked "Attention Is All You Need Until You Need Retention" above the
    real transformer paper: the decoy contains the query as a prefix and is
    longer, and a plain similarity ratio punishes the exact match for being
    short while rewarding the decoy for overlapping a lot. Scoring the part
    before the colon as well, and keeping the better of the two, means a paper
    whose main title IS the query wins outright.
    """
    q, t = _norm(query), _norm(title)
    if not q or not t:
        return 0.0
    if q == t:
        return 1.0
    ratio = difflib.SequenceMatcher(None, q, t).ratio()
    head = _norm(title.split(":", 1)[0])
    if head and head != t:
        ratio = max(ratio, difflib.SequenceMatcher(None, q, head).ratio())
    # An exact main-title hit beats anything fuzzy, so that a decoy cannot win
    # on sheer length of overlap.
    if head == q:
        return 0.99
    return ratio
