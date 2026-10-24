#!/usr/bin/env bash
# unit.sh — fast, offline tests of logic that has broken before.
#
#   tests/unit.sh     common/githooks/check runs it before every push
#
# Scripts run against a throwaway $HOME, never the real one.
set -uo pipefail
cd "$(dirname "$0")/.."
REPO=$PWD

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
ok()  { :; }
bad() { echo "unit: FAIL $*" >&2; fails=$((fails + 1)); }
eq()  { [[ $2 == "$3" ]] && ok || bad "$1: expected [$3], got [$2]"; }
# Run a repo script as if installed, in the sandbox home, off the WSL path.
sbx() { env -i HOME="$T/home" PATH="$REPO/common/stow/scripts/.local/bin:/usr/bin:/bin" "$@"; }
mkdir -p "$T/home"

# --- obsidian-vault ----------------------------------------------------------
V=$T/home/research/vault
mkdir -p "$V/.obsidian" "$V/drafts/2026/oct" "$T/loose"
touch "$V/drafts/2026/oct/post.md" "$T/loose/x.md"

eq "vault of nested file" "$(sbx obsidian-vault of "$V/drafts/2026/oct/post.md")" "$V"
eq "vault of vault dir"   "$(sbx obsidian-vault of "$V")" "$V"
sbx obsidian-vault of "$T/loose/x.md" 2>/dev/null && bad "vault of a file outside any vault succeeded"
eq "root default"   "$(sbx obsidian-vault root)" "$T/home/research"
eq "root override"  "$(sbx env ZFILES_VAULT_ROOT=/elsewhere obsidian-vault root)" "/elsewhere"
eq "path finds the research vault" "$(sbx obsidian-vault path)" "$V"
eq "path by name"   "$(sbx obsidian-vault path vault)" "$V"
eq "path pinned"    "$(sbx env ZFILES_OBSIDIAN_VAULT="$T/loose" obsidian-vault path)" "$T/loose"
eq "help starts at the header" "$(sbx obsidian-vault help | head -1)" "obsidian-vault — resolve Obsidian vault locations on any zfiles target."

# --- publish-post ------------------------------------------------------------
BLOG=$T/home/Documents/Repos/zstreeter.github.io
mkdir -p "$BLOG"
echo '@book{k, title={T}}' > "$V/references.bib"
printf -- '---\ntitle: P\ndate: 2026-01-02\n---\nBody @k\n' > "$V/drafts/2026/oct/post.md"
sbx publish-post "$V/drafts/2026/oct/post.md" >/dev/null || bad "publish-post failed"
P=$BLOG/posts/2026-01-02-post
[[ -f $P/references.bib ]] || bad "publish-post: bib not copied from a draft nested two levels deep"
eq "bibliography pinned once" "$(grep -c '^bibliography: \[references.bib\]' "$P/index.qmd")" 1
eq "pinned inside front matter" "$(sed -n 4p "$P/index.qmd")" "bibliography: [references.bib]"

printf 'No front matter.\n\n---\n\nbibliography: prose\n' > "$V/drafts/bare.md"
sbx publish-post "$V/drafts/bare.md" >/dev/null || bad "publish-post failed on a bare draft"
B=$(echo "$BLOG"/posts/*-bare/index.qmd)
cmp -s "$B" "$V/drafts/bare.md" || bad "publish-post edited a draft without front matter"

printf -- '---\ntitle: Q\nbibliography: mine.bib\n---\n' > "$V/drafts/own.md"
sbx publish-post "$V/drafts/own.md" >/dev/null
eq "keeps a draft's own bibliography" "$(grep -c '^bibliography:' "$BLOG"/posts/*-own/index.qmd)" 1
sbx publish-post "$V/drafts/own.md" >/dev/null 2>&1 && bad "publish-post overwrote an existing post"

# --- paperctl ----------------------------------------------------------------
(cd common/stow/paperctl/.local/lib && python3 -I -c 'import sys; sys.path.insert(0, ".")
from paperctl import library, alphaxiv, resolve
library._selftest(); alphaxiv.demo(); resolve._selftest()' >/dev/null) || bad "paperctl selftests"

((fails)) && { echo "unit: $fails failed" >&2; exit 1; }
echo "unit: ok"
