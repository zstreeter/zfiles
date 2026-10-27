"""One paper into one folder, however it was found.

`paperctl add` gets a typed query, `mail thread` a link someone shared, `pull` an
alphaXiv bookmark. All three are the same act -- work out which paper it is,
fill in what the sources know, file it, try for a PDF -- so all three call
file() and differ only in where the reference came from and who to credit.

What file() decides, so no caller does:
  kind        what the reference was (arxiv, doi, ieee, nature, ...): it is
              stored on the entry, and acquire needs it (IEEE -> needs-sso)
  shortcut    a reference whose arXiv id or DOI is already filed with a PDF
              costs no network at all
  dry_run     resolve and enrich (reads), write and download nothing
"""

from __future__ import annotations

from pathlib import Path

from . import identity, library, links, resolve, sources


def kind_of(ref: str) -> str:
    """arxiv, doi or title for bare ids and titles; the publisher kind for a paper URL."""
    kind = resolve.kind_of(ref)
    if kind == "url":
        host_kind, is_paper = links.classify(links.normalize(ref))
        return host_kind if is_paper else "url"
    return kind


def file(cfg, fetch, ref: str, dest: Path, names: list[str], dry_run: bool = False,
         provenance: dict | None = None):
    """File the paper `ref` names. Returns (entry, alternatives).

    entry["status"] is a library status, or "unresolved" when no source knew
    the reference (nothing is written then). `alternatives` are the other
    candidates for a title search, best first.
    """
    have = library.find(dest, identity.ids_of_text(ref))
    if have and library.has_pdf(have):
        return {**have, "note": "already in this folder"}, []
    rec, alternatives = resolve.resolve(fetch, ref, names)
    if rec is None:
        return {"status": "unresolved", "query": ref}, []
    rec = sources.enrich(fetch, rec, names)
    entry = library.add(cfg, fetch, rec, dest, dry_run=dry_run, kind=kind_of(ref),
                        provenance=provenance)
    return entry, alternatives


def _selftest() -> None:
    """Every caller gets the same kind; a filed paper costs nothing; IEEE via `add` says needs-sso."""
    import tempfile

    from .library import _Cfg, _NoNet, save_index

    for ref, kind in {
        "2506.19243": "arxiv", "10.1038/nature14539": "doi", "Attention is all you need": "title",
        "https://ieeexplore.ieee.org/document/1234567": "ieee",
        "https://doi.org/10.1038/nature14539": "doi",
        "https://arxiv.org/abs/2506.19243": "arxiv",
        "https://example.org/some/page": "url",
    }.items():
        assert kind_of(ref) == kind, (ref, kind_of(ref), kind)

    class Unreachable:
        def get_text(self, *a, **k):
            raise AssertionError("a filed paper must not touch the network")
        get = get_text

    class IeeePage(_NoNet):
        """An IEEE landing page with citation tags; every PDF attempt fails."""

        def get_text(self, url, **k):
            assert "ieeexplore" in url, url
            return ('<meta name="citation_title" content="A Filter Bank">'
                    '<meta name="citation_author" content="Ada Lovelace">')

    with tempfile.TemporaryDirectory() as t:
        cfg, dest = _Cfg(Path(t)), Path(t) / "F"
        save_index(dest, {"entries": [{"ident": "arxiv:2506.19243", "arxiv_id": "2506.19243",
                                       "citekey": "k", "title": "T", "status": "downloaded"}]})
        entry, _ = file(cfg, Unreachable(), "https://arxiv.org/abs/2506.19243v4", dest, ["arxiv"])
        assert entry["note"] == "already in this folder", entry

        entry, _ = file(cfg, IeeePage(), "https://ieeexplore.ieee.org/document/1234567", dest, [])
        assert (entry["status"], entry["kind"], entry["title"]) == ("needs-sso", "ieee", "A Filter Bank"), entry

        entry, _ = file(cfg, IeeePage(), "https://ieeexplore.ieee.org/document/7654321", dest, [],
                        dry_run=True)
        assert entry["status"] == "would-add" and len(library.entries(cfg, dest)) == 2

        entry, _ = file(cfg, _NoNet(), "No Such Paper Anywhere", dest, [])
        assert entry == {"status": "unresolved", "query": "No Such Paper Anywhere"}, entry
    print("ingest selftest: ok")


if __name__ == "__main__":
    _selftest()
