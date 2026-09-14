"""HTTP, with the manners the scholarly APIs actually ask for.

Stdlib urllib rather than requests, because this has to run on the work server
where installing anything is a ticket. The politeness is not decoration: arXiv,
Crossref and OpenAlex all publish rate expectations and all degrade a noisy
client rather than refusing it outright, which is the worst failure mode to
debug -- results just get slower and thinner.
"""

from __future__ import annotations

import ssl
import time
import urllib.error
import urllib.parse
import urllib.request

DEFAULT_UA = "paperctl/1.0 (+https://github.com/zstreeter/zfiles)"

# Retried: transient by definition. 429 is included because every one of these
# APIs prefers a slow client to a blocked one, and 5xx is the publisher having
# a bad minute. 403 and 404 are deliberately absent -- a paywall does not open
# on the second ask, and retrying it just makes the run take four times longer
# to reach the same "link-only".
RETRY_STATUS = {408, 425, 429, 500, 502, 503, 504}


class Fetch:
    """A configured fetcher. Timeouts and retries come from config, not here."""

    def __init__(self, user_agent: str = DEFAULT_UA, timeout: int = 30,
                 retries: int = 2, mailto: str = ""):
        self.ua = user_agent
        self.timeout = timeout
        self.retries = max(0, int(retries))
        # Crossref and OpenAlex both route a request carrying a contact address
        # into a faster, more reliable pool. It is not authentication and it is
        # not required; it is the difference between the polite and the common
        # pool. Empty is fine and simply forgoes that.
        self.mailto = mailto
        self._ctx = _ssl_ctx()

    def _open(self, url: str, accept: str, timeout: int | None):
        req = urllib.request.Request(url, headers={
            "User-Agent": (f"{self.ua} mailto:{self.mailto}"
                           if self.mailto else self.ua),
            "Accept": accept,
        })
        return urllib.request.urlopen(
            req, timeout=timeout or self.timeout, context=self._ctx)

    def get(self, url: str, accept: str = "*/*",
            timeout: int | None = None) -> bytes:
        """Bytes, or raise. Retries only what is worth retrying."""
        last: Exception | None = None
        for attempt in range(self.retries + 1):
            try:
                with self._open(url, accept, timeout) as r:
                    return r.read()
            except urllib.error.HTTPError as e:
                last = e
                if e.code not in RETRY_STATUS:
                    raise
                # Retry-After is authoritative when present; a server that
                # tells you when to come back has already answered the
                # question backoff is guessing at.
                wait = _retry_after(e) or (2 ** attempt)
            except (urllib.error.URLError, TimeoutError, OSError) as e:
                last = e
                wait = 2 ** attempt
            if attempt < self.retries:
                time.sleep(min(wait, 30))
        raise last if last else RuntimeError(f"unreachable: {url}")

    def get_text(self, url: str, accept: str = "*/*",
                 timeout: int | None = None) -> str:
        return self.get(url, accept, timeout).decode("utf-8", "replace")

    def final_url(self, url: str, timeout: int = 20) -> str:
        """Where a shortener actually lands. Never raises: the original URL is
        a usable answer, and a shortener that will not resolve is not a reason
        to lose the link."""
        try:
            with self._open(url, "*/*", timeout) as r:
                return r.geturl()
        except urllib.error.HTTPError as e:
            return e.url or url
        except Exception:
            return url

    def reachable(self, url: str, timeout: int = 8) -> bool:
        """For `doctor`. An HTTP error still proves the network path works."""
        try:
            with self._open(url, "*/*", timeout):
                return True
        except urllib.error.HTTPError:
            return True
        except Exception:
            return False


def _retry_after(e: urllib.error.HTTPError) -> float:
    try:
        return float(e.headers.get("Retry-After", ""))
    except (TypeError, ValueError):
        return 0.0


def _ssl_ctx() -> ssl.SSLContext:
    """Corporate TLS interception is the normal case on the work laptop.

    certifi is not guaranteed present, and the system store is what the proxy's
    root actually lands in, so the default context is correct here. This used
    to fall back to an unverified context on any exception, which turned a
    misconfigured trust store into a silent downgrade -- if verification cannot
    be set up, that is worth failing on.
    """
    return ssl.create_default_context()


def qs(**params) -> str:
    """Query string from keyword args, dropping the empty ones."""
    return urllib.parse.urlencode(
        {k: v for k, v in params.items() if v not in (None, "", [])})
