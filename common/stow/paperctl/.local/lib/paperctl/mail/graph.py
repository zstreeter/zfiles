"""Microsoft Graph -- Outlook on the work laptop.

Reuses graph_client.py from the m365-email skill by path discovery rather than
vendoring a copy: the token refresh logic is fiddly, it already works, and two
copies would drift. One device-code login (~/.config/microsoft-graph/token.json)
covers every m365-* skill and this.

The $select list is the load-bearing part. body and uniqueBody must both be
requested, and both are HTML. See mail/__init__.py for why a text rendering is
not acceptable here.
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

from .types import Message, Thread

MSG_FIELDS = ("id,conversationId,subject,from,toRecipients,ccRecipients,"
              "receivedDateTime,sentDateTime,hasAttachments,webLink,"
              "body,uniqueBody")

# Subjects that are noise in every thread. Matched at the start only -- a real
# paper discussion can mention "out of office" in passing.
AUTOREPLY = ("automatic reply:", "out of office:", "autoreply:", "undeliverable:")

_CLIENT = None


def _client_paths() -> list[Path]:
    return [
        Path.home() / ".claude" / "skills" / "m365-email" / "scripts",
        Path.home() / ".agents" / "skills" / "m365-email" / "scripts",
        Path("/mnt/c/Users") / os.environ.get("USER", "") / "cowork"
        / "skills" / "m365-email" / "scripts",
    ]


def _client(cfg):
    """The shared GraphClient, or None with the reason left to probe()."""
    global _CLIENT
    if _CLIENT is not None:
        return _CLIENT
    for path in _client_paths():
        if (path / "graph_client.py").exists():
            sys.path.insert(0, str(path))
            try:
                from graph_client import GraphClient  # type: ignore
            except Exception:
                continue
            _CLIENT = GraphClient()
            return _CLIENT
    return None


def probe(cfg) -> tuple[bool, str, str]:
    token = cfg.path("mail.graph.token")
    found = next((p for p in _client_paths() if (p / "graph_client.py").exists()),
                 None)
    if not found:
        return False, "m365-email skill not installed", (
            "install the m365-email skill, or set mail.backend = himalaya")
    if not token.exists():
        return False, f"no token at {token}", (
            "python3 ~/.claude/skills/m365-teams/scripts/auth.py")
    client = _client(cfg)
    if client is None:
        return False, f"graph_client.py at {found} would not import", ""
    try:
        if not client.is_authenticated():
            return False, "token present but expired", (
                "python3 ~/.claude/skills/m365-teams/scripts/auth.py")
    except Exception as e:
        return False, f"token check failed: {type(e).__name__}", ""
    return True, f"authenticated, client from {found}", ""


def find_thread(cfg, subject: str, account=None) -> Thread | None:
    """Resolve a subject fragment to one conversation.

    Searches wide then filters client-side: $search tokenizes, so it
    over-matches on a long subject, while an exact-phrase $filter reliably
    under-returns. Over-matching and narrowing is the recoverable direction.
    """
    client = _client(cfg)
    if client is None:
        return None
    data = client.get("/me/messages", params={
        "$search": f'"subject:{subject}"',
        "$select": "id,conversationId,subject,receivedDateTime",
        "$top": 100,
    })
    frag = subject.lower()
    msgs = [m for m in (data or {}).get("value", []) or []
            if frag in (m.get("subject") or "").lower()]
    if not msgs:
        return None

    groups: dict[str, list[dict]] = {}
    for m in msgs:
        groups.setdefault(m.get("conversationId", ""), []).append(m)
    cid, members = max(groups.items(), key=lambda kv: len(kv[1]))
    if len(groups) > 1:
        print(f"paperctl: {len(groups)} conversations matched; taking the "
              f"largest ({len(members)} messages)", file=sys.stderr)

    members.sort(key=lambda m: m.get("receivedDateTime") or "")
    return Thread(id=cid, title=members[0].get("subject", subject),
                  message_ids=[m["id"] for m in members],
                  backend="graph")


def fetch_thread(cfg, thread: Thread, account=None) -> list[Message]:
    """Full bodies, one GET each.

    Per-message rather than a collection query because uniqueBody is not
    reliably returned on collections -- and uniqueBody is the whole point.
    """
    client = _client(cfg)
    if client is None:
        return []
    out = []
    for mid in thread.message_ids:
        try:
            full = client.get(f"/me/messages/{mid}",
                              params={"$select": MSG_FIELDS})
        except Exception as e:
            print(f"paperctl: message {mid[:12]}... failed: {type(e).__name__}",
                  file=sys.stderr)
            continue
        subject = full.get("subject") or ""
        if subject.lower().lstrip().startswith(AUTOREPLY):
            continue
        sender = (full.get("from") or {}).get("emailAddress") or {}
        out.append(Message(
            id=full.get("id", mid),
            sender=sender.get("name") or sender.get("address") or "unknown",
            sender_address=sender.get("address", ""),
            date=full.get("receivedDateTime") or full.get("sentDateTime") or "",
            subject=subject,
            html=(full.get("body") or {}).get("content") or "",
            html_unique=(full.get("uniqueBody") or {}).get("content"),
        ))
    out.sort(key=lambda m: m.date)
    return out


def search(cfg, query: str, account=None, limit: int = 25) -> list[dict]:
    client = _client(cfg)
    if client is None:
        return []
    data = client.get("/me/messages", params={
        "$search": f'"{query}"',
        "$select": "id,subject,from,receivedDateTime",
        "$top": limit,
    })
    out = []
    for m in (data or {}).get("value", []) or []:
        sender = (m.get("from") or {}).get("emailAddress") or {}
        out.append({"id": m.get("id"), "subject": m.get("subject", ""),
                    "from": sender.get("address", ""),
                    "date": m.get("receivedDateTime", "")})
    return out
