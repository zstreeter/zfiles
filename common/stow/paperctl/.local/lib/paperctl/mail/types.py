"""The two values every mail backend speaks in.

Separate from mail/__init__.py so the backends can import them while
mail/__init__.py imports the backends, without the two forming a cycle.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class Message:
    id: str = ""
    sender: str = ""
    sender_address: str = ""
    date: str = ""
    subject: str = ""
    html: str = ""
    html_unique: str | None = None

    @property
    def body(self) -> str:
        """What to extract links from: the reply-only body when we have one.

        uniqueBody is what makes attribution meaningful. Without it every
        replier appears to have shared every earlier link -- quoted history
        once inflated a single URL to 38 occurrences across one thread. A
        backend that cannot provide it sets None and accepts that cost.
        """
        return self.html_unique if self.html_unique is not None else self.html


@dataclass
class Thread:
    id: str = ""
    title: str = ""
    message_ids: list[str] = field(default_factory=list)
    account: str = ""
    backend: str = ""
    extra: dict = field(default_factory=dict)
