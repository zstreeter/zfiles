#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = ["google-api-python-client>=2.100", "google-auth-oauthlib>=1.2"]
# ///
"""Upload a stream recording to YouTube as PRIVATE, with the transcript as captions.

    youtube.py <video> <youtube.json> [captions.srt]   prints the video id
    youtube.py --check <youtube.json>                 validate metadata only, no network

Private is not negotiable here: making a video public is the user's call, in
YouTube Studio, after they've watched it.
"""
import json
import os
import sys
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "stream-post"
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "stream-post"
CLIENT_SECRET = CONFIG / "client_secret.json"
TOKEN = STATE / "youtube-token.json"
# force-ssl covers videos.insert and captions.insert; youtube.upload alone can't add captions.
SCOPES = ["https://www.googleapis.com/auth/youtube.force-ssl"]
EDUCATION = "27"


def load_meta(path):
    meta = json.loads(Path(path).read_text())
    title, desc = meta.get("title", "").strip(), meta.get("description", "").strip()
    tags = meta.get("tags", [])
    errors = []
    if not title or len(title) > 100:
        errors.append(f"title must be 1-100 characters (is {len(title)})")
    if len(desc) > 5000:
        errors.append(f"description must be at most 5000 characters (is {len(desc)})")
    if any(c in title + desc for c in "<>"):
        errors.append("YouTube rejects '<' and '>' in the title and description")
    if not isinstance(tags, list) or not all(isinstance(t, str) for t in tags):
        errors.append("tags must be a list of strings")
    elif len(",".join(tags)) > 500:
        errors.append("tags must total at most 500 characters")
    if errors:
        sys.exit(f"youtube.py: {path}:\n  " + "\n  ".join(errors))
    return title, desc, tags


def credentials():
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    creds = Credentials.from_authorized_user_file(TOKEN, SCOPES) if TOKEN.exists() else None
    if creds and creds.valid:
        return creds
    if creds and creds.expired and creds.refresh_token:
        creds.refresh(Request())
    else:
        if not CLIENT_SECRET.exists():
            sys.exit(f"youtube.py: no OAuth client at {CLIENT_SECRET} -- see the stream-post skill")
        creds = InstalledAppFlow.from_client_secrets_file(CLIENT_SECRET, SCOPES).run_local_server(port=0)
    STATE.mkdir(parents=True, exist_ok=True)
    TOKEN.touch(mode=0o600)
    TOKEN.write_text(creds.to_json())
    return creds


def upload(video, meta_path, srt=None):
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaFileUpload

    title, desc, tags = load_meta(meta_path)
    yt = build("youtube", "v3", credentials=credentials())
    body = {
        "snippet": {"title": title, "description": desc, "tags": tags, "categoryId": EDUCATION},
        "status": {"privacyStatus": "private", "selfDeclaredMadeForKids": False},
    }
    req = yt.videos().insert(part="snippet,status", body=body,
                             media_body=MediaFileUpload(video, chunksize=32 << 20, resumable=True))
    resp = None
    while resp is None:
        status, resp = req.next_chunk()
        if status:
            print(f"\ruploading {status.progress():.0%}", end="", file=sys.stderr, flush=True)
    print(file=sys.stderr)
    vid = resp["id"]
    print(f"uploaded {vid}, privacy: {resp['status']['privacyStatus']}", file=sys.stderr)

    if srt and Path(srt).exists():
        try:  # captions are a nicety; the video is up either way
            yt.captions().insert(
                part="snippet",
                body={"snippet": {"videoId": vid, "language": "en", "name": "Transcript"}},
                media_body=MediaFileUpload(srt, mimetype="application/octet-stream"),
            ).execute()
        except Exception as e:  # noqa: BLE001
            print(f"youtube.py: captions not added ({e}); YouTube's auto-captions still apply", file=sys.stderr)
    print(vid)


if __name__ == "__main__":
    args = sys.argv[1:]
    if len(args) == 2 and args[0] == "--check":
        load_meta(args[1])
    elif len(args) in (2, 3):
        upload(*args)
    else:
        sys.exit(__doc__)
