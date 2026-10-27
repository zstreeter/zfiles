"""The library on disk: one folder per topic, and the index that tracks it.

    <root>/<Folder_Name>/
        README.md        human index, papers first, with who shared what
        refs.bib         BibTeX for everything with resolvable metadata
        papers/*.pdf     open-access copies that could be fetched
        .paperctl.json   machine state, so a re-run only adds what is new

README.md and refs.bib are both *generated* from .paperctl.json on every write.
That is what makes re-running safe and incremental: the index is the truth, the
two readable files are projections of it, and neither is ever parsed back.

Callers say what to do -- add, remove, adopt, retry, tidy, entries, bib_entries
-- and never load, edit and save an index themselves. Every write goes through
_commit, which is the one place citekeys are made unique and then persisted, so
a key shown in README.md or refs.bib is always one `remove` can find.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

from . import identity, naming
from .record import Record

INDEX_NAME = ".paperctl.json"
SCHEMA = 1


def root(cfg) -> Path:
    return cfg.path("library.root")


def folder(cfg, name: str | None) -> Path:
    """Resolve a folder name to a path under the library root.

    An absolute path is honoured as-is so `--to /tmp/x` can escape the library
    entirely, which is how the flexibility tests prove nothing is hardcoded.
    """
    if not name:
        return root(cfg) / "Inbox"
    p = Path(name).expanduser()
    return p if p.is_absolute() else root(cfg) / name


def index_dirs(base: Path) -> list[Path]:
    """Every folder at or below `base` that has an index -- topics may nest.

    A project folder such as `Tensor_Networks/` can hold topic subfolders, each
    with its own index; search, bib and retry must see all of them.
    """
    return sorted(p.parent for p in base.rglob(INDEX_NAME))


def load_index(path: Path) -> dict:
    f = path / INDEX_NAME
    try:
        data = json.loads(f.read_text())
    except FileNotFoundError:
        return {"schema": SCHEMA, "entries": []}
    except (json.JSONDecodeError, OSError) as e:
        sys.exit(f"paperctl: {f} is unreadable ({e}). Move it aside to start over.")
    data.setdefault("entries", [])
    # Indexes written before keys were persisted can hold duplicates; refs.bib
    # showed them suffixed, so every reader sees those same keys from the start.
    dedupe_citekeys(data["entries"])
    return data


def save_index(path: Path, index: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    index["schema"] = SCHEMA
    index["updated"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    tmp = path / (INDEX_NAME + ".tmp")
    tmp.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    tmp.replace(path / INDEX_NAME)


def find_entry(index: dict, paper) -> dict | None:
    """The entry for the same paper as `paper` (a Record or an entry), by identity.same."""
    return next((e for e in index["entries"] if identity.same(e, paper)), None)



def pdf_name(rec: Record, style: str) -> str:
    """Filename for a paper's PDF, collision-proof by construction.

    The short hash is not decoration. The old code truncated the title to 70
    characters and then skipped the download if that path already existed --
    so two papers whose titles agreed for 70 characters (a series, or a paper
    and its erratum) silently resolved to one file, and the second was recorded
    as "already downloaded" without anything ever being fetched.
    """
    stem = naming.filename(rec.title or "untitled", style, limit=80)
    tag = hashlib.sha1(rec.ident.encode()).hexdigest()[:6]
    return f"{stem}__{tag}.pdf"


def download_pdf(fetch, url: str, dest: Path) -> tuple[bool, str]:
    try:
        data = fetch.get(url, accept="application/pdf,*/*", timeout=90)
    except Exception as e:
        return False, f"fetch failed: {type(e).__name__}"
    if not data[:5].startswith(b"%PDF"):
        return False, "response was not a PDF (likely a paywall or login page)"
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return True, f"{len(data) // 1024} KB"


def acquire(fetch, rec: Record, papers: Path, email: str,
            kind: str = "") -> dict:
    """Try hard for an open-access PDF. Never fails the run over one paper."""
    from .sources import unpaywall

    dest = papers / pdf_name(rec, "title_case")
    if dest.exists() and dest.stat().st_size > 0:
        return {"status": "have", "pdf": dest.name, "note": "already downloaded"}

    candidates: list[str] = []
    if rec.arxiv_id:
        candidates.append(f"https://arxiv.org/pdf/{rec.arxiv_id}")
    if rec.pdf_url:
        candidates.append(rec.pdf_url)
    if rec.url and rec.url.lower().split("?")[0].endswith(".pdf"):
        candidates.append(rec.url)
    if rec.doi:
        oa = unpaywall.pdf_url(fetch, rec.doi, email)
        if oa:
            candidates.append(oa)

    reasons = []
    for url in dict.fromkeys(candidates):
        ok, note = download_pdf(fetch, url, dest)
        if ok:
            return {"status": "downloaded", "pdf": dest.name, "note": note,
                    "from": url}
        reasons.append(f"{urllib.parse.urlsplit(url).netloc}: {note}")

    if kind == "ieee":
        return {"status": "needs-sso",
                    "note": "IEEE Xplore -- needs institutional SSO; "
                            "fetch with the ieee-xplore skill"}
    if not email and rec.doi:
        reasons.append("unpaywall not tried: set sources.unpaywall_email "
                       "in ~/.config/paperctl/local.toml")
    return {"status": "link-only",
            "note": "; ".join(reasons) or "no open-access copy found"}


# Entry statuses. has_pdf / RETRYABLE are the only questions callers ask of one.
HAVE = frozenset({"downloaded", "have"})     # a local PDF exists ("have": not ours to delete)
RETRYABLE = frozenset({"link-only"})         # no open-access copy yet; `retry` re-asks
PROVENANCE = ("shared_by", "shared_at", "source_url")


def has_pdf(entry: dict) -> bool:
    return entry.get("status") in HAVE


def _commit(cfg, dest: Path, index: dict) -> None:
    """Make citekeys unique, persist, regenerate README.md and refs.bib. Every write ends here."""
    dedupe_citekeys(index["entries"])
    save_index(dest, index)
    write_projections(cfg, dest, index)


def _citekey_for(cfg, rec: Record, dest: Path, index: dict) -> str:
    """A key no *other* paper uses anywhere in the library, so library.bib never has to rename it.

    The same paper filed in two folders gets the same key in both: one paper,
    one citation, whichever bibliography a vault reads.
    """
    owners = [e for d, e in entries(cfg, root(cfg)) if d != dest] + index["entries"]
    known = next((e["citekey"] for e in owners if e.get("citekey") and identity.same(e, rec)), "")
    if known:
        return known
    base = naming.citekey(rec.authors, rec.title, rec.year)
    taken = {}
    for e in owners:
        taken.setdefault(e.get("citekey"), []).append(e)
    for key in _suffixed(base):
        users = taken.get(key, [])
        if all(identity.same(u, rec) for u in users):
            return key
    raise AssertionError("unreachable")


def _suffixed(base: str):
    yield base
    for n in range(26 * 27):
        q, r = divmod(n, 26)
        yield base + (chr(ord("a") + q - 1) if q else "") + chr(ord("a") + r)



def add(cfg, fetch, rec: Record, dest: Path, dry_run: bool = False,
        kind: str = "", provenance: dict | None = None) -> dict:
    """Put one record into a folder. Returns the index entry."""
    index = load_index(dest)
    existing = find_entry(index, rec)
    if existing:
        # The same paper seen again, e.g. its published version after the preprint:
        # keep what the first sighting knew (an arXiv id is a PDF route) and who shared it.
        rec = dataclasses.replace(rec)
        known = record_of(existing)
        for f in Record.__dataclass_fields__:
            if f != "score" and not getattr(rec, f) and getattr(known, f):
                setattr(rec, f, getattr(known, f))
        provenance = {**{k: existing[k] for k in PROVENANCE if existing.get(k)},
                      **(provenance or {})}
    if existing and has_pdf(existing):
        # Already readable. Still learn what this sighting adds (a DOI, a journal).
        gained = {f: v for f, v in rec.to_dict().items()
                  if f != "score" and v and not existing.get(f)}
        if gained and not dry_run:
            existing.update(gained)
            existing["ident"] = identity.key(existing)
            _commit(cfg, dest, index)
        return {**existing, "note": "already in this folder"}
    ident = rec.ident

    entry = {
        "ident": ident,
        # A re-seen paper keeps its key: something may already cite it.
        "citekey": (existing or {}).get("citekey") or _citekey_for(cfg, rec, dest, index),
        "added": (existing or {}).get("added") or datetime.now(timezone.utc).strftime("%Y-%m-%d"),
        "kind": kind or ("arxiv" if rec.arxiv_id else "doi" if rec.doi else "other"),
        **rec.to_dict(),
        **(provenance or {}),
    }

    if dry_run:
        entry["status"] = "would-add"
        return entry

    email = str(cfg.get("sources.unpaywall_email") or "")
    entry.update(acquire(fetch, rec, dest / "papers", email, kind))

    if existing:
        index["entries"] = [entry if e is existing else e for e in index["entries"]]
    else:
        index["entries"].append(entry)
    _commit(cfg, dest, index)
    return entry


def remove(cfg, dest: Path, refs: list[str], dry_run: bool = False) -> list[dict]:
    """Drop entries from a folder by citekey (with or without @) or ident. Returns them.

    All or nothing: an unknown ref raises ValueError before anything is written,
    so a typo can't leave half a cleanup done. A PDF paperctl downloaded goes with
    its entry -- `add` can fetch it again. Any other PDF is left in papers/: status
    "have" may be a file the user adopted, which nothing could bring back.
    """
    index = load_index(dest)
    want = {r.lstrip("@") for r in refs}
    hit = [e for e in index["entries"] if want & {e.get("citekey"), e.get("ident")}]
    missing = want - {k for e in hit for k in (e.get("citekey"), e.get("ident"))}
    if missing:
        raise ValueError(f"not in {dest}: {', '.join(sorted(missing))}")
    if dry_run:
        return hit
    for e in hit:
        pdf = dest / "papers" / e["pdf"] if e.get("pdf") else None
        if pdf and e.get("status") == "downloaded" and pdf.is_file():
            pdf.unlink()
    index["entries"] = [e for e in index["entries"] if e not in hit]
    _commit(cfg, dest, index)
    return hit


def entries(cfg, base: Path) -> list[tuple[Path, dict]]:
    """(folder, entry) for every entry at or below `base`."""
    return [(d, e) for d in index_dirs(base) for e in load_index(d)["entries"]]


def bib_entries(cfg, base: Path) -> list[dict]:
    """One entry per paper across every folder under `base`, keyed as the folders key them.

    The same paper filed twice is one entry. Two different papers that share a
    key across folders (possible only in libraries filed before keys were made
    library-wide) still get suffixed, since a .bib with a duplicate key cites
    the wrong paper -- that key then differs from the folder's refs.bib.
    """
    out: list[dict] = []
    for _, e in entries(cfg, base):
        if not any(identity.same(e, o) for o in out):
            out.append(dict(e))
    dedupe_citekeys(out)
    return out


ADOPT_FLOOR = 0.55   # the same floor resolve uses for a title match


def adopt(cfg, dest: Path, files: list[Path], dry_run: bool = False):
    """File PDFs already on disk against existing entries, by title similarity.

    Returns (adopted, skipped): [(filename, citekey, score)], [(filename, best score)].
    Below ADOPT_FLOOR the file is skipped rather than filed against the wrong
    paper: misfiling a PDF is worse than leaving it loose, because the index
    then asserts something false. Raises FileNotFoundError if `dest` has no entries.
    """
    import difflib
    import re
    import shutil

    index = load_index(dest)
    if not index["entries"]:
        raise FileNotFoundError(f"no index at {dest} -- `paperctl add` first")
    papers = dest / "papers"
    style = cfg.get("library.filename_style") or "title_case"
    norm = lambda t: re.sub(r"[^a-z0-9]+", " ", (t or "").lower()).strip()
    done, skipped = [], []
    for f in files:
        stem = norm(f.stem)
        best, score = None, 0.0
        for e in index["entries"]:
            r = difflib.SequenceMatcher(None, stem, norm(e.get("title"))).ratio()
            if r > score:
                best, score = e, r
        if not best or score < ADOPT_FLOOR:
            skipped.append((f.name, score))
            continue
        target = papers / pdf_name(record_of(best), style)
        if not dry_run:
            papers.mkdir(parents=True, exist_ok=True)
            shutil.move(str(f), target)
            best.update(pdf=target.name, status="have", note="adopted from local file")
        done.append((f.name, best.get("citekey"), score))
    if done and not dry_run:
        _commit(cfg, dest, index)
    return done, skipped


def retry(cfg, fetch, base: Path, dry_run: bool = False):
    """Re-attempt RETRYABLE entries under `base`. Returns (attempted, [changes])."""
    email = str(cfg.get("sources.unpaywall_email") or "")
    attempted, changed = 0, []
    for f in index_dirs(base):
        index = load_index(f)
        dirty = False
        for e in index["entries"]:
            if e.get("status") not in RETRYABLE:
                continue
            attempted += 1
            if dry_run:
                changed.append({"folder": f.name, "title": e.get("title"), "status": "would-retry"})
                continue
            got = acquire(fetch, record_of(e), f / "papers", email, e.get("kind", ""))
            if got["status"] in HAVE:
                e.update(got)
                dirty = True
                changed.append({"folder": f.name, "title": e.get("title"), **got})
        if dirty:
            _commit(cfg, f, index)
    return attempted, changed


def tidy(cfg, base: Path, apply: bool = False) -> list[dict]:
    """Duplicate PDFs by content hash under `base`, nested folders included.

    Returns one {"hash", "keep": [paths], "remove": [paths]} per duplicated
    content. A file an index entry points at is always kept -- deleting it would
    leave the entry claiming a PDF that is gone -- so only unreferenced copies
    are removed; with none referenced, the first is kept. `apply` deletes "remove".
    """
    from collections import defaultdict

    referenced = {d / "papers" / e["pdf"] for d, e in entries(cfg, base) if e.get("pdf")}
    by_hash: dict[str, list[Path]] = defaultdict(list)
    for pdf in sorted(p for p in base.rglob("*.pdf") if p.parent.name == "papers"):
        by_hash[hashlib.sha256(pdf.read_bytes()).hexdigest()].append(pdf)

    report = []
    for h, ps in by_hash.items():
        if len(ps) < 2:
            continue
        keep = [p for p in ps if p in referenced] or ps[:1]
        drop = [p for p in ps if p not in keep]
        report.append({"hash": h, "keep": keep, "remove": drop})
        if apply:
            for p in drop:
                p.unlink()
    return report


def _selftest_remove(tmp: Path | None = None) -> None:
    """remove(): all-or-nothing on unknown refs; downloaded PDF deleted, adopted PDF kept.

    python3 -c 'from paperctl.library import _selftest_remove; _selftest_remove()'
    """
    if tmp is None:
        import tempfile
        with tempfile.TemporaryDirectory() as t:
            return _selftest_remove(Path(t))
    cfg = _Cfg(tmp)
    lib = tmp / "Lib"
    (lib / "papers").mkdir(parents=True)
    (lib / "papers" / "a.pdf").write_text("a")
    (lib / "papers" / "b.pdf").write_text("b")
    save_index(lib, {"entries": [
        {"ident": "10.1234/a", "citekey": "aKey2020", "title": "A", "status": "downloaded", "pdf": "a.pdf"},
        {"ident": "10.1234/b", "citekey": "bKey2021", "title": "B", "status": "have", "pdf": "b.pdf"},
        {"ident": "https://c.org/p", "citekey": "cKey2022", "title": "C", "status": "link-only"}]})
    try:
        remove(cfg, lib, ["@aKey2020", "nope"])
        raise AssertionError("unknown ref must raise")
    except ValueError:
        pass
    assert len(load_index(lib)["entries"]) == 3                   # nothing written
    assert [e["ident"] for e in remove(cfg, lib, ["aKey2020"], dry_run=True)] == ["10.1234/a"]
    assert (lib / "papers" / "a.pdf").exists()                    # dry run touches nothing
    gone = remove(cfg, lib, ["@aKey2020", "10.1234/b"])
    assert sorted(e["ident"] for e in gone) == ["10.1234/a", "10.1234/b"]
    assert [e["ident"] for e in load_index(lib)["entries"]] == ["https://c.org/p"]
    assert not (lib / "papers" / "a.pdf").exists()                # downloaded: deleted
    assert (lib / "papers" / "b.pdf").exists()                    # "have": kept
    assert "aKey2020" not in (lib / "refs.bib").read_text()
    assert "cKey2022" in (lib / "refs.bib").read_text()
    print("remove selftest: ok")


class _Cfg(dict):
    """The two things library reads from a Config: get() and path("library.root")."""

    def __init__(self, root: Path):
        super().__init__({"library.root": str(root), "library.write_refs_bib": True,
                          "library.write_readme": True})

    def path(self, k: str) -> Path:
        return Path(self[k])


class _PdfNet:
    """A fetch where every URL serves a PDF."""

    def get(self, *a, **k):
        return b"%PDF-1.4 test"


class _NoNet:
    """A fetch that is always offline: every PDF attempt fails, nothing leaves the machine."""

    def get(self, *a, **k):
        raise OSError("offline")

    get_text = get


def _selftest_identity(tmp: Path) -> None:
    """add(): a preprint and its published version are one entry, and nothing it knew is lost."""
    cfg = _Cfg(tmp)
    lib = tmp / "Same"
    pre = Record(title="Deep Things", authors=["Ada Lovelace"], year="2025",
                 arxiv_id="2506.19243")
    first = add(cfg, _NoNet(), pre, lib, provenance={"shared_by": "Bo"})
    assert (first["status"], first["ident"]) == ("link-only", "arxiv:2506.19243"), first

    pub = Record(title="Deep Things", authors=["Ada Lovelace"], year="2026",
                 doi="10.1234/DT", arxiv_id="2506.19243v2", venue="J. Things")
    add(cfg, _NoNet(), pub, lib)
    [e] = load_index(lib)["entries"]
    assert e["ident"] == "10.1234/dt" and e["venue"] == "J. Things", e
    assert e["citekey"] == first["citekey"] and e["shared_by"] == "Bo", e

    e["status"] = "have"                                  # readable now; a re-sighting only adds facts
    save_index(lib, {"entries": [e]})
    again = add(cfg, _NoNet(), Record(title="Deep Things", doi="https://doi.org/10.1234/dt",
                                      publisher="Pub"), lib)
    [e] = load_index(lib)["entries"]
    assert again["note"] == "already in this folder" and e["publisher"] == "Pub", e
    assert "note" not in e or e["note"] != "already in this folder"

    add(cfg, _NoNet(), Record(title="Other", doi="10.1234/other"), lib)
    assert len(load_index(lib)["entries"]) == 2


def _selftest_folder(tmp: Path) -> None:
    """Citekeys persisted and library-wide; bib, tidy, adopt and retry through the folder module."""
    cfg = _Cfg(tmp)
    a, b = tmp / "Keys" / "A", tmp / "Keys" / "B"
    smith = lambda t, **k: Record(title=t, authors=["Jo Smith"], year="2020", **k)

    # A library filed before keys were persisted: two papers share a key in the index.
    save_index(a, {"entries": [
        {"ident": "10.1234/one", "doi": "10.1234/one", "citekey": "smithDeeNetLea2020",
         "title": "Deep Nets Learn One", "added": "2020-01-01", "status": "link-only"},
        {"ident": "10.1234/two", "doi": "10.1234/two", "citekey": "smithDeeNetLea2020",
         "title": "Deep Nets Learn Two", "added": "2020-01-02", "status": "link-only"}]})
    add(cfg, _NoNet(), smith("Unrelated Thing", doi="10.1234/three"), a)
    keys = {e["ident"]: e["citekey"] for e in load_index(a)["entries"]}
    assert keys["10.1234/one"] == "smithDeeNetLea2020" and keys["10.1234/two"] == "smithDeeNetLea2020a", keys
    assert "{smithDeeNetLea2020a," in (a / "refs.bib").read_text()      # the key README/bib show...
    remove(cfg, a, ["smithDeeNetLea2020a"])                              # ...is one remove can find

    # New keys are unique across the library; the same paper keeps one key everywhere.
    other = add(cfg, _NoNet(), smith("Deep Nets Learn Four", doi="10.1234/four", arxiv_id="2501.00004"), b)
    assert other["citekey"] == "smithDeeNetLea2020a", other              # A owns the base key
    same = add(cfg, _NoNet(), smith("Deep nets that learn, part one", doi="10.1234/ONE"), b)
    assert same["citekey"] == "smithDeeNetLea2020", same      # found by identity, not by title
    bib = bib_entries(cfg, tmp / "Keys")
    assert sorted(e["citekey"] for e in bib) == ["smithDeeNetLea2020", "smithDeeNetLea2020a", "smithUnrThi2020"], bib

    # retry: a link-only entry with a route to a PDF becomes downloaded; one without stays.
    attempted, changed = retry(cfg, _PdfNet(), tmp / "Keys" / "B")
    assert (attempted, [c["title"] for c in changed]) == (2, ["Deep Nets Learn Four"]), changed
    assert [has_pdf(e) for e in load_index(b)["entries"]] == [True, False]

    # tidy: nested folders are seen; a PDF the index points at is never removed.
    nested = tmp / "Proj" / "Topic" / "papers"
    nested.mkdir(parents=True)
    pdf = next((b / "papers").glob("*.pdf"))
    for name in ("copy1.pdf", "copy2.pdf"):
        (nested / name).write_bytes(pdf.read_bytes())
    report = tidy(cfg, tmp, apply=True)
    [dup] = [r for r in report if pdf in r["keep"]]
    assert pdf.exists() and not (nested / "copy1.pdf").exists() and not (nested / "copy2.pdf").exists(), dup

    # adopt: a loose PDF whose name matches a title is filed; a stranger is not.
    c = tmp / "Adopt"
    save_index(c, {"entries": [{"ident": "10.1234/x", "citekey": "k", "title": "Quantum Error Correction Codes",
                                "status": "link-only"}]})
    (c / "quantum_error_correction_codes.pdf").write_bytes(b"%PDF")
    (c / "holiday_photos.pdf").write_bytes(b"%PDF")
    done, skipped = adopt(cfg, c, sorted(c.glob("*.pdf")))
    assert [d[0] for d in done] == ["quantum_error_correction_codes.pdf"] and len(skipped) == 1
    [e] = load_index(c)["entries"]
    assert e["status"] == "have" and (c / "papers" / e["pdf"]).exists()
    try:
        adopt(cfg, tmp / "Empty", [])
        raise AssertionError("adopt into an empty folder must raise")
    except FileNotFoundError:
        pass


def dedupe_citekeys(entries: list[dict]) -> None:
    """Suffix a, b, c on collision, in place.

    Two papers by the same author in the same year with similar titles do
    collide, and a .bib with a duplicate key is silently wrong: BibTeX keeps
    one entry and every citation of the other points at the wrong paper.
    """
    used: set[str] = set()
    for e in sorted(entries, key=lambda x: (x.get("added", ""), x.get("title", ""))):
        base = e.get("citekey") or "ref"
        e["citekey"] = next(k for k in _suffixed(base) if k not in used)
        used.add(e["citekey"])



def write_projections(cfg, dest: Path, index: dict) -> None:
    """README.md and refs.bib from the index. Only _commit calls this, after keys are unique."""
    if cfg.get("library.write_refs_bib"):
        write_bib(dest / "refs.bib", index["entries"], dest.name)
    if cfg.get("library.write_readme"):
        write_readme(dest / "README.md", index["entries"], dest.name)


def record_of(entry: dict) -> Record:
    """The Record fields back out of an index entry, ignoring the bookkeeping."""
    fields = Record.__dataclass_fields__
    return Record(**{k: v for k, v in entry.items() if k in fields})


def write_bib(path: Path, entries: list[dict], title: str) -> int:
    out = [f"% {title} -- generated by paperctl, do not edit by hand.",
           f"% Regenerate: paperctl bib --folder {title}", ""]
    n = 0
    for e in sorted(entries, key=lambda x: x.get("citekey", "")):
        if not e.get("title"):
            continue
        out.append(naming.bibtex(record_of(e), e.get("citekey") or "ref"))
        n += 1
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
    return n


STATUS_MARK = {"downloaded": "[x]", "have": "[x]",
               "needs-sso": "[ ]", "link-only": "[ ]", "would-add": "[ ]"}


def write_readme(path: Path, entries: list[dict], title: str) -> None:
    have = sum(1 for e in entries if has_pdf(e))
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    out = [f"# {title.replace('_', ' ')}", "",
           f"{len(entries)} entries, {have} available as local PDFs. "
           f"Updated {now} by `paperctl`.", ""]

    def is_paper(e: dict) -> bool:
        return bool(e.get("doi") or e.get("arxiv_id")
                    or e.get("kind") not in ("other", "", None))

    papers = [e for e in entries if is_paper(e)]
    others = [e for e in entries if not is_paper(e)]

    if papers:
        out += [f"## Papers ({len(papers)})", ""]
        out += _rows(papers)
    if others:
        out += ["", f"## Other links ({len(others)})", ""]
        out += _rows(others)

    missing = [e for e in entries if e.get("status") in RETRYABLE]
    if missing:
        out += ["", "## Not yet retrieved", "",
                "`paperctl retry` re-attempts these; open access often lands later.",
                ""]
        for e in missing:
            out.append(f"- {e.get('title') or e.get('url')} — {e.get('note', '')}")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")


def _rows(entries: list[dict]) -> list[str]:
    rows = []
    for e in sorted(entries, key=lambda x: (x.get("year") or "", x.get("title") or ""),
                    reverse=True):
        mark = STATUS_MARK.get(e.get("status", ""), "[ ]")
        title = e.get("title") or e.get("url") or "untitled"
        link = f"[{title}]({e['url']})" if e.get("url") else title
        rows.append(f"- {mark} {link}")

        bits = []
        authors = e.get("authors") or []
        if authors:
            bits.append(", ".join(authors[:3]) + (" et al." if len(authors) > 3 else ""))
        if e.get("year"):
            bits.append(e["year"])
        if e.get("venue"):
            bits.append(f"*{e['venue']}*")
        if e.get("citekey"):
            bits.append(f"`@{e['citekey']}`")
        if bits:
            rows.append(f"  {' · '.join(bits)}")
        if e.get("pdf"):
            rows.append(f"  [PDF](papers/{urllib.parse.quote(e['pdf'])})")
        if e.get("shared_by"):
            rows.append(f"  shared by {e['shared_by']}"
                        + (f", {e['shared_at'][:10]}" if e.get("shared_at") else ""))
    return rows


def _selftest() -> None:
    """Nested topic folders are found at any depth, and nothing outside `base`."""
    import tempfile
    with tempfile.TemporaryDirectory() as t:
        root = Path(t)
        for d in ("A", "Proj/Topic1", "Proj/Topic2", "Other"):
            save_index(root / d, {"entries": []})
        (root / "Proj" / "Topic1" / "papers").mkdir()
        assert [p.relative_to(root).as_posix() for p in index_dirs(root)] == \
            ["A", "Other", "Proj/Topic1", "Proj/Topic2"]
        assert [p.name for p in index_dirs(root / "Proj")] == ["Topic1", "Topic2"]
        assert index_dirs(root / "Missing") == []

        _selftest_remove(root / "r")
        _selftest_identity(root / "i")
        _selftest_folder(root / "f")
    print("library selftest: ok")


if __name__ == "__main__":
    _selftest()
