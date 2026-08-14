#!/usr/bin/env sh
# zfiles remote bootstrap — run this on a work server, from a herdr pane:
#
#   curl -fsSL https://raw.githubusercontent.com/zstreeter/zfiles/main/remote/install.sh | sh
#
# What it does: fetches only the parts of zfiles a bash ssh session actually
# wants (the shared shell config, the bash prompt, yazi) and hands off to
# bootstrap.sh --remote, which installs neovim/yazi/etc into ~/.local via mise.
#
# Deliberately NOT here: zsh, herdr, pi/opencode, mail, anything desktop. herdr
# runs on the local machine; the server is just what's inside one of its panes.
#
# Constraints this respects:
#   - never sudo, never a package manager: everything lands under $HOME
#   - never replaces ~/.bashrc: bootstrap appends a guarded block to it
#   - POSIX sh, because `curl | sh` shouldn't assume bash is the /bin/sh here

set -eu

REPO_URL="${ZFILES_REPO_URL:-https://github.com/zstreeter/zfiles.git}"
REPO_DIR="${ZFILES_DIR:-$HOME/.zfiles}"
BRANCH="${ZFILES_BRANCH:-main}"

# The stow packages a remote needs. Cone-mode sparse-checkout always includes
# top-level files too, so bootstrap.sh and .stow-local-ignore come along free.
SPARSE_DIRS="shell bash yazi remote"

info() { printf '\033[1;34m>>>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required but not installed."

# Sparse checkout needs git 2.25+ (`sparse-checkout` subcommand) and partial
# clone needs 2.19+. Older servers are common enough to be worth a fallback —
# a full clone of this repo is still only a few MB of text.
git_supports_sparse() {
    v=$(git --version | awk '{print $3}')
    major=${v%%.*}
    rest=${v#*.}
    minor=${rest%%.*}
    [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 25 ]; }
}

if [ -d "$REPO_DIR/.git" ]; then
    info "Updating existing checkout at $REPO_DIR..."
    git -C "$REPO_DIR" fetch --depth 1 origin "$BRANCH"
    git -C "$REPO_DIR" checkout -B "$BRANCH" "origin/$BRANCH"
elif git_supports_sparse; then
    info "Sparse-cloning zfiles into $REPO_DIR ($SPARSE_DIRS)..."
    git clone --filter=blob:none --no-checkout --depth 1 \
        --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
    git -C "$REPO_DIR" sparse-checkout init --cone
    # shellcheck disable=SC2086  # word splitting is the point here
    git -C "$REPO_DIR" sparse-checkout set $SPARSE_DIRS
    git -C "$REPO_DIR" checkout "$BRANCH"
else
    warn "git $(git --version | awk '{print $3}') is too old for sparse-checkout; full shallow clone instead."
    git clone --depth 1 --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
fi

[ -x "$REPO_DIR/bootstrap.sh" ] || chmod +x "$REPO_DIR/bootstrap.sh"

info "Handing off to bootstrap.sh --remote..."
exec "$REPO_DIR/bootstrap.sh" --remote
