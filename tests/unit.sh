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
# Run a repo script as if installed, in the sandbox home, on a plain linux
# target whatever this host is; `sbx env ZFILES_TARGET=wsl ...` steers it.
sbx() { env -i HOME="$T/home" ZFILES_TARGET=linux PATH="$REPO/common/stow/scripts/.local/bin:/usr/bin:/bin" "$@"; }
mkdir -p "$T/home/.config/shell"
ln -s "$REPO/common/stow/shell/.config/shell/target.sh" "$T/home/.config/shell/target.sh"

# --- obsidian-vault ----------------------------------------------------------
V=$T/home/research/vault
mkdir -p "$V/.obsidian" "$V/drafts/2026/oct" "$T/loose"
touch "$V/drafts/2026/oct/post.md" "$T/loose/x.md"

eq "vault of nested file" "$(sbx obsidian-vault of "$V/drafts/2026/oct/post.md")" "$V"
eq "vault of vault dir"   "$(sbx obsidian-vault of "$V")" "$V"
sbx obsidian-vault of "$T/loose/x.md" 2>/dev/null && bad "vault of a file outside any vault succeeded"
eq "root default" "$(sbx obsidian-vault root)" "$T/home/research"
# On WSL new vaults go to the Windows side; a cached %APPDATA% stands in for cmd.exe.
W=$T/home/c/Users/u/AppData/Roaming; mkdir -p "$W" "$T/home/.cache/zfiles"
echo "$W" > "$T/home/.cache/zfiles/appdata"
eq "root on wsl" "$(sbx env ZFILES_TARGET=wsl obsidian-vault root)" "$T/home/c/Users/u/vaults"
rm "$T/home/.cache/zfiles/appdata"
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

# --- publish-lint: nothing local is ever published ----------------------------
L=$T/lint; mkdir -p "$L"; touch "$L/fig.png"
printf '[a](https://x.org) [m](mailto:a@b.c) [s](#s) $[[n,k,d]]$ ![f](fig.png) ![[fig.png]] [[@k]] @k\n' > "$L/ok.md"
sbx publish-lint "$L/ok.md" --target blog 2>/dev/null || bad "publish-lint rejected web links, maths, adjacent images or citations"
sbx publish-lint "$L/ok.md" --target confluence-md 2>/dev/null && bad "publish-lint passed citekeys/local images on confluence-md"
for case in 'see ~/Library/x' 'cd /home/u/p' 'go /mnt/c/Users' '[n](../notes/a.md)' '[[Vault Note]]' '![[gone.png]]' '```\nls $HOME/x\n```'; do
    printf "%b\n" "$case" > "$L/bad.md"
    sbx publish-lint "$L/bad.md" --target blog 2>/dev/null && bad "publish-lint passed: $case"
done
printf -- '---\ntitle: R\ndate: 2026-01-03\n---\nsee ~/x\n' > "$V/drafts/leak.md"
sbx publish-post "$V/drafts/leak.md" >/dev/null 2>&1 && bad "publish-post published a local path"
[[ -e $BLOG/posts/2026-01-03-leak ]] && bad "publish-post created a post dir before the lint gate"

# --- paperctl ----------------------------------------------------------------
(cd common/stow/paperctl/.local/lib && python3 -I -c 'import sys; sys.path.insert(0, ".")
from paperctl import library, alphaxiv, resolve
library._selftest(); alphaxiv.demo(); resolve._selftest()' >/dev/null) || bad "paperctl selftests"

# --- lean-sandbox (check's verdict logic, against a fake lake) ---------------
LS=$REPO/common/stow/lean/.local/bin/lean-sandbox
mkdir -p "$T/fakebin" "$T/sbx"
printf '#!/bin/sh\ncat "$FAKE_OUT"\n' > "$T/fakebin/lake"; chmod +x "$T/fakebin/lake"
touch "$T/x.lean"
lchk() { printf '%s\n' "$1" > "$T/out"
    env -i HOME="$T/home" PATH="$T/fakebin:/usr/bin:/bin" LEAN_SANDBOX="$T/sbx" FAKE_OUT="$T/out" \
        "$LS" check "$T/x.lean" >/dev/null 2>&1; }
lchk "'t' depends on axioms: [propext, Classical.choice, Quot.sound]" || bad "lean check rejected standard axioms"
lchk "'t' does not depend on any axioms" || bad "lean check rejected an axiom-free proof"
lchk "'t' depends on axioms: [propext, sorryAx]" && bad "lean check passed sorryAx"
lchk "warning: declaration uses 'sorry'" && bad "lean check passed a sorry warning"
lchk "'t' depends on axioms: [cheat, propext]" && bad "lean check passed a custom axiom"
lchk "'t' depends on axioms: [propext,
  Classical.choice,
  a_custom_axiom_on_a_wrapped_line]" && bad "lean check passed a custom axiom on a wrapped line"
lchk "no axioms printed" && bad "lean check passed a file without #print axioms"
eq "lean path override" "$(env -i HOME="$T/home" LEAN_SANDBOX=/x "$LS" path)" "/x"

# --- target contract (bootstrap --plan: resolve, print, touch nothing) --------
plan() { env -i HOME="$T/planhome" PATH=/usr/bin:/bin "$@" "$REPO/bootstrap.sh" --plan 2>&1; }
for t in omarchy wsl linux remote; do
    p=$(plan env ZFILES_TARGET=$t)
    grep -qx "TARGET=$t" <<<"$p" || bad "plan $t: $p"
    grep -qx "STOW=shell" <<<"$p" || bad "plan $t does not stow shell (bootstrap sources its target.sh)"
    if [[ $t == omarchy ]]; then want=false; else want=true; fi
    grep -qx "STATIC_THEME=$want" <<<"$p" || bad "plan $t: STATIC_THEME should be $want"
    if [[ $t == remote ]]; then want=false; else want=true; fi
    grep -qx "OWNS_HOME=$want" <<<"$p" || bad "plan $t: OWNS_HOME should be $want"
done
eq "remote stows exactly remote/stow.txt" \
    "$(plan env ZFILES_TARGET=remote | sed -n 's/^STOW=//p' | sort | tr '\n' ' ')" \
    "$(grep -v '^#' remote/stow.txt | grep -v '^$' | sort | tr '\n' ' ')"
while read -r pkg; do
    [[ -d common/stow/$pkg ]] || bad "remote/stow.txt names a package not in common/stow: $pkg"
done < <(grep -v '^#' remote/stow.txt | grep -v '^$')
grep -qx STOW=wsl <<<"$(plan env ZFILES_TARGET=wsl)" || bad "plan wsl does not stow wsl/stow"
plan env ZFILES_TARGET=bogus >/dev/null && bad "plan accepted an unknown target"
mkdir -p "$T/planhome/.local/state/zfiles" && touch "$T/planhome/.local/state/zfiles/remote"
grep -qx TARGET=remote <<<"$(plan)" || bad "remote marker not honoured"
rm -rf "$T/planhome"; plan >/dev/null; [[ -e $T/planhome ]] && bad "bootstrap --plan wrote to \$HOME"
# Shared steps branch on the contract, never on which target they run for.
grep -nE '\$(REMOTE|OMARCHY|WSL)\b|TARGET ?==' common/setup.sh && bad "common/setup.sh branches on the target"

((fails)) && { echo "unit: $fails failed" >&2; exit 1; }
echo "unit: ok"
