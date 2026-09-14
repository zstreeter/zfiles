"""Argument parsing and dispatch.

Conventions held across every subcommand, because four different agents drive
this and inconsistency is what makes a CLI unusable to them:

    --json      on every read command, so output can be consumed structurally
    --dry-run   on every mutating command, and documented as the first step
    --library   everywhere, so nothing is pinned to ~/Library

Each command is a small function taking (args, cfg) and returning an exit code.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path

from . import config, library, naming, net, resolve
from .record import Record
from .sources import REGISTRY, enabled

__version__ = "1.0"


def _tty() -> bool:
    return sys.stdout.isatty() and os.environ.get("NO_COLOR") is None


def c(code: str, s: str) -> str:
    return f"\033[{code}m{s}\033[0m" if _tty() else s


def emit(args, payload, lines: list[str]) -> None:
    """One place that decides JSON vs prose, so no command can forget --json."""
    if getattr(args, "json", False):
        print(json.dumps(payload, indent=2, default=str))
    else:
        print("\n".join(lines))


def fetcher(cfg) -> net.Fetch:
    return net.Fetch(
        user_agent=str(cfg.get("net.user_agent")),
        timeout=int(cfg.get("net.timeout") or 30),
        retries=int(cfg.get("net.retries") or 2),
        mailto=str(cfg.get("sources.unpaywall_email") or ""),
    )


def sources_for(args, cfg) -> list[str]:
    return enabled(getattr(args, "source", None), cfg.get("sources.enabled"))


# --------------------------------------------------------------------------
# doctor
# --------------------------------------------------------------------------

def cmd_doctor(args, cfg) -> int:
    """What works on THIS machine, and for anything that does not, why not."""
    from .mail import probe as mail_probe

    fetch = fetcher(cfg)
    checks: list[dict] = []

    def check(name, ok, detail, fix=""):
        checks.append({"name": name, "ok": bool(ok), "detail": detail, "fix": fix})

    check("target", True, cfg.target,
          "override with PAPERCTL_TARGET=wsl|omarchy|remote|linux")
    check("config files", True,
          ", ".join(str(p) for p in cfg.files) or "none (using built-in defaults)")

    root = library.root(cfg)
    check("library root", root.parent.exists(), str(root)
          + ("" if root.exists() else "  (will be created on first add)"))

    email = str(cfg.get("sources.unpaywall_email") or "")
    check("unpaywall email", bool(email), email or "not set",
          "set sources.unpaywall_email in ~/.config/paperctl/local.toml "
          "-- without it, paywalled DOIs stay link-only")

    if not args.offline:
        for name in REGISTRY:
            mod = REGISTRY[name]
            url = getattr(mod, "API", "")
            check(f"source: {name}", fetch.reachable(url), url)

    for m in mail_probe(cfg):
        check(f"mail: {m['backend']}", m["ok"], m["detail"], m.get("fix", ""))

    for tool, why in (("quarto", "render papers"), ("pandoc", "convert notes")):
        path = shutil.which(tool)
        check(f"tool: {tool}", bool(path), path or "not installed",
              f"optional -- only needed to {why}")

    if args.json:
        print(json.dumps({"target": cfg.target, "checks": checks}, indent=2))
        return 0

    print(c("1", f"paperctl {__version__}") + c("2", f"  target={cfg.target}"))
    print()
    for ch in checks:
        mark = c("32", " ok ") if ch["ok"] else c("33", "----")
        print(f"  [{mark}] {ch['name']:<22} {ch['detail']}")
        if not ch["ok"] and ch["fix"]:
            print(f"         {c('2', ch['fix'])}")
    # Exit 0 even with failures: doctor reports, it does not judge. A missing
    # himalaya on WSL is correct, not broken, and a non-zero exit here would
    # make every wrapper script treat a healthy machine as failing.
    return 0


# --------------------------------------------------------------------------
# add
# --------------------------------------------------------------------------

def cmd_add(args, cfg) -> int:
    fetch = fetcher(cfg)
    srcs = sources_for(args, cfg)
    dest = library.folder(cfg, args.to)

    rec, alts = resolve.resolve(fetch, args.query, srcs)
    if rec is None:
        print(f"paperctl: nothing found for {args.query!r}", file=sys.stderr)
        if not srcs:
            print("          no sources enabled -- check sources.enabled",
                  file=sys.stderr)
        return 1
    rec = resolve.enrich(fetch, rec, srcs)

    entry = library.add(cfg, fetch, rec, dest, dry_run=args.dry_run,
                        kind=resolve.kind_of(args.query))

    payload = {"folder": str(dest), "entry": entry,
               "alternatives": [a.to_dict() for a in alts[:4]]}
    lines = []
    if args.dry_run:
        lines.append(c("33", "--dry-run: nothing written."))
    lines += [
        f"{c('1', entry.get('title') or entry.get('url') or '(untitled)')}",
        f"  {', '.join((entry.get('authors') or [])[:4])}"
        f"{'  ' + entry['year'] if entry.get('year') else ''}",
        f"  citekey  @{entry.get('citekey')}",
        f"  status   {entry.get('status')}  {entry.get('note', '')}",
        f"  folder   {dest}",
    ]
    if alts:
        lines += ["", c("2", f"{len(alts)} other match(es); "
                             f"`paperctl search-web` to see them.")]
    emit(args, payload, lines)
    return 0


# --------------------------------------------------------------------------
# search-web / search
# --------------------------------------------------------------------------

def cmd_search_web(args, cfg) -> int:
    from .sources import search_all

    fetch = fetcher(cfg)
    srcs = sources_for(args, cfg)
    found = search_all(fetch, args.query, srcs, args.limit)
    if not found:
        print(f"paperctl: no results for {args.query!r}", file=sys.stderr)
        return 1

    lines = []
    for i, r in enumerate(found[: args.limit], 1):
        lines.append(f"{c('1', str(i) + '.')} {r.title}")
        bits = [", ".join(r.authors[:3]) + (" et al." if len(r.authors) > 3 else "")]
        if r.year:
            bits.append(r.year)
        if r.venue:
            bits.append(r.venue)
        lines.append(f"   {c('2', ' · '.join(b for b in bits if b))}")
        ident = r.arxiv_id or r.doi or r.url
        lines.append(f"   {c('2', f'{r.source}  {r.score:.2f}')}  {ident}")
    lines += ["", c("2", "Add one with:  paperctl add <id-or-doi> --to <Folder>")]
    emit(args, [r.to_dict() for r in found[: args.limit]], lines)
    return 0


def cmd_search(args, cfg) -> int:
    """Search the local library, not the web."""
    from .record import score_title

    root = library.root(cfg)
    hits = []
    for index_file in sorted(root.glob(f"*/{library.INDEX_NAME}")):
        folder_name = index_file.parent.name
        for e in library.load_index(index_file.parent).get("entries", []):
            hay = " ".join([e.get("title", ""), " ".join(e.get("authors") or []),
                            e.get("venue", ""), e.get("citekey", "")])
            if args.query.lower() in hay.lower():
                score = 1.0
            else:
                score = score_title(args.query, e.get("title", ""))
                if score < 0.45:
                    continue
            hits.append({**e, "folder": folder_name, "match": score})

    hits.sort(key=lambda h: -h["match"])
    hits = hits[: args.limit]
    if not hits:
        lines = [f"paperctl: nothing in {root} matches {args.query!r}"]
        if not root.exists():
            lines.append("          the library does not exist yet -- "
                         "`paperctl add` creates it")
        emit(args, [], lines)
        return 1

    lines = []
    for h in hits:
        mark = "PDF" if h.get("status") in ("downloaded", "have") else "   "
        lines.append(f"{c('32', mark)} {c('1', h.get('title') or h.get('url'))}")
        lines.append(f"    {c('2', h['folder'])}  @{h.get('citekey')}"
                     + (f"  papers/{h['pdf']}" if h.get("pdf") else ""))
    emit(args, hits, lines)
    return 0


# --------------------------------------------------------------------------
# bib
# --------------------------------------------------------------------------

def cmd_bib(args, cfg) -> int:
    """Regenerate BibTeX. Writes library.bib, NEVER references.bib.

    references.bib in a vault is Better BibTeX's auto-export and hand edits to
    it vanish on the next sync. Quarto takes a list, so the two coexist:
        bibliography: [references.bib, library.bib]
    """
    root = library.root(cfg)
    folders = ([library.folder(cfg, args.folder)] if args.folder
               else sorted(p.parent for p in root.glob(f"*/{library.INDEX_NAME}")))

    entries: list[dict] = []
    for f in folders:
        entries.extend(library.load_index(f).get("entries", []))
    library.dedupe_citekeys(entries)

    if args.out:
        out = Path(args.out).expanduser()
        if out.name == "references.bib":
            print("paperctl: refusing to write references.bib -- it is "
                  "Better BibTeX's file and hand edits are overwritten.\n"
                  f"          Write {out.parent / cfg.get('quarto.bib_name')} "
                  "instead and list both in _quarto.yml.", file=sys.stderr)
            return 2
    else:
        out = (folders[0] / "refs.bib") if len(folders) == 1 else root / str(
            cfg.get("quarto.bib_name"))

    if args.dry_run:
        emit(args, {"would_write": str(out), "entries": len(entries)},
             [c("33", "--dry-run: nothing written."),
              f"would write {len(entries)} entries to {out}"])
        return 0

    n = library.write_bib(out, entries, out.stem)
    emit(args, {"wrote": str(out), "entries": n},
         [f"wrote {n} entries to {out}"])
    return 0


# --------------------------------------------------------------------------
# retry
# --------------------------------------------------------------------------

def cmd_retry(args, cfg) -> int:
    """Re-attempt papers that had no open-access copy last time.

    Worth doing: Unpaywall indexes an OA copy days or weeks after publication,
    so a link-only from last month is often downloadable now.
    """
    fetch = fetcher(cfg)
    root = library.root(cfg)
    folders = ([library.folder(cfg, args.folder)] if args.folder
               else sorted(p.parent for p in root.glob(f"*/{library.INDEX_NAME}")))
    email = str(cfg.get("sources.unpaywall_email") or "")

    changed, attempted = [], 0
    for f in folders:
        index = library.load_index(f)
        dirty = False
        for e in index.get("entries", []):
            if e.get("status") not in library.RETRYABLE:
                continue
            attempted += 1
            if args.dry_run:
                changed.append({"folder": f.name, "title": e.get("title"),
                                "status": "would-retry"})
                continue
            got = library.acquire(fetch, library.record_of(e), f / "papers",
                                  email, e.get("kind", ""))
            if got["status"] in ("downloaded", "have"):
                e.update(got)
                dirty = True
                changed.append({"folder": f.name, "title": e.get("title"),
                                **got})
        if dirty:
            library.save_index(f, index)
            library.write_projections(cfg, f, index)

    lines = ([c("33", "--dry-run: nothing fetched.")] if args.dry_run else [])
    lines.append(f"{attempted} retryable, {len(changed)} "
                 f"{'would be retried' if args.dry_run else 'now downloaded'}")
    lines += [f"  {ch['folder']}: {ch['title']}" for ch in changed]
    emit(args, changed, lines)
    return 0


# --------------------------------------------------------------------------
# tidy
# --------------------------------------------------------------------------

def cmd_tidy(args, cfg) -> int:
    """Report duplicate PDFs by content hash. Report-only unless --apply."""
    import hashlib
    from collections import defaultdict

    root = library.root(cfg)
    by_hash: dict[str, list[Path]] = defaultdict(list)
    for pdf in sorted(root.glob("*/papers/*.pdf")):
        h = hashlib.sha256(pdf.read_bytes()).hexdigest()
        by_hash[h].append(pdf)

    dupes = {h: ps for h, ps in by_hash.items() if len(ps) > 1}
    payload = {h: [str(p) for p in ps] for h, ps in dupes.items()}
    lines = [f"{sum(len(p) for p in by_hash.values())} PDFs, "
             f"{len(dupes)} duplicated by content."]
    for h, ps in dupes.items():
        lines.append(f"  {h[:12]}")
        for i, p in enumerate(ps):
            lines.append(f"    {'keep' if i == 0 else 'dupe'}  "
                         f"{p.relative_to(root)}")
    if dupes and not args.apply:
        lines.append("")
        lines.append(c("2", "Nothing was changed. Re-run with --apply to remove "
                            "the copies marked dupe."))
    elif dupes and args.apply:
        for ps in dupes.values():
            for p in ps[1:]:
                p.unlink()
        lines.append(f"removed {sum(len(p) - 1 for p in dupes.values())} duplicates")
    emit(args, payload, lines)
    return 0


# --------------------------------------------------------------------------
# parser
# --------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(
        prog="paperctl",
        description="One research-paper library for every agent and every machine.",
        epilog="Config: ~/.config/paperctl/config.toml (committed) and "
               "local.toml (per-host, holds secrets). `paperctl doctor` says "
               "what works here.")
    ap.add_argument("--version", action="version",
                    version=f"paperctl {__version__}")
    ap.add_argument("--library", dest="library.root", metavar="DIR",
                    help="override the library root for this run")
    ap.add_argument("--config", metavar="FILE",
                    help="use this config file instead of the default")
    sub = ap.add_subparsers(dest="cmd", required=True)

    def add_cmd(name, fn, help_, json_=True, dry=False):
        p = sub.add_parser(name, help=help_)
        if json_:
            p.add_argument("--json", action="store_true",
                           help="machine-readable output")
        if dry:
            p.add_argument("--dry-run", action="store_true",
                           help="show what would happen; write nothing")
        p.set_defaults(fn=fn)
        return p

    d = add_cmd("doctor", cmd_doctor, "what works on this machine, and why not")
    d.add_argument("--offline", action="store_true",
                   help="skip network reachability checks")

    a = add_cmd("add", cmd_add, "add a paper by title, arXiv id, DOI or URL",
                dry=True)
    a.add_argument("query")
    a.add_argument("--to", metavar="FOLDER", help="folder under the library root")
    a.add_argument("--source", help="comma-separated subset of "
                                    + ",".join(REGISTRY))

    s = add_cmd("search", cmd_search, "search the local library")
    s.add_argument("query")
    s.add_argument("--limit", type=int, default=20)

    w = add_cmd("search-web", cmd_search_web, "search arXiv, Crossref, OpenAlex")
    w.add_argument("query")
    w.add_argument("--limit", type=int, default=10)
    w.add_argument("--source", help="comma-separated subset of "
                                    + ",".join(REGISTRY))

    b = add_cmd("bib", cmd_bib, "regenerate BibTeX for a folder or the library",
                dry=True)
    b.add_argument("--folder")
    b.add_argument("--out", metavar="FILE")

    r = add_cmd("retry", cmd_retry, "re-attempt papers with no open-access copy",
                dry=True)
    r.add_argument("--folder")

    t = add_cmd("tidy", cmd_tidy, "find duplicate PDFs by content hash")
    t.add_argument("--apply", action="store_true",
                   help="actually remove duplicates (default is report-only)")

    from .mail import register_cli
    register_cli(sub, add_cmd)
    return ap


def main(argv: list[str] | None = None) -> int:
    ap = build_parser()
    args = ap.parse_args(argv)

    if getattr(args, "config", None):
        os.environ["PAPERCTL_CONFIG"] = args.config

    # Only dotted names are config overrides; the rest are command arguments.
    overrides = {k: v for k, v in vars(args).items() if "." in k}
    cfg = config.load(overrides)
    return args.fn(args, cfg)
