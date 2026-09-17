#!/usr/bin/env sh

set -eu

REPO_URL="${ZFILES_REPO_URL:-https://github.com/zstreeter/zfiles.git}"
REPO_DIR="${ZFILES_DIR:-$HOME/.zfiles}"
BRANCH="${ZFILES_BRANCH:-main}"

SPARSE_DIRS="common/stow/shell common/stow/bash common/stow/yazi remote"

info() { printf '\033[1;34m>>>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!!\033[0m %s\n' "$1"; }
die()  { printf '\033[1;31mERR\033[0m %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git is required but not installed."

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
