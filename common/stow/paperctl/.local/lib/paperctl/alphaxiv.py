"""alphaXiv bookmarks -> the local library. One direction, deliberately.

alphaXiv is where papers are *found* -- the feed, the similar-paper rail, the
comment threads. It is not a library: no citekeys, no notes, no PDF you own, no
bibliography. So its folders are an inbox, and `paperctl pull` drains that inbox
into `~/Library/<Folder>/` where the rest of paperctl already works.

Nothing here writes back to alphaXiv, and nothing here touches references.bib --
that one is Zotero/Better BibTeX's and stays hand-curated. A bookmark is a "look
at this later", which is not the same claim as a bibliography entry, and pushing
them into one would put unread papers in a citation list.

    GET https://api.alphaxiv.org/folders/v3
    Authorization: Bearer $ALPHAXIV_API_KEY   (alphaxiv.org -> Settings -> API Keys)

The response is every folder with its papers inline -- one request for the whole
library, no pagination to walk.

This is the ONLY source in paperctl that needs a credential. arXiv, Crossref and
OpenAlex are open APIs with no key and no registration, and Unpaywall wants a
contact address rather than a key -- which is why that one is a config value and
this one is not.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error

from . import naming
from .sources import arxiv

API = "https://api.alphaxiv.org"
FOLDERS_URL = f"{API}/folders/v3"

# Checked in order. Which one carries the arXiv id is not contractual -- the
# payload has carried it under both names -- and a private upload has it under
# none of them. Sniffing all of them and validating with arxiv.id_of() means a
# renamed field degrades to a title search instead of filing garbage.
ID_KEYS = ("canonicalId", "canonical_id", "universalPaperId",
           "universal_paper_id", "paperVersionId", "version_id")

# Where zfiles keeps every API key: gitignored, chmod 600, seeded by
# common/setup.sh and sourced by shell/env.sh on every shell start. Named here
# only so `doctor` can say where to put the key -- nothing reads the file.
SECRETS_FILE = (os.environ.get("XDG_CONFIG_HOME")
                or os.path.expanduser("~/.config")) + "/shell/secrets.env"


def key() -> str:
    """The API key, from the environment only.

    Deliberately not a paperctl config setting. config.toml is committed, and
    local.toml beside it is gitignored but still inside a stowed repo -- one
    `git add -f` from being published. secrets.env is outside the repo
    entirely, which is a stronger guarantee than an ignore rule. It is also the
    variable the alphaxiv CLI reads, so one export serves both.
    """
    return os.environ.get("ALPHAXIV_API_KEY", "").strip()


def fetch_folders(fetch, api_key: str) -> list[dict]:
    raw = fetch.get_text(FOLDERS_URL, accept="application/json",
                         headers={"Authorization": f"Bearer {api_key}"})
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError(f"expected a list of folders, got {type(data).__name__}")
    return [f for f in data if isinstance(f, dict)]


def papers_of(folder: dict) -> list[dict]:
    return [p for p in (folder.get("papers") or []) if isinstance(p, dict)]


def ident_of(paper: dict) -> tuple[str, str]:
    """(query for resolve.resolve, arxiv id or "").

    The arXiv id is returned separately because it is also the cheap key for
    "already have this one", before any network call is made.
    """
    for k in ID_KEYS:
        aid = arxiv.id_of(str(paper.get(k) or ""))
        if aid:
            return aid, aid
    return naming.clean(paper.get("title") or ""), ""


def probe(cfg, fetch=None) -> tuple[bool, str, str]:
    """(ok, detail, fix) for `paperctl doctor`."""
    api_key = key()
    if not api_key:
        return False, "$ALPHAXIV_API_KEY not set", (
            "mint a key at alphaxiv.org -> Settings -> API Keys, then add\n"
            "           export ALPHAXIV_API_KEY=\"axv1_...\"\n"
            f"         to {SECRETS_FILE} and open a new shell")
    if fetch is None:
        return True, "key set (not checked -- offline)", ""
    try:
        folders = fetch_folders(fetch, api_key)
    except urllib.error.HTTPError as e:
        if e.code in (401, 403):
            return False, f"key rejected ({e.code})", \
                "the key was revoked or mistyped -- issue a new one"
        return False, f"HTTP {e.code}", ""
    except Exception as e:
        return False, f"{type(e).__name__}: {e}", ""
    n = sum(len(papers_of(f)) for f in folders)
    return True, f"{len(folders)} folder(s), {n} bookmarked paper(s)", ""


# --------------------------------------------------------------------------
# Command
# --------------------------------------------------------------------------

def cmd_pull(args, cfg) -> int:
    from . import library, resolve
    from .cli import c, emit, fetcher, sources_for

    api_key = key()
    if not api_key:
        ok, detail, fix = probe(cfg)
        print(f"paperctl: {detail}\n         {fix}", file=sys.stderr)
        return 2

    fetch = fetcher(cfg)
    try:
        folders = fetch_folders(fetch, api_key)
    except urllib.error.HTTPError as e:
        hint = ("  -- the key was revoked or mistyped"
                if e.code in (401, 403) else "")
        print(f"paperctl: alphaXiv returned HTTP {e.code}{hint}", file=sys.stderr)
        return 2
    except Exception as e:
        print(f"paperctl: cannot read alphaXiv folders: {e}", file=sys.stderr)
        return 2

    if args.folder:
        want = args.folder.lower()
        folders = [f for f in folders if want in str(f.get("name") or "").lower()]
        if not folders:
            print(f"paperctl: no alphaXiv folder matching {args.folder!r}",
                  file=sys.stderr)
            return 1

    srcs = sources_for(args, cfg)
    report: list[dict] = []
    lines: list[str] = []
    if args.dry_run:
        lines.append(c("33", "--dry-run: nothing written."))

    for f in folders:
        name = str(f.get("name") or "Bookmarks")
        papers = papers_of(f)
        # --to collapses every alphaXiv folder into one library folder; without
        # it each folder keeps its own name. title_case_filename is what makes
        # that safe -- a folder called "PINNs / blowup" would otherwise nest,
        # and one called "/tmp" would escape the library root entirely.
        dest = library.folder(cfg, args.to or naming.title_case_filename(name))

        # Skip on arxiv_id, not on ident: an arXiv paper that also has a DOI is
        # stored under the DOI, so ident alone would re-resolve it every run.
        known = {e.get("arxiv_id") for e in library.load_index(dest).get("entries", [])
                 if e.get("arxiv_id") and e.get("status") in ("downloaded", "have")}

        added, skipped, missed = [], 0, []
        for p in papers:
            query, aid = ident_of(p)
            if aid and aid in known:
                skipped += 1
                continue
            if not query:
                continue
            if args.dry_run:
                added.append({"title": p.get("title"), "query": query,
                              "status": "would-add"})
                continue
            rec, _alts = resolve.resolve(fetch, query, srcs)
            if rec is None:
                missed.append(p.get("title") or query)
                continue
            rec = resolve.enrich(fetch, rec, srcs)
            added.append(library.add(
                cfg, fetch, rec, dest,
                kind=resolve.kind_of(query),
                provenance={"shared_by": "alphaXiv bookmarks",
                            "shared_at": p.get("addedAt") or p.get("added_at"),
                            "source_url": _abs_url(p)}))

        got = sum(1 for a in added if a.get("status") in ("downloaded", "have"))
        report.append({"alphaxiv_folder": name, "folder": str(dest),
                       "bookmarked": len(papers), "added": len(added),
                       "with_pdf": got, "already_had": skipped,
                       "unresolved": missed, "entries": added})

        lines.append(f"{c('1', name)}  {c('2', str(dest))}")
        lines.append(f"  {len(papers)} bookmarked · "
                     f"{len(added)} {'would be filed' if args.dry_run else 'filed'} · "
                     f"{got} with PDFs · {skipped} already had")
        for m in missed:
            lines.append(f"  {c('33', 'UNRESOLVED')} {m}")

    if not any(r["bookmarked"] for r in report):
        lines.append(c("2", "no bookmarks found -- add some at "
                            "https://www.alphaxiv.org/bookmarks"))
    emit(args, report, lines)
    return 0


def _abs_url(paper: dict) -> str:
    _q, aid = ident_of(paper)
    return f"https://www.alphaxiv.org/abs/{aid}" if aid else ""


def register_cli(sub, add_cmd) -> None:
    """Attach `paperctl pull`. Called by cli.build_parser."""
    p = add_cmd("pull", cmd_pull,
                "pull your alphaXiv bookmarks into the library", dry=True)
    p.add_argument("--folder", metavar="NAME",
                   help="only this alphaXiv folder (substring match); "
                        "default is all of them")
    p.add_argument("--to", metavar="FOLDER",
                   help="file everything into one library folder instead of "
                        "one per alphaXiv folder")
    p.add_argument("--source", help="restrict metadata sources")


# --------------------------------------------------------------------------

def demo() -> None:
    """python3 -m paperctl.alphaxiv -- the parsing this module actually owns."""
    assert ident_of({"canonicalId": "2506.19243"}) == ("2506.19243", "2506.19243")
    # Versioned ids lose the version: v1 and v2 are one paper in the library.
    assert ident_of({"canonicalId": "2506.19243v2"})[1] == "2506.19243"
    # Field moved -> still found, because every candidate is sniffed.
    assert ident_of({"universalPaperId": "2506.19243"})[1] == "2506.19243"
    assert ident_of({"universal_paper_id": "1706.03762"})[1] == "1706.03762"
    # A private upload has a Mongo id and no arXiv id: fall back to the title,
    # which resolve.resolve searches for. Must NOT be mistaken for an id.
    priv = ident_of({"paperGroupId": "652f1c9ab3d4e5f6a7b8c9d0",
                     "title": "  Some   Internal Report "})
    assert priv == ("Some Internal Report", ""), priv
    # Nothing usable at all is not a crash; the caller skips it.
    assert ident_of({}) == ("", "")
    assert papers_of({"papers": [{"title": "x"}, "junk", None]}) == [{"title": "x"}]
    assert papers_of({}) == []
    # Folder names are sanitised before they become paths.
    assert "/" not in naming.title_case_filename("PINNs / blowup")
    print("alphaxiv: ok")


if __name__ == "__main__":
    demo()
