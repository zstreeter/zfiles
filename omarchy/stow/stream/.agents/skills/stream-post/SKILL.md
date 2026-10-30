---
name: stream-post
description: Turn a Twitch stream recording into a blog draft and YouTube metadata, then publish both behind a human review. Use when the user has finished a stream, mentions stream-post, a stream recording, a VOD, or wants a stream written up, uploaded to YouTube, or posted to the blog.
---

# stream-post

The user streams learning math, physics and AI on Twitch. Every stream becomes
a YouTube video and a blog post on zstreeter.github.io, and **nothing goes
public until the user has checked it**.

```
OBS records ~/Videos/stream/<stamp>.mp4 while live (hybrid mp4, OBS chapter markers)
stream-post prep      transcript + markers -> agent drafts   <- you are usually here
  (user reviews the draft in Obsidian and <stamp>.d/youtube.json)
stream-post publish   YouTube upload as PRIVATE, video embedded, post staged in the blog repo
  (user previews, flips the video public in YouTube Studio)
stream-post live      commits + pushes the blog post
```

Run `stream-post status` to see where each recording is. Never run `publish`
or `live` unless the user asks for that step by name: they are the review gates.

## Drafting (what `stream-post prep` asks an agent to do)

Inputs, in the session directory `<stamp>.d/` next to the recording:

- `transcript.txt` and `transcript.srt` -- whisper.cpp output. Expect misheard
  math terms; fix them from context (it's "Hilbert space", not "Gilbert space").
- `markers.txt` -- `HH:MM:SS<TAB>name`, one per OBS chapter marker the user
  dropped with SUPER+CTRL+ALT+M. May be empty. They mark moments the user
  wanted to find again, so they are strong chapter candidates.

Write exactly these, and nothing else:

1. **`<vault>/drafts/<slug>.qmd`** -- the blog post. Front matter:
   ```yaml
   ---
   title: "..."
   author: "Zachary Streeter"
   date: YYYY-MM-DD        # the recording's date (from its file name)
   categories: [...]       # e.g. Math, Physics, AI, Lean
   description: "One sentence."
   ---
   ```
   The body is a write-up of what was *learned*, not a transcript summary:
   the question the stream set out to answer, the ideas worked through in
   order, the math in LaTeX (`$...$`, `$$...$$`), the dead ends worth knowing
   about, open questions, and good questions from chat when the transcript
   shows them. First person, the user's voice, plain and direct. Leave out
   stream housekeeping (starting soon, mic checks, breaks). Do not invent results
   the stream did not reach; if something was left unresolved, say so. Anything
   you add that wasn't on stream (an example, a cleaner proof, a correction)
   goes in a `:::{.callout-note title="Added in the write-up"}` block, so the
   user can see it and keep or cut it.
   Only `https://` links, no local paths and no `[[wikilinks]]` (publish-lint
   refuses them).

2. **`<stamp>.d/youtube.json`**:
   ```json
   {
     "title": "under 100 characters, says what was learned",
     "description": "2-4 sentence summary, a blank line, then chapters",
     "tags": ["lowercase", "topics"]
   }
   ```
   Chapters go at the end of the description, one per line, `0:00 Intro`
   first, then `M:SS Title` or `H:MM:SS Title`, ascending. YouTube only shows
   chapters with at least 3 entries, the first at 0:00, each at least 10
   seconds long.

3. **`<stamp>.d/slug`** -- the slug alone on one line: lowercase,
   hyphenated, a few words, no date (publish-post adds the date).

## Publishing details

- The YouTube upload is always requested as **private**. Google may also lock
  uploads from an unaudited API project to private. If so, the user either
  requests the free audit once or uploads in YouTube Studio by hand and runs
  `stream-post publish --video <url>`.
- OAuth client: `~/.config/stream-post/client_secret.json` (Google Cloud,
  "Desktop app" client, YouTube Data API v3 enabled). The first upload opens a
  browser for consent; the token is cached in `~/.local/state/stream-post/`.
  Set the OAuth consent screen to **In production** (no verification needed
  for personal use; click through the "unverified app" warning once): in
  "Testing" Google expires the token every 7 days. A dead token just re-opens
  the browser.

## While streaming

- SUPER+CTRL+ALT: 1-5 scenes, M chapter marker, U mic mute, P hide the focused
  window from the stream (`no_screen_share`; use it for anything showing keys).
- The webcam is on whenever OBS is open -- the Linux camera source has no
  "off when not shown" option. Close OBS to free it.
- Twitch chat in a terminal: `twt` (twitch-tui; needs its own Twitch login).
- The blog post comes out of the vault draft via `publish-post` (see the
  `quarto` skill), which runs publish-lint first.
