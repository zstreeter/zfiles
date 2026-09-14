"""Mail backends, behind one interface, chosen per machine.

The work laptop reads Outlook through Microsoft Graph; the Omarchy box reads
IMAP through himalaya. Neither should know the other exists, so both implement:

    find_thread(cfg, subject_fragment, account=None) -> Thread | None
    fetch_thread(cfg, thread, account=None)          -> [Message]
    probe(cfg)                                       -> (ok, detail, fix)

The contract is written to the WEAKER backend on purpose. himalaya has no
conversation id and no equivalent of Graph's uniqueBody, so Thread.id is an
opaque string the backend chooses, and Message.html_unique is explicitly
nullable. A caller that assumes either is present is a caller that works only
on WSL.

THE ONE NON-NEGOTIABLE: Message.html is raw markup. Never a text rendering.
Links in mail live in href attributes and the visible text is usually the
paper's title -- a flattening path returned zero URLs for 4 of 22 messages in a
real thread, including the originating mail with its two most important links.
"""

from __future__ import annotations

import sys

from . import graph, himalaya
from .types import Message, Thread

BACKENDS = {"graph": graph, "himalaya": himalaya}

__all__ = ["Message", "Thread", "BACKENDS", "resolve_backend", "probe",
           "register_cli"]


def resolve_backend(cfg) -> tuple[object | None, str, str]:
    """Return (module, name, why). Honours mail.backend, including "auto"."""
    want = str(cfg.get("mail.backend") or "auto").lower()
    if want == "none":
        return None, "none", "mail.backend is none"
    if want in BACKENDS:
        mod = BACKENDS[want]
        ok, detail, _ = mod.probe(cfg)
        if not ok:
            return None, want, f"{want} configured but unavailable: {detail}"
        return mod, want, f"mail.backend = {want} ({cfg.origin('mail.backend')})"
    if want != "auto":
        return None, want, f"unknown mail.backend {want!r}"

    # auto: probe in the order that matches how the targets actually differ,
    # so an unlisted machine still lands somewhere sensible.
    for name in ("graph", "himalaya"):
        ok, detail, _ = BACKENDS[name].probe(cfg)
        if ok:
            return BACKENDS[name], name, f"auto-detected {name} ({detail})"
    return None, "auto", "no mail backend available (see `paperctl doctor`)"


def probe(cfg) -> list[dict]:
    """Every backend's state, for doctor. Reports all, not just the chosen one."""
    out = []
    for name, mod in BACKENDS.items():
        ok, detail, fix = mod.probe(cfg)
        out.append({"backend": name, "ok": ok, "detail": detail, "fix": fix})
    mod, chosen, why = resolve_backend(cfg)
    # ok tracks whether a backend actually resolved, not whether one was named.
    # "himalaya configured but unavailable" is a failure, and reporting it as
    # ok is exactly the kind of cheerful lie doctor exists to prevent.
    out.append({"backend": "selected", "ok": mod is not None,
                "detail": f"{chosen} -- {why}",
                "fix": ("set mail.backend, or install the backend this target "
                        "expects") if mod is None else ""})
    return out


# --------------------------------------------------------------------------
# Commands
# --------------------------------------------------------------------------

def _harvest(cfg, messages, fetch=None):
    """Messages -> deduplicated links with provenance. Backend-independent."""
    from .. import links as LE

    raw, flattened = [], 0
    for m in messages:
        found, _text, looks_flat = LE.extract_from_html(m.body)
        if looks_flat:
            flattened += 1
        for url, anchor in found:
            raw.append({"url": url, "anchor": anchor, "msg": m.id,
                        "who": m.sender, "at": m.date})

    after_noise = [r for r in raw if not LE.is_noise(r["url"])]
    kept_urls = set(LE.drop_truncated([r["url"] for r in after_noise]))
    signal = [r for r in after_noise if r["url"] in kept_urls]

    # Expand shorteners BEFORE classifying and deduping. A lnkd.in URL says
    # nothing about what it points at, so an unexpanded one is always filed as
    # "other", and two shorteners for the same target never dedupe. Done even
    # for --dry-run, because the counts it reports would otherwise not match
    # the counts a real run produces.
    shortened = 0
    if fetch is not None:
        for r in signal:
            if not LE.is_shortener(r["url"]):
                continue
            landed = LE.normalize(fetch.final_url(r["url"]))
            if landed and landed != r["url"]:
                r["resolved_from"] = r["url"]
                r["url"] = landed
                shortened += 1

    seen: dict[str, dict] = {}
    for r in sorted(signal, key=lambda x: x["at"] or ""):
        if r["url"] not in seen:
            kind, is_paper = LE.classify(
                r["url"], cfg.get("links.internal_domains", []) or [])
            seen[r["url"]] = {**r, "kind": kind, "is_paper": is_paper}
    ordered = sorted(seen.values(), key=lambda x: x["at"] or "")

    stages = {
        "messages": len(messages),
        "raw anchor hrefs": len(raw),
        "after noise suppression": len(after_noise),
        "after truncation filtering": len(signal),
        "shorteners expanded": shortened,
        "unique links": len(ordered),
        "papers": sum(1 for r in ordered if r["is_paper"]),
    }
    return ordered, stages, flattened


def cmd_thread(args, cfg) -> int:
    from ..cli import c, emit, fetcher, sources_for
    from .. import library, resolve

    mod, name, why = resolve_backend(cfg)
    if mod is None:
        print(f"paperctl: {why}", file=sys.stderr)
        return 2

    thread = mod.find_thread(cfg, args.subject, args.account)
    if thread is None:
        print(f"paperctl: no thread matching {args.subject!r} "
              f"(backend: {name})", file=sys.stderr)
        return 1
    messages = mod.fetch_thread(cfg, thread, args.account)
    fetch = fetcher(cfg)
    found, stages, flattened = _harvest(cfg, messages, fetch)

    stage_lines = [f"  {k:<28}{v}" for k, v in stages.items()]
    warn = []
    if flattened:
        warn = ["", c("31", f"WARNING: {flattened} message(s) parsed as HTML but "
                            f"contained no anchors."),
                "That is the signature of a text-flattening body path, not an "
                "empty thread.", "Do not trust these counts."]

    if args.links_only or args.dry_run:
        lines = [c("1", thread.title), f"  backend {name}"] + stage_lines
        if args.links_only and not args.dry_run:
            lines += [""] + [f"- [{r['anchor'] or r['url']}]({r['url']})"
                             f"  — {r['who']}, {(r['at'] or '')[:10]}"
                             for r in found]
        if args.dry_run:
            lines.insert(0, c("33", "--dry-run: nothing written."))
        emit(args, {"thread": thread.title, "backend": name, "stages": stages,
                    "links": found}, lines + warn)
        return 0

    # Full harvest: resolve each paper link and file it.
    from ..naming import title_case_filename
    dest = library.folder(cfg, args.to or title_case_filename(thread.title))
    srcs = sources_for(args, cfg)

    added = []
    for r in found:
        if not r["is_paper"]:
            continue
        rec, _ = resolve.resolve(fetch, r["url"], srcs)
        if rec is None:
            continue
        rec = resolve.enrich(fetch, rec, srcs)
        added.append(library.add(cfg, fetch, rec, dest, kind=r["kind"],
                                 provenance={"shared_by": r["who"],
                                             "shared_at": r["at"],
                                             "source_url": r["url"]}))

    got = sum(1 for a in added if a.get("status") in ("downloaded", "have"))
    emit(args, {"thread": thread.title, "backend": name, "folder": str(dest),
                "stages": stages, "added": added},
         [c("1", thread.title), f"  backend {name}"] + stage_lines
         + ["", f"{len(added)} papers filed, {got} with local PDFs",
            f"  {dest}"] + warn)
    return 0


def cmd_search(args, cfg) -> int:
    from ..cli import c, emit

    mod, name, why = resolve_backend(cfg)
    if mod is None:
        print(f"paperctl: {why}", file=sys.stderr)
        return 2
    hits = mod.search(cfg, args.query, args.account, args.limit)
    lines = [f"{c('2', (h.get('date') or '')[:10])}  "
             f"{c('1', h.get('subject', ''))}\n    {h.get('from', '')}"
             for h in hits]
    emit(args, hits, lines or [f"no messages matching {args.query!r}"])
    return 0 if hits else 1


def register_cli(sub, add_cmd) -> None:
    """Attach `paperctl mail ...`. Called by cli.build_parser."""
    m = sub.add_parser("mail", help="harvest links and papers out of email")
    msub = m.add_subparsers(dest="mailcmd", required=True)

    t = msub.add_parser("thread", help="every paper shared in one email thread")
    t.add_argument("--subject", required=True,
                   help="a fragment of the thread's subject")
    t.add_argument("--account", help="backend account (himalaya); "
                                     "default is the backend's own")
    t.add_argument("--to", metavar="FOLDER",
                   help="library folder (default: the thread subject)")
    t.add_argument("--links-only", action="store_true",
                   help="list links; do not resolve or download papers")
    t.add_argument("--source", help="restrict metadata sources")
    t.add_argument("--dry-run", action="store_true",
                   help="show the counts at each stage; write nothing")
    t.add_argument("--json", action="store_true")
    t.set_defaults(fn=cmd_thread)

    s = msub.add_parser("search", help="find threads by subject or content")
    s.add_argument("query")
    s.add_argument("--account")
    s.add_argument("--limit", type=int, default=25)
    s.add_argument("--json", action="store_true")
    s.set_defaults(fn=cmd_search)
