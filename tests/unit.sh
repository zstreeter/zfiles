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
# On WSL the default root is the Windows side (needs cmd.exe), so it is a non-WSL default.
grep -qi microsoft /proc/version 2>/dev/null \
    || eq "root default" "$(sbx obsidian-vault root)" "$T/home/research"
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

# --- zdraft: one reading of a draft for every publish script ----------------
(cd common/stow/scripts/.local/lib && python3 -I -c 'import sys; sys.path.insert(0, ".")
import zdraft; zdraft._selftest()') || bad "zdraft selftest"
# Lint and publisher see the same maths: here neither does, so the gate must see [[Note]].
printf '$x$$[[Note]]$\n' > "$L/adj.md"
sbx publish-lint "$L/adj.md" --target confluence-md 2>/dev/null && bad "publish-lint masked maths publish-confluence publishes as text"
PC=$REPO/wsl/stow/wsl/.local/bin/publish-confluence
eq "confluence finds no maths in \$x\$\$[[Note]]\$" "$(python3 -I -c 'import sys, importlib.util as u, importlib.machinery as m
pc = u.module_from_spec(u.spec_from_loader("pc", m.SourceFileLoader("pc", sys.argv[1]))); pc.__spec__.loader.exec_module(pc)
print(pc.extract_math(open(sys.argv[2]).read())[1])' "$PC" "$L/adj.md")" "[]"
# --via-quarto renders from the vault (the Quarto project), however deep the draft.
QV=$T/qvault; mkdir -p "$QV/.obsidian" "$QV/drafts/2026/oct"; touch "$QV/_quarto.yml" "$QV/drafts/2026/oct/d.qmd"
eq "confluence renders a nested draft from its vault" "$(python3 -I -c 'import sys, types, importlib.util as u, importlib.machinery as m
pc = u.module_from_spec(u.spec_from_loader("pc", m.SourceFileLoader("pc", sys.argv[1]))); pc.__spec__.loader.exec_module(pc)
def run(cmd, cwd=None, **kw):
    print(cwd, cmd[2]); return types.SimpleNamespace(returncode=1, stdout="", stderr="")
pc.subprocess = types.SimpleNamespace(run=run)
try: pc.quarto_body(sys.argv[2])
except SystemExit: pass' "$PC" "$QV/drafts/2026/oct/d.qmd")" "$QV drafts/2026/oct/d.qmd"
# vault-doctor reads citekeys with the same grammar: Better BibTeX keys included.
mkdir -p "$V/notes"; printf 'See [[@smith_2003]] and @doe.2020, not `@code`.\n' > "$V/notes/k.md"
printf '@article{doe.2020,\n}\n' > "$V/refs.bib"
out=$(sbx vault-doctor "$V" 2>&1)
grep -q 'citekey @smith_2003 not in any .bib' <<<"$out" || bad "vault-doctor missed BBT key smith_2003"
grep -q 'citekey @doe.2020 not' <<<"$out" && bad "vault-doctor missed doe.2020 in the .bib"
grep -q '@code' <<<"$out" && bad "vault-doctor read a citekey inside code"
rm -f "$V/notes/k.md" "$V/refs.bib"

# --- paperctl ----------------------------------------------------------------
(cd common/stow/paperctl/.local/lib && python3 -I -c 'import sys; sys.path.insert(0, ".")
from paperctl import identity, sources, library, ingest, mail, alphaxiv, resolve
identity._selftest(); sources._selftest(); library._selftest(); ingest._selftest(); mail._selftest(); alphaxiv.demo(); resolve._selftest()' >/dev/null) || bad "paperctl selftests"

# A library written before citekeys were persisted: refs.bib showed the second key
# suffixed, the index did not, and `remove` of the key you could see failed.
P=$T/plib/F; mkdir -p "$P"
printf '%s' '{"entries": [
  {"ident": "10.1234/a", "doi": "10.1234/a", "citekey": "kTwi2020", "title": "Twin A", "added": "2020-01-01", "status": "link-only"},
  {"ident": "10.1234/b", "doi": "10.1234/b", "citekey": "kTwi2020", "title": "Twin B", "added": "2020-01-02", "status": "link-only"}]}' > "$P/.paperctl.json"
PC() { env -i HOME="$T/home" PATH=/usr/bin:/bin "$REPO/common/stow/paperctl/.local/bin/paperctl" --library "$T/plib" "$@"; }
PC remove kTwi2020a --from F >/dev/null || bad "paperctl remove of a suffixed legacy citekey failed"
eq "remove took the suffixed twin" "$(PC search Twin --json | python3 -c 'import json,sys; print(" ".join(e["title"] for e in json.load(sys.stdin)))')" "Twin A"
grep -q '{kTwi2020,' "$P/refs.bib" || bad "refs.bib lost the remaining key"

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

((fails)) && { echo "unit: $fails failed" >&2; exit 1; }
echo "unit: ok"
