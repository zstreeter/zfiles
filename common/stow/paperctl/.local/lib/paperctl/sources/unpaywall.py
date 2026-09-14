"""Unpaywall -- legal open-access copies for a DOI.

Not in REGISTRY: it answers "where can I read this?" rather than "what is
this?", so it is a PDF locator, not a metadata source, and nothing should
search it.

Requires a contact email. That is Unpaywall's stated condition of use, not a
login -- it goes in local.toml as sources.unpaywall_email, because config.toml
is committed. With no email set, this returns nothing and the caller falls back
to whatever direct PDF links it already has.
"""

from __future__ import annotations

import json
import urllib.parse

API = "https://api.unpaywall.org/v2"


def pdf_url(fetch, doi: str, email: str) -> str:
    """Best open-access PDF for a DOI, or "" if there is none."""
    if not doi or not email:
        return ""
    url = (f"{API}/{urllib.parse.quote(doi)}"
           f"?email={urllib.parse.quote(email)}")
    try:
        data = json.loads(fetch.get_text(url, accept="application/json"))
    except Exception:
        return ""
    loc = data.get("best_oa_location") or {}
    # url_for_pdf is the direct file; url is the landing page. Preferring the
    # landing page would hand the downloader an HTML page to reject.
    return loc.get("url_for_pdf") or loc.get("url") or ""
