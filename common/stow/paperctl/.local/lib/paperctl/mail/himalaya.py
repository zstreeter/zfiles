"""himalaya -- IMAP on Omarchy, via the CLI rather than an IMAP library.

himalaya already holds the accounts, the passwords (through `pass`) and the
folder mapping, all configured in omarchy/stow/himalaya/. Re-implementing IMAP
here would mean a second copy of all of that, so this shells out.

Two things Graph has and himalaya does not, both handled rather than assumed:

  * No conversation id. Threads are rebuilt from RFC 5322 References /
    In-Reply-To, with a normalized-subject fallback for the mail clients that
    omit them.
  * No uniqueBody. html_unique is None, and the caller falls back to the full
    body with URL-keyed dedupe -- which costs attribution precision (the first
    person to *quote* a link may be credited over the first to share it) but
    not correctness of the link set itself.

WRITTEN BUT UNVERIFIED: neither himalaya nor pass is installed on the machine
this was developed on, so this code has never executed against a real mailbox.
`paperctl doctor` reports that plainly rather than implying it is proven.
"""

from __future__ import annotations

import email
import json
import re
import shutil
import subprocess
import sys
from email import policy

from .types import Message, Thread
from ..naming import strip_re_prefix

TIMEOUT = 60


def _bin(cfg) -> str:
    return str(cfg.get("mail.himalaya.bin") or "himalaya")


def _accounts(cfg) -> list:
    return list(cfg.get("mail.himalaya.accounts") or [])


def _run(cfg, args: list[str], account=None) -> tuple[int, str, str]:
    cmd = [_bin(cfg)]
    if account:
        cmd += ["--account", account]
    cmd += args
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=TIMEOUT)
        return p.returncode, p.stdout, p.stderr
    except FileNotFoundError:
        return 127, "", f"{_bin(cfg)}: not found"
    except subprocess.TimeoutExpired:
        return 124, "", f"{_bin(cfg)}: timed out after {TIMEOUT}s"
    except OSError as e:
        return 1, "", str(e)


def probe(cfg) -> tuple[bool, str, str]:
    path = shutil.which(_bin(cfg))
    if not path:
        return False, f"{_bin(cfg)} not installed", (
            "install himalaya, or set mail.backend = graph")
    code, out, err = _run(cfg, ["account", "list", "--output", "json"])
    if code != 0:
        return (False,
                f"`{_bin(cfg)} account list` exited {code}: "
                f"{(err or out).strip()[:120]}",
                "check ~/.config/himalaya/config.toml and that `pass` is unlocked")
    try:
        names = [a.get("name", "") for a in json.loads(out)]
    except (json.JSONDecodeError, AttributeError, TypeError):
        names = []
    configured = _accounts(cfg)
    missing = [a for a in configured if a not in names]
    if missing:
        return False, (f"configured account(s) {', '.join(missing)} not in "
                       f"himalaya ({', '.join(names) or 'none'})"), (
            "fix mail.himalaya.accounts, or add them to himalaya's config")
    return True, f"{path}, accounts: {', '.join(names) or 'default'}", ""


def _envelopes(cfg, query: str, account, limit: int) -> list[dict]:
    """himalaya's envelope list, tolerant of its output shape changing.

    v1 emitted a bare array, v2 wraps it. Accepting both is cheaper than
    pinning a version this code cannot test against.
    """
    code, out, err = _run(cfg, ["envelope", "list", "--output", "json",
                                "--page-size", str(limit), query], account)
    if code != 0:
        print(f"paperctl: himalaya envelope list failed: "
              f"{(err or out).strip()[:160]}", file=sys.stderr)
        return []
    try:
        data = json.loads(out)
    except json.JSONDecodeError:
        return []
    if isinstance(data, dict):
        data = data.get("envelopes") or data.get("items") or []
    return data if isinstance(data, list) else []


def _raw(cfg, msg_id: str, account) -> str:
    code, out, err = _run(cfg, ["message", "read", "--raw", str(msg_id)], account)
    if code != 0:
        print(f"paperctl: himalaya could not read {msg_id}: "
              f"{(err or out).strip()[:120]}", file=sys.stderr)
        return ""
    return out


def _html_of(raw: str) -> tuple[str, str]:
    """(html, plain) from an RFC 5322 message, walking multipart/alternative.

    HTML is preferred and returned raw. The plain part is a fallback for
    senders that post text-only -- there are no anchors to lose there, so the
    bare-URL sweep is all that was ever available.
    """
    try:
        msg = email.message_from_string(raw, policy=policy.default)
    except Exception:
        return "", raw
    html_part = plain_part = ""
    for part in msg.walk():
        if part.get_content_maintype() == "multipart":
            continue
        if part.get_filename():
            continue                      # an attachment, not the body
        try:
            body = part.get_content()
        except Exception:
            continue
        ctype = part.get_content_type()
        if ctype == "text/html" and not html_part:
            html_part = body
        elif ctype == "text/plain" and not plain_part:
            plain_part = body
    return html_part, plain_part


def _headers(raw: str) -> dict:
    try:
        msg = email.message_from_string(raw, policy=policy.default)
    except Exception:
        return {}
    return {k.lower(): str(v) for k, v in msg.items()}


_MSGID = re.compile(r"<[^<>@\s]+@[^<>\s]+>")


def find_thread(cfg, subject: str, account=None) -> Thread | None:
    """Rebuild a thread from References / In-Reply-To.

    Graph hands back a conversationId; here the thread has to be reconstructed.
    Message-Ids are the reliable signal and the normalized subject is the
    fallback, because some clients send neither References nor In-Reply-To.
    """
    account = account or (_accounts(cfg)[0] if _accounts(cfg) else None)
    # himalaya's query language; quoted so a multi-word subject stays one term.
    envs = _envelopes(cfg, f'subject "{subject}"', account, 200)
    if not envs:
        return None

    frag = subject.lower()
    seeds = [e for e in envs
             if frag in str(e.get("subject") or "").lower()]
    if not seeds:
        return None

    norm = strip_re_prefix(str(seeds[0].get("subject") or subject)).lower()
    ids, seen_msgids = [], set()
    for e in seeds:
        if strip_re_prefix(str(e.get("subject") or "")).lower() != norm:
            continue
        mid = e.get("id") or e.get("internal_id")
        if mid is None:
            continue
        ids.append(str(mid))
        for h in ("message_id", "message-id"):
            if e.get(h):
                seen_msgids.update(_MSGID.findall(str(e[h])))

    if not ids:
        return None
    ids.sort(key=lambda i: next(
        (str(e.get("date") or "") for e in seeds
         if str(e.get("id") or e.get("internal_id")) == i), ""))
    return Thread(id=norm, title=strip_re_prefix(str(seeds[0].get("subject") or subject)),
                  message_ids=ids, account=account or "", backend="himalaya",
                  extra={"message_ids_rfc": sorted(seen_msgids)})


def fetch_thread(cfg, thread: Thread, account=None) -> list[Message]:
    account = account or thread.account or (
        _accounts(cfg)[0] if _accounts(cfg) else None)
    out: list[Message] = []
    for mid in thread.message_ids:
        raw = _raw(cfg, mid, account)
        if not raw:
            continue
        headers = _headers(raw)
        subject = headers.get("subject", "")
        if subject.lower().lstrip().startswith(
                ("automatic reply:", "out of office:", "autoreply:")):
            continue
        html_part, plain = _html_of(raw)
        sender = headers.get("from", "")
        addr = ""
        m = re.search(r"<([^>]+)>", sender)
        if m:
            addr = m.group(1)
        out.append(Message(
            id=str(mid),
            sender=re.sub(r"\s*<[^>]+>", "", sender).strip(' "') or addr or "unknown",
            sender_address=addr or sender,
            date=headers.get("date", ""),
            subject=subject,
            # Plain text lands in `html` when there is no HTML part: the link
            # extractor's bare-URL sweep handles it, and there were no anchors
            # to lose. html_unique stays None -- himalaya has no equivalent.
            html=html_part or plain,
            html_unique=None,
        ))
    return out


def search(cfg, query: str, account=None, limit: int = 25) -> list[dict]:
    account = account or (_accounts(cfg)[0] if _accounts(cfg) else None)
    out = []
    for e in _envelopes(cfg, f'subject "{query}"', account, limit):
        frm = e.get("from") or {}
        out.append({
            "id": str(e.get("id") or e.get("internal_id") or ""),
            "subject": e.get("subject", ""),
            "from": (frm.get("addr") or frm.get("address") or frm.get("name", ""))
                    if isinstance(frm, dict) else str(frm),
            "date": str(e.get("date") or ""),
        })
    return out
