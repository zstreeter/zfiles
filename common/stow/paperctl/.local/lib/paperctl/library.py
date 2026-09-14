"""The library on disk: one folder per topic, and the index that tracks it.

    <root>/<Folder_Name>/
        README.md        human index, papers first, with who shared what
        refs.bib         BibTeX for everything with resolvable metadata
        papers/*.pdf     open-access copies that could be fetched
        .paperctl.json   machine state, so a re-run only adds what is new

README.md and refs.bib are both *generated* from .paperctl.json on every write.
That is what makes re-running safe and incremental: the index is the truth, the
two readable files are projections of it, and neither is ever parsed back.
"""

from __future__ import annotations

import hashlib
import json
import sys
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

from . import naming
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


def load_index(path: Path) -> dict:
    f = path / INDEX_NAME
    try:
        data = json.loads(f.read_text())
    except FileNotFoundError:
        return {"schema": SCHEMA, "entries": []}
    except (json.JSONDecodeError, OSError) as e:
        # Refuse rather than silently starting a fresh index: overwriting it
        # would lose every record of what was already downloaded.
        sys.exit(f"paperctl: {f} is unreadable ({e}). Move it aside to start over.")
    data.setdefault("entries", [])
    return data


def save_index(path: Path, index: dict) -> None:
    path.mkdir(parents=True, exist_ok=True)
    index["schema"] = SCHEMA
    index["updated"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    tmp = path / (INDEX_NAME + ".tmp")
    tmp.write_text(json.dumps(index, indent=2, sort_keys=True) + "\n")
    # Atomic: a crash mid-write must not leave a truncated index, which
    # load_index would then refuse and block every later run.
    tmp.replace(path / INDEX_NAME)


def find_entry(index: dict, ident: str) -> dict | None:
    return next((e for e in index["entries"] if e.get("ident") == ident), None)


# --------------------------------------------------------------------------
# PDF acquisition
# --------------------------------------------------------------------------

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
        # Publishers answer a paywalled request with 200 and a login page, so
        # status code is not enough -- the magic bytes are the real check.
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


# Statuses worth re-attempting later. needs-sso is IEEE-only and genuinely
# needs a human, but link-only often just means Unpaywall had not yet indexed
# the OA copy -- so `paperctl retry` exists and this is what it looks for.
RETRYABLE = {"link-only"}


# --------------------------------------------------------------------------
# Adding
# --------------------------------------------------------------------------

def add(cfg, fetch, rec: Record, dest: Path, dry_run: bool = False,
        kind: str = "", provenance: dict | None = None) -> dict:
    """Put one record into a folder. Returns the index entry."""
    index = load_index(dest)
    ident = rec.ident
    existing = find_entry(index, ident)
    if existing and existing.get("status") in ("downloaded", "have"):
        existing["note"] = "already in this folder"
        return existing

    entry = {
        "ident": ident,
        "citekey": naming.citekey(rec.authors, rec.title, rec.year),
        "added": datetime.now(timezone.utc).strftime("%Y-%m-%d"),
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
        index["entries"] = [entry if e.get("ident") == ident else e
                            for e in index["entries"]]
    else:
        index["entries"].append(entry)
    save_index(dest, index)
    write_projections(cfg, dest, index)
    return entry


def dedupe_citekeys(entries: list[dict]) -> None:
    """Suffix a, b, c on collision, in place.

    Two papers by the same author in the same year with similar titles do
    collide, and a .bib with a duplicate key is silently wrong: BibTeX keeps
    one entry and every citation of the other points at the wrong paper.
    """
    seen: dict[str, int] = {}
    for e in sorted(entries, key=lambda x: (x.get("added", ""), x.get("title", ""))):
        base = e.get("citekey") or "ref"
        n = seen.get(base, 0)
        seen[base] = n + 1
        if n:
            e["citekey"] = f"{base}{chr(ord('a') + n - 1)}"


# --------------------------------------------------------------------------
# Projections: README.md and refs.bib
# --------------------------------------------------------------------------

def write_projections(cfg, dest: Path, index: dict) -> None:
    entries = index.get("entries") or []
    dedupe_citekeys(entries)
    if cfg.get("library.write_refs_bib"):
        write_bib(dest / "refs.bib", entries, dest.name)
    if cfg.get("library.write_readme"):
        write_readme(dest / "README.md", entries, dest.name)


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
    have = sum(1 for e in entries if e.get("status") in ("downloaded", "have"))
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
        # Provenance only exists for mail-harvested entries; omit the line
        # entirely rather than printing "shared by None".
        if e.get("shared_by"):
            rows.append(f"  shared by {e['shared_by']}"
                        + (f", {e['shared_at'][:10]}" if e.get("shared_at") else ""))
    return rows
