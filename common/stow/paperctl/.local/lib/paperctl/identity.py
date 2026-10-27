"""What paper is this? One answer, for every caller.

A paper arrives as an arXiv id, a DOI, a URL carrying either, or a title, and
every source reports ids in its own shape: arXiv's Atom <id> carries a version,
an OpenAlex landing URL may too, doi.org URLs are percent-encoded. Anything that
parses, stores or compares an identity goes through here, so "the same paper"
means one thing in the index, in search merging and in the PDF filename.

Works on Records and on index entries alike: both expose doi / arxiv_id / url /
title, one as attributes and the other as keys.
"""

from __future__ import annotations

import re
import urllib.parse

_NEW = r"\d{4}\.\d{4,5}"
# Pre-2007 ids: archive[.SUBJECT]/YYMMNNN, e.g. hep-th/9901001, math.CV/0101001.
_OLD = r"[a-z][a-z-]*(?:\.[A-Z]{2})?/\d{7}"
_ARXIV = re.compile(rf"(?:arxiv[:/]|abs/|pdf/)?({_NEW}|{_OLD})(?:v\d+)?", re.I)
_DOI = re.compile(r"\b(10\.\d{4,9}/[^\s\"'<>]+)", re.I)


def arxiv_id(text: str) -> str:
    """The arXiv id in an id, a URL or a citation string, version stripped; or "".

    A bare new-style id counts on its own; anything else must mention arXiv,
    because "1234.56789" inside an unrelated URL is not a claim about arXiv.
    """
    t = (text or "").strip()
    if "arxiv" not in t.lower() and not re.fullmatch(rf"{_NEW}(v\d+)?", t):
        return ""
    m = _ARXIV.search(t)
    return m.group(1) if m else ""


def doi(text: str) -> str:
    """The DOI in a bare DOI, a doi: prefix, a doi.org URL or a publisher URL; or ""."""
    m = _DOI.search(urllib.parse.unquote(text or ""))
    return m.group(1).rstrip(".,;)»\"'").lower() if m else ""


def _get(x, name: str) -> str:
    v = x.get(name) if isinstance(x, dict) else getattr(x, name, "")
    return str(v or "")


def _strong(x) -> tuple[str, str]:
    return doi(_get(x, "doi")), arxiv_id(_get(x, "arxiv_id"))


def key(x) -> str:
    """The stored identity: DOI, else arxiv:<id>, else URL, else title.

    DOI outranks the arXiv id: a preprint and its published version share a
    DOI once both are known, and merging those two is correct.
    """
    d, a = _strong(x)
    return (d if d else f"arxiv:{a}" if a
            else (_get(x, "url").lower() or _get(x, "title").lower()))


def ids(x) -> set[str]:
    """Every identity `x` can be matched on. Weak ids only when there is no strong one."""
    d, a = _strong(x)
    strong = {i for i in (d, f"arxiv:{a}" if a else "") if i}
    return strong or ({key(x)} - {""})


def ids_of_text(text: str) -> set[str]:
    """The strong ids a user-supplied string carries, before anything is looked up."""
    d, a = doi(text), arxiv_id(text)
    return {i for i in (d, f"arxiv:{a}" if a else "") if i}


def same(a, b) -> bool:
    """Same paper: they share a DOI, an arXiv id, or (lacking both) a URL/title."""
    return bool(ids(a) & ids(b))


def _selftest() -> None:
    for text, want in {
        "2506.19243": "2506.19243", "2506.19243v2": "2506.19243",
        "arXiv:2506.19243v3": "2506.19243",
        "https://arxiv.org/abs/2506.19243v2": "2506.19243",
        "https://arxiv.org/pdf/2506.19243v2.pdf": "2506.19243",
        "http://arxiv.org/abs/solv-int/9901001v1": "solv-int/9901001",
        "https://arxiv.org/abs/hep-th/9901001": "hep-th/9901001",
        "arXiv:math.CV/0101001": "math.CV/0101001",
        "https://example.org/files/2506.19243": "", "2506.19243 transformers": "",
        "": "",
    }.items():
        assert arxiv_id(text) == want, (text, arxiv_id(text), want)
    for text, want in {
        "10.1038/nature14539": "10.1038/nature14539",
        "doi:10.1038/NATURE14539": "10.1038/nature14539",
        "https://doi.org/10.1038/nature14539.": "10.1038/nature14539",
        "https://doi.org/10.1002%2Fanie.201915678": "10.1002/anie.201915678",
        "https://pubs.acs.org/doi/10.1021/acs.jctc.5b00001": "10.1021/acs.jctc.5b00001",
        "no doi here": "",
    }.items():
        assert doi(text) == want, (text, doi(text), want)

    pre = {"arxiv_id": "2506.19243v2", "title": "T"}
    pub = {"doi": "10.1234/X", "arxiv_id": "2506.19243", "title": "T"}
    only_doi = {"doi": "https://doi.org/10.1234/x"}
    assert key(pre) == "arxiv:2506.19243"
    assert key(pub) == key(only_doi) == "10.1234/x"
    assert same(pre, pub) and same(pub, only_doi) and not same(pre, only_doi)
    assert key({"url": "HTTPS://X.org/p"}) == "https://x.org/p"
    assert not same({"title": "A"}, {"title": "B"}) and same({"title": "A"}, {"title": "a"})
    assert ids({}) == set() and not same({}, {})
    assert ids_of_text("https://arxiv.org/abs/2506.19243v1") == {"arxiv:2506.19243"}
    assert ids_of_text("Attention is all you need") == set()
    print("identity selftest: ok")


if __name__ == "__main__":
    _selftest()
