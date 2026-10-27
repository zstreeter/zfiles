#!/usr/bin/env bash
# e2e.sh — install zfiles for real in a clean container, then check the result.
#
#   tests/e2e.sh [remote|linux]...   default: both; needs docker and the network
#
# remote runs the curl-able installer against what is pushed to GitHub (as a
# server would); linux runs bootstrap.sh from this working tree. Each target is
# installed twice: the second run is the update path and must change nothing.
# Omarchy and WSL cannot run in a container -- test those on the real machine.
set -euo pipefail
cd "$(dirname "$0")/.."

TOOLS="nvim yazi ya rg fd fzf zoxide bat eza jq stow paperctl measure elan lean-sandbox"

run() {
    local target=$1 cmd
    case $target in
        remote) cmd='sh /zfiles/remote/install.sh' ;;
        # The tracked files as they are in this working tree, uncommitted edits included.
        linux)  cmd='[ -d ~/zfiles ] || { mkdir ~/zfiles && tar -xzf /tree.tgz -C ~/zfiles && git -C ~/zfiles init -q; }; SHELL=/usr/bin/zsh ZFILES_TARGET=linux ~/zfiles/bootstrap.sh'
                TOOLS+=" zsh herdr" ;;
        *) echo "unknown target: $target" >&2; return 2 ;;
    esac
    echo ">>> e2e: $target"
    docker run --rm -v "$PWD:/zfiles:ro" -v "$TREE:/tree.tgz:ro" -e CMD="$cmd" -e TOOLS="$TOOLS" ubuntu:24.04 bash -c '
        set -u
        apt-get update -qq >/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
            git curl ca-certificates perl make gawk python3 jq unzip xz-utils zsh gnupg sudo >/dev/null
        useradd -m -s /bin/bash u && echo "u ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/u
        as_u() { su - u -c "$1"; }
        fail=0
        for pass in install update; do
            as_u "$CMD" > /tmp/$pass.log 2>&1 || { echo "FAIL: $pass exited $?"; tail -20 /tmp/$pass.log; exit 1; }
            grep -E "ERR|Backed up|Removed retired" /tmp/$pass.log && { [ $pass = update ] && fail=1; }
        done
        broken=$(find /home/u -xtype l -not -path "*/.cache/*" | head)
        [ -z "$broken" ] || { echo "FAIL: broken links: $broken"; fail=1; }
        missing=$(as_u "bash -lic '\''for t in $TOOLS; do command -v \$t >/dev/null || printf \"%s \" \$t; done'\''" 2>/dev/null)
        [ -z "$missing" ] || { echo "FAIL: not on PATH after login: $missing"; fail=1; }
        as_u "bash -lic \"nvim --headless +q\"" >/dev/null 2>&1 || { echo "FAIL: nvim does not start"; fail=1; }
        exit $fail
    ' && echo ">>> e2e: $target ok"
}

TREE=$(mktemp --suffix=.tgz)
trap 'rm -f "$TREE"' EXIT
git ls-files -z | tar --null -T - -czf "$TREE"
chmod 644 "$TREE"

status=0
for t in "${@:-remote linux}"; do
    for target in $t; do run "$target" || status=1; done
done
exit $status
