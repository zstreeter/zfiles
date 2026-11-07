#!/usr/bin/env bash
# unit.sh — fast, offline tests of logic that has broken before.
#
#   tests/unit.sh     common/githooks/check runs it before every push
#
# Scripts run against a throwaway $HOME, never the real one.
set -uo pipefail
# A hook exports GIT_DIR (always, from a worktree): every fixture repo below would
# then commit into this one. Seen: a push from a worktree flipped core.bare.
unset $(git rev-parse --local-env-vars)
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
# mcp: every installed harness gets lean-lsp once; a re-run adds nothing; none installed is an error.
H=$T/harness; mkdir -p "$H"
for h in pi claude codex; do
    cat > "$H/$h" <<'FAKE'
#!/bin/sh
me=$(basename "$0"); echo "$me $*" >> "$H/log"
case "$2" in
    add) touch "$H/$me.reg" ;;
    get) [ -e "$H/$me.reg" ] ;;
    list) [ -e "$H/$me.reg" ] && echo "lean-lsp: connected" ;;
esac
FAKE
    chmod +x "$H/$h"
done
printf '#!/bin/sh\n' > "$H/uvx"; chmod +x "$H/uvx"
lmcp() { env -i HOME="$T/home" H="$H" PATH="$H:/usr/bin:/bin" "$LS" mcp >/dev/null 2>&1; }
lmcp || bad "lean-sandbox mcp failed"
eq "mcp registers with each harness" "$(grep -c ' mcp add ' "$H/log")" 3
grep -q '^claude mcp add --scope user lean-lsp -- uvx lean-lsp-mcp$' "$H/log" || bad "claude not registered at user scope"
: > "$H/log"; lmcp
eq "mcp re-run adds nothing" "$(grep -c ' mcp add' "$H/log")" 0
rm "$H/pi" "$H/claude" "$H/codex"; lmcp && bad "lean-sandbox mcp succeeded with no harness installed"
eq "lean path override" "$(env -i HOME="$T/home" LEAN_SANDBOX=/x "$LS" path)" "/x"

# --- stream-post (status, publish --video, embed once; offline) --------------
SP="$REPO/omarchy/stow/stream/.local/bin/stream-post"
BLOG="$T/home/Documents/Repos/zstreeter.github.io"
spx() { sbx env ZFILES_OBSIDIAN_VAULT="$V" STREAM_REC_DIR="$T/rec" "$SP" "$@"; }
mkdir -p "$T/rec/s1.d" "$BLOG/posts/2025-03-01-lie-pauli"  # a different post whose name ends in the slug
git -C "$BLOG" init -q
touch -d '-5 min' "$T/rec/s1.mp4"
eq "stream-post status, new" "$(spx status | tr -s ' ')" "s1 new (stream-post prep)"
echo hi > "$T/rec/s1.d/transcript.txt"
eq "stream-post status, transcribed" "$(spx status | tr -s ' ')" "s1 transcribed"
echo pauli > "$T/rec/s1.d/slug"
echo '{"title":"t","description":"d","tags":[]}' > "$T/rec/s1.d/youtube.json"
printf -- '---\ntitle: "P"\ndate: 2026-10-29\n---\n\nBody.\n' > "$V/drafts/pauli.qmd"
# An id may start with "-"; it must not be read as a grep option.
spx publish --video "https://www.youtube.com/watch?v=-bcdefghijk&t=3" >/dev/null 2>&1 || bad "stream-post publish --video failed"
eq "stream-post video id from URL" "$(cat "$T/rec/s1.d/youtube-id")" -bcdefghijk
spx publish >/dev/null 2>&1 || bad "stream-post publish re-run failed"
eq "stream-post embeds once" "$(grep -c 'video https://www.youtube.com/watch?v=-bcdefghijk' "$V/drafts/pauli.qmd")" 1
eq "stream-post staged its own post, not lie-pauli" "$(cat "$T/rec/s1.d/post")" "posts/2026-10-29-pauli"
git -C "$BLOG" add -A && git -C "$BLOG" -c user.name=t -c user.email=t@t commit -qm x
eq "stream-post status, committed but no upstream" "$(spx status | tr -s ' ')" "s1 committed, not pushed (stream-post live)"
spx publish --video "not a video" >/dev/null 2>&1 && bad "stream-post accepted a URL with no video id"
# speech_only drops cues whisper invents over silence, keeps real ones (short too).
source <(sed -n '/^speech_only() {/,/^}/p' "$SP")
printf 'Speech segment 0: start = 100.00, end = 1100.00\nSpeech segment 1: start = 6000.00, end = 6060.00\n' > "$T/seg.txt"
printf '1\n00:00:01,000 --> 00:00:11,000\n real\n\n2\n00:00:30,000 --> 00:00:59,900\n Thank you.\n\n3\n00:01:00,000 --> 00:01:00,700\n Yes.\n\n4\n00:02:31,020 --> 00:02:31,020\n Thank you.\n\n' > "$T/in.srt"
eq "speech_only keeps speech, drops invented cues" "$(speech_only "$T/seg.txt" "$T/in.srt" | grep -v -- '-->' | grep '^ ' | tr -d ' ' | tr '\n' ,)" "real,Yes.,"
touch "$T/rec/s2.mp4"
spx status >/dev/null; spx prep >/dev/null 2>&1 && bad "stream-post prep took a recording still being written"

# --- agent-sandbox (server half, against a fake docker) ---------------------
# It runs from the session dir ssh-sandbox ships it to, as on a server.
H=$T/ash; R=$H/.agent-sandbox
mkdir -p "$R" "$H/.ssh"
# ssh-sandbox ships a fresh copy each session; down deletes it.
ship() { mkdir -p "$R" && cp "$REPO/common/stow/sandbox/.local/bin/agent-sandbox" "$REPO/common/stow/sandbox/.local/share/agent-sandbox/agent-job" "$R/"; }
ship
AS=$R/agent-sandbox
D=$T/docker; mkdir -p "$D/bin"
# Fake docker: logs argv one per line; inspect answers from $D/{label,running}; rm drops it.
cat > "$D/bin/docker" <<'EOF'
#!/bin/sh
case "$1" in run) case "$*" in *" cat "*) ;; *) [ -f "$D/label" ] && { echo "name in use" >&2; exit 125; }; printf '%s\n' "$@" > "$D/last"; echo 1 > "$D/label"; echo true > "$D/running" ;; esac; exit 0 ;; esac
case "$1" in rm) rm -f "$D/label"; exit 0 ;; esac
case "$*" in exec*agent-job\ running) [ -f "$D/jobfail" ] && exit 1; cat "$D/jobs" 2>/dev/null; exit 0 ;; esac
printf '%s\n' "$@" > "$D/lastx"
[ "$1" = inspect ] || exit 0
[ -f "$D/label" ] || exit 1
case "$*" in *Labels*) cat "$D/label" ;; *Running*) cat "$D/running" ;; esac
EOF
chmod +x "$D/bin/docker"
ssh-keygen -q -t ed25519 -N '' -C t -f "$T/k"
AK=$H/.ssh/authorized_keys; echo "ssh-rsa AAAAother keep" > "$AK"
as() { env -i HOME="$H" USER=u D="$D" PATH="$D/bin:/usr/bin:/bin" "$AS" "$@"; }
up() { as up --image img@sha256:ab "$@" < "$T/k.pub"; }
up >/dev/null 2>&1 || bad "agent-sandbox up failed"
for f in --cap-drop ALL no-new-privileges:true --read-only --pids-limit u_agent zfiles.agent-sandbox=1 \
         AGENT_SANDBOX=1 AGENT_SANDBOX_IMAGE=img@sha256:ab --memory; do
    grep -qx -- "$f" "$D/last" || bad "agent-sandbox up lacks $f"
done
eq "agent-sandbox network is off by default" "$(grep -A1 -x -- --network "$D/last" | tail -1)" none
grep -qE -- '^--privileged|docker.sock|^seccomp=unconfined' "$D/last" && bad "agent-sandbox up loosened the sandbox"
grep -q '^/tmp:rw,exec,' "$D/last" || bad "agent-sandbox /tmp is noexec (Docker's tmpfs default): JITs and pytest run binaries from it"
grep -qx "$H/agent-sandbox/u_agent:/workspace:rw" "$D/last" || bad "agent-sandbox workspace mount wrong"
grep -qx "$R/tools:/opt/agent-sandbox:ro" "$D/last" || bad "agent-sandbox tools not mounted read-only"
[[ -x $R/tools/bin/rsync && -x $R/tools/bin/agent-job ]] || bad "agent-sandbox did not stage rsync and agent-job"
grep -q -- '--library-path /opt/agent-sandbox/lib' "$R/tools/bin/rsync" || bad "staged tools not bound by --library-path"
grep -rq LD_LIBRARY_PATH "$R/tools/bin" && bad "staged tools set LD_LIBRARY_PATH (tmux jobs would inherit it)"
grep -q "^$(id -un):x:$(id -u):" "$R/tools/passwd" || bad "agent-sandbox passwd lacks our uid"
[[ -f $R/audit.log ]] || bad "up did not create the audit log (down copies it even if no command ran)"
blob=$(cut -d' ' -f2 "$T/k.pub")
grep -q "^restrict,pty,expiry-time=\"[0-9]\{12\}\",command=\"$AS gate u_agent\" ssh-ed25519 $blob" "$AK" || bad "key line not restricted/expiring/forced: $(cat "$AK")"
grep -q AAAAother "$AK" || bad "agent-sandbox dropped another key"
up >/dev/null 2>&1; eq "re-up keeps one line for the key" "$(grep -c -- "$blob" "$AK")" 1
up --workspace "$T/elsewhere" >/dev/null 2>&1 && bad "re-up switched the workspace of a live session (down would delete the wrong one)"
up --from '100.64.0.1,fd7a:115c:a1e0::1' >/dev/null 2>&1 || bad "up refused tailnet --from addresses"
grep -q "^restrict,pty,from=\"100.64.0.1,fd7a:115c:a1e0::1\",expiry-time=" "$AK" || bad "--from not on the key line: $(cat "$AK")"
up --from '1.2.3.4" ,command="sh' >/dev/null 2>&1 && bad "up accepted a --from that injects key options"
up >/dev/null 2>&1; grep -q 'from=' "$AK" && bad "re-up without --from kept the old restriction"
up --name other >/dev/null 2>&1 && bad "up started a second session over a live one"
echo "command=\"/bin/sh\" $(cat "$T/k.pub")" > "$T/opt.pub"
as up --image i < "$T/opt.pub" >/dev/null 2>&1 && bad "up accepted a key carrying options"
mkdir -p "$H/data"; up --mount "$H/data:/data" >/dev/null 2>&1 || bad "agent-sandbox refused a plain data mount"
grep -qx "$H/data:/data:ro" "$D/last" || bad "agent-sandbox mount not read-only by default"
for m in "$H" "$T" / /etc "$H/.ssh" "$R" "$H/nonexistent"; do
    up --mount "$m:/x" >/dev/null 2>&1 && bad "agent-sandbox mounted $m"
done
up --privileged >/dev/null 2>&1 && bad "agent-sandbox accepted an unknown flag"
# gate: the name comes from the key line; down / foreign containers refuse; the command
# reaches the container as ONE argument.
gate() { env -i HOME="$H" USER=u D="$D" PATH="$D/bin:/usr/bin:/bin" SSH_ORIGINAL_COMMAND="$1" "$AS" gate u_agent; }
gate 'echo a; rm -rf ~' >/dev/null 2>&1
eq "gate argv" "$(sed -n '1p;3p;$p' "$D/lastx" | tr '\n' '|')" "exec|u_agent|echo a; rm -rf ~|"
eq "gate probe" "$(gate agent-sandbox-probe)" "agent-sandbox: gated u_agent"
eq "gate audits each request, quoted, on the host" "$(tail -1 "$R/audit.log" | cut -d' ' -f2-)" "echo\\ a\\;\\ rm\\ -rf\\ ~"
chmod 444 "$R/audit.log"; rm -f "$D/lastx"; gate id >/dev/null 2>&1
grep -qx exec "$D/lastx" 2>/dev/null && bad "gate ran a command it could not audit"
chmod 644 "$R/audit.log"
as gate >/dev/null 2>&1 && bad "gate ran without a name"
as gate 'x;y' >/dev/null 2>&1 && bad "gate accepted a hostile name"
echo 0 > "$D/label"; rm -f "$D/lastx"; gate id >/dev/null 2>&1
grep -qx exec "$D/lastx" 2>/dev/null && bad "gate exec'd into a foreign container"
up >/dev/null 2>&1 && bad "up replaced a foreign container"
echo 1 > "$D/label"
# down refuses to end running jobs, or jobs it cannot list, unless --force.
printf 'train\033]0;pwned\007\n' > "$D/jobs"
o=$(as down 2>&1) && bad "down removed a sandbox with a job running"
[[ $o == *$'\033'* ]] && bad "down echoed the container's escape sequences to the terminal"
up >/dev/null 2>&1 && bad "up recreated a sandbox with a job running"
rm "$D/jobs"; touch "$D/jobfail"
as down >/dev/null 2>&1 && bad "down removed a sandbox whose jobs it could not list"
rm "$D/jobfail"
# down: nothing left -- container, key line, workspace, session dir -- and other keys kept.
as down >/dev/null 2>&1 || bad "agent-sandbox down failed"
[[ -e $D/label ]] && bad "down left the container"
grep -q -- "$blob" "$AK" && bad "down left the key line"
grep -q AAAAother "$AK" || bad "down dropped another key"
[[ -e $H/agent-sandbox || -e $R ]] && bad "down left files: $(ls -a "$H")"
as down >/dev/null 2>&1 && bad "down succeeded with no session"
# A workspace the session made is deleted wherever it is; one that already existed never is.
mkdir -p "$T/scratch/had"; echo keep > "$T/scratch/had/f"
ship; o=$(up --workspace "$T/scratch/had" 2>&1 && as down 2>&1) || bad "session on an existing workspace failed: $o"
eq "down kept a workspace that existed before the session" "$(cat "$T/scratch/had/f" 2>/dev/null)" keep
ship; up --workspace "$T/scratch/new" >/dev/null 2>&1 && as down >/dev/null 2>&1 || bad "session on a new outside-home workspace failed"
[[ -e $T/scratch/new ]] && bad "down left a workspace the session created outside home"

# --- agent-job (real tmux, private socket dir) --------------------------------
if command -v tmux >/dev/null; then
AJ=$REPO/common/stow/sandbox/.local/share/agent-sandbox/agent-job
mkdir -p "$T/aj/tmux" "$T/aj/w"
aj() { (cd "$T/aj/w" && env -i HOME="$T/aj" PATH=/usr/bin:/bin TMUX_TMPDIR="$T/aj/tmux" "$AJ" "$@"); }
id=$(aj start --name ok -- 'echo "it'"'"'s $((1+1))"; echo err >&2; exit 3')
eq "agent-job start prints its id" "$id" ok
aj wait ok 2>/dev/null; eq "agent-job wait returns the job's exit code" "$?" 3
eq "agent-job status after exit" "$(aj status ok)" "exited 3"
eq "agent-job log keeps stdout and stderr" "$(aj logs ok | tr '\n' ' ')" "it's 2 err "
eq "agent-job runs from the caller's directory" "$(aj start --name pwd -- pwd >/dev/null; aj wait pwd 2>/dev/null; aj logs pwd)" "$T/aj/w"
aj start --name long -- 'sleep 30' >/dev/null
eq "agent-job running" "$(aj running)" long
aj start --name long -- true >/dev/null 2>&1 && bad "agent-job started a second job under a running id"
aj kill long >/dev/null; eq "agent-job status after kill" "$(aj status long)" killed
gen=$(aj start -- true); [[ $gen =~ ^j[0-9]{8}-[0-9]{6}-[0-9]+$ ]] || bad "agent-job generated id: $gen"
aj start --name '../x' -- true >/dev/null 2>&1 && bad "agent-job accepted a path as an id"
aj status nope >/dev/null 2>&1 && bad "agent-job status of an unknown job succeeded"
# A job whose tmux server vanished (the sandbox was recreated) reads 'lost', not running.
aj start --name gone -- 'sleep 30' >/dev/null; env TMUX_TMPDIR="$T/aj/tmux" tmux -L agent-jobs kill-server
eq "agent-job status of a job whose server died" "$(aj status gone)" lost
# As the host's docker exec calls it: no tmux on PATH, the staged one beside agent-job.
mkdir -p "$T/aj/stage" "$T/aj/nobin"; cp "$AJ" "$T/aj/stage/"; ln -sf "$(command -v tmux)" "$T/aj/stage/tmux"
for c in sh date cat mkdir rm pwd printf head basename dirname sleep tee mv touch tail; do ln -sf "$(command -v $c)" "$T/aj/nobin/$c"; done
ajs() { (cd "$T/aj/w" && env -i HOME="$T/aj" PATH="$T/aj/nobin" TMUX_TMPDIR="$T/aj/tmux" "$T/aj/stage/agent-job" "$@"); }
ajs start --name staged -- 'sleep 30' >/dev/null
eq "agent-job finds the staged tmux beside it" "$(ajs running)" staged
ajs kill staged >/dev/null
fi

# --- agent-jail (real bubblewrap, fake home) ----------------------------------
if command -v bwrap >/dev/null && bwrap --ro-bind / / true 2>/dev/null; then
AJL=$REPO/common/stow/sandbox/.local/bin/agent-jail
JH=$T/jail; mkdir -p "$JH/.ssh/agent" "$JH/.config/gh" "$JH/.config/gh-work" "$JH/.config/agent-jail" "$JH/notes"
for f in id_ed25519 agent_sandbox agent_sandbox.pub config known_hosts; do echo "secret-$f" > "$JH/.ssh/$f"; done
echo token > "$JH/.config/gh/hosts.yml"; echo token > "$JH/.config/gh-work/hosts.yml"; echo mine > "$JH/notes/private"; echo work > "$JH/notes/ok"
printf '%s\n' '# extra' "$JH/notes/private" > "$JH/.config/agent-jail/hide"
jl() { env -i HOME="$JH" PATH=/usr/bin:/bin SSH_AUTH_SOCK="$JH/.ssh/agent/socket" GH_TOKEN=t "$AJL" "$@"; }
eq "jail ~/.ssh keeps only the sandbox key and config" "$(jl ls "$JH/.ssh" | tr '\n' ' ')" "agent_sandbox agent_sandbox.pub config known_hosts "
eq "jail sandbox key readable" "$(jl cat "$JH/.ssh/agent_sandbox")" "secret-agent_sandbox"
jl cat "$JH/.ssh/id_ed25519" >/dev/null 2>&1 && bad "jail exposed the real key"
eq "jail empties token stores" "$(jl ls -A "$JH/.config/gh" "$JH/.config/gh-work" | grep -c hosts)" 0
eq "jail hides extra paths from its hide file" "$(jl cat "$JH/notes/private" 2>/dev/null)" ""
eq "jail leaves the rest of home alone" "$(jl cat "$JH/notes/ok")" work
eq "jail drops agent and token env" "$(jl sh -c 'echo "${SSH_AUTH_SOCK-}${GH_TOKEN-}"')" ""
eq "jail gives ssh drop-ins it accepts (root reads as nobody in the jail)" "$(jl find /etc/ssh/ssh_config.d -name '*.conf' \( ! -user "$(id -u)" -o -perm /022 \) 2>/dev/null)" ""
eq "jail passes the exit code" "$(jl sh -c 'exit 7'; echo $?)" 7
jl "$AJL" true >/dev/null 2>&1 && bad "jail nested inside itself"
# Nothing written under home may run later outside the jail; the project stays writable.
mkdir -p "$JH/proj" "$JH/.pi" "$JH/.rt"; git -C "$JH/proj" init -q; echo .pi > "$JH/.config/agent-jail/rw"; : > "$JH/.rt/bus"
jp() { (cd "$JH/proj" && env -i HOME="$JH" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$JH/.rt" DBUS_SESSION_BUS_ADDRESS="unix:path=$JH/.rt/bus" "$AJL" "$@"); }
eq "jail home is read-only" "$(jp sh -c '(: > "$HOME/.zshrc") 2>/dev/null && echo rw || echo ro')" ro
eq "jail project is writable" "$(jp sh -c ': > f && echo rw')" rw
eq "jail rw file makes agent state writable" "$(jp sh -c ': > "$HOME/.pi/s" && echo rw')" rw
eq "jail keeps .git/config read-only" "$(jp sh -c 'git config x.y z 2>/dev/null && echo rw || echo ro')" ro
eq "jail keeps .git/hooks read-only" "$(jp sh -c '(: > .git/hooks/pre-commit) 2>/dev/null && echo rw || echo ro')" ro
eq "jail hides the session runtime dir (D-Bus, systemd --user)" "$(jp sh -c 'ls -A "$XDG_RUNTIME_DIR"; echo "${DBUS_SESSION_BUS_ADDRESS-}"')" ""
outside=$(mktemp); jp test -e "$outside" && bad "jail shares /tmp (tmux and X11 sockets live there)"; rm -f "$outside"
(cd "$JH" && env -i HOME="$JH" PATH=/usr/bin:/bin "$AJL" true >/dev/null 2>&1) && bad "jail made the whole home writable"
fi

# --- ssh-sandbox (alias writing + the safety check, against a fake ssh -G) ----
SS=$REPO/common/stow/sandbox/.local/bin/ssh-sandbox
mkdir -p "$T/sshbin"
cat > "$T/sshbin/ssh" <<'EOF'
#!/bin/sh
[ "$1" = -G ] || { printf '%s\n' "$@" >> "$T_SSHLOG"; exit 0; }
case $2 in
  *-agent) awk -v a="$2" '$0=="Host "a{on=1;next} /^Host /{on=0} on&&NF{print tolower($1), $2}' "$CONF"; cat "$EXTRA" ;;
  *) printf 'hostname %s.example\nuser me\nport 22\n' "$2" ;;
esac
EOF
# Fake Tailscale: this laptop is 100.64.0.1; node5 is a peer, node1 is not.
cat > "$T/sshbin/tailscale" <<'EOF'
#!/bin/sh
case "$*" in "ip") printf '100.64.0.1\nfd7a:115c:a1e0::1\n' ;; "ip -4 node5.example" | "ip -4 100.64.0.5") echo 100.64.0.5 ;; *) exit 1 ;; esac
EOF
chmod +x "$T/sshbin/ssh" "$T/sshbin/tailscale"; : > "$T/extra"
ss() { env -i HOME="$T/ssh" PATH="$T/sshbin:/usr/bin:/bin" CONF="$T/ssh/c.conf" EXTRA="$T/extra" T_SSHLOG="$T/sshlog" \
    AGENT_SANDBOX_SSH_CONF="$T/ssh/c.conf" AGENT_SANDBOX_KEY="$T/ssh/k" "$SS" "$@"; }
ss config node1 >/dev/null 2>&1 && ss config node1 >/dev/null 2>&1 && ss config node2 >/dev/null 2>&1 || bad "ssh-sandbox config failed"
eq "ssh-sandbox config idempotent" "$(ss list | tr '\n' ' ')" "node1-agent node2-agent "
grep -q 'HostName node1.example' "$T/ssh/c.conf" || bad "ssh-sandbox config lost the hostname"
ss check node1-agent >/dev/null 2>&1 || bad "ssh-sandbox check rejected a clean alias"
echo "identityfile ~/.ssh/id_ed25519" > "$T/extra"
ss check node1-agent >/dev/null 2>&1 && bad "ssh-sandbox check passed an alias that also offers the real key"
echo "controlpath ~/.ssh/cm/%r@%h:%p" > "$T/extra"; sed -i '/ControlPath none/d' "$T/ssh/c.conf"
ss check node1-agent >/dev/null 2>&1 && bad "ssh-sandbox check passed a shared ControlPath"
ss config node1 >/dev/null 2>&1
echo "proxycommand nc %h %p" > "$T/extra"
ss check node1-agent >/dev/null 2>&1 && bad "ssh-sandbox check passed a ProxyCommand"
ss config 'x;rm' >/dev/null 2>&1 && bad "ssh-sandbox accepted a hostile host name"
ss config -oProxyCommand >/dev/null 2>&1 && bad "ssh-sandbox accepted a host name that is an ssh option"
ss config me@node3 >/dev/null 2>&1; grep -qx 'Host node3-agent' "$T/ssh/c.conf" || bad "user@host did not give the alias host-agent"
# Server-side commands go through sh -c whatever the login shell, args quoted for sh.
ss status node1 >/dev/null 2>&1
eq "server commands run via sh -c" "$(tail -1 "$T/sshlog" | cut -c1-7)" "sh -c '"
# Over Tailscale the alias dials the peer's tailnet address and up binds the key to ours.
: > "$T/extra"; ss up node5 --mount "/my data:/d" >/dev/null 2>&1
grep -q 'HostName 100.64.0.5' "$T/ssh/c.conf" || bad "ssh-sandbox alias for a tailnet peer not on its tailnet address"
mkdir -p "$T/rs/.agent-sandbox"; printf '#!/bin/sh\nprintf "%%s\\n" "$@"\n' > "$T/rs/.agent-sandbox/agent-sandbox"; chmod +x "$T/rs/.agent-sandbox/agent-sandbox"
args=$(grep -F "agent-sandbox '\\''up'" "$T/sshlog" | tail -1)
eq "up args reach the server intact, with the tailnet --from" "$(HOME="$T/rs" sh -c "$args" | tr '\n' '|')" "up|--from|100.64.0.1,fd7a:115c:a1e0::1|--mount|/my data:/d|"
: > "$T/sshlog"; ss up node1 >/dev/null 2>&1; grep -q -- --from "$T/sshlog" && bad "ssh-sandbox bound a non-tailnet session to tailnet addresses"
grep -q 'HostName node1.example' "$T/ssh/c.conf" || bad "ssh-sandbox moved a non-peer onto a tailnet address"
mkdir -p "$T/fetched"; echo mine > "$T/fetched/f"
o=$(ss down node1 --fetch "$T/fetched" 2>&1); grep -q "not empty" <<<"$o" || bad "ssh-sandbox fetched into a non-empty directory: $o"
ss down node1 >/dev/null 2>&1 && bad "ssh-sandbox down ran without --fetch or --discard (it deletes the workspace)"
mkdir -p "$T/ssh/.config/agent-sandbox"; echo "--image x" > "$T/ssh/.config/agent-sandbox/node1"; chmod 666 "$T/ssh/.config/agent-sandbox/node1"
o=$(ss up node1 2>&1); grep -q "not group/world writable" <<<"$o" || bad "ssh-sandbox read world-writable host defaults: $o"
o=$(ss up me@node1 2>&1); grep -q "not group/world writable" <<<"$o" || bad "user@host did not find the host's defaults: $o"

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
