#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

info() { echo -e "\033[1;34m>>>\033[0m $1"; }
warn() { echo -e "\033[1;33m!!!\033[0m $1"; }
error() { echo -e "\033[1;31mERR\033[0m $1" >&2; exit 1; }

# Machine facts → one TARGET directory. Each target dir owns everything
# specific to that machine type: setup.sh, pkglist, stow/ packages, assets.
#   omarchy/  — Arch + Omarchy desktop (Hyprland, keyd, themes, email)
#   wsl/      — WSL Ubuntu work laptop (apt + mise, Windows host side)
#   remote/   — a work server reached over ssh from a herdr pane. Bash prompt,
#               yazi and neovim only, all user-local — never sudo, never
#               rearrange $HOME.
#   (linux)   — anything else: common packages only, no target dir.
#
# REMOTE can't be sniffed (a server looks like any other Linux box), so it's
# explicit. remote/install.sh passes --remote after its sparse clone.
REMOTE=false
[[ "${ZFILES_TARGET:-}" == remote ]] && REMOTE=true
for arg in "$@"; do
    case "$arg" in
        --remote) REMOTE=true ;;
        *) echo "unknown argument: $arg" >&2; exit 2 ;;
    esac
done

OMARCHY=false
if ! $REMOTE && [[ -d "$HOME/.local/share/omarchy" || -d "$HOME/.config/omarchy" ]]; then
    OMARCHY=true
fi

WSL=false
! $REMOTE && grep -qi microsoft /proc/version 2>/dev/null && WSL=true

# ZFILES_SKIP_PKG=1 forces the "no package manager" branch. The package step is
# the only part that needs sudo and the only part that takes minutes; skipping
# it makes re-runs (fixing a config, re-stowing after an edit) cheap.
PKG=none
if $REMOTE || [[ -n "${ZFILES_SKIP_PKG:-}" ]]; then
    PKG=none
elif command -v pacman &>/dev/null; then
    PKG=pacman
elif command -v apt-get &>/dev/null; then
    PKG=apt
fi

TARGET=linux
$WSL && TARGET=wsl
$OMARCHY && TARGET=omarchy
$REMOTE && TARGET=remote

# Installs mise into ~/.local/bin if absent, then pins the given tools globally.
# Shared by the wsl target (noble ships neovim stale and yazi not at all), the
# remote target (no root, so mise is the *only* source of binaries there), and
# the core-CLI backfill below. Tools are pinned one at a time on purpose: one
# name missing from mise's registry shouldn't take the rest of the toolchain
# down with it.
install_mise_stack() {
    if ! command -v mise &>/dev/null && [[ ! -x "$HOME/.local/bin/mise" ]]; then
        info "Installing mise..."
        curl -fsSL https://mise.run | sh
    fi
    mkdir -p "$HOME/.local/bin"
    export PATH="$HOME/.local/bin:$PATH"

    local tool
    for tool in "$@"; do
        mise use -g "$tool" || warn "mise could not install '$tool' — install it manually."
    done
    eval "$(mise activate bash --shims)"
}

# Each <target>/setup.sh defines target_packages() and target_setup(), and may
# override PINENTRY (consumed by common/setup.sh for gpg-agent) or STOW_ONLY
# (a package whitelist — remote stows a subset of common).
PINENTRY=/usr/bin/pinentry-gtk
STOW_ONLY=()
target_packages() {
    warn "Plain Linux — no package step. Core CLI tools are backfilled via mise below."
}
target_setup() { :; }
[[ -f "$TARGET/setup.sh" ]] && source "$TARGET/setup.sh"

info "Target: $TARGET"

# 1. Target packages
target_packages

# 1b. Core CLI backfill.
#
# These aren't garnish: yazi's keymap binds z/Z to zoxide and its find/search to
# fd, rg and fzf, and the shared shell aliases assume eza and bat. Each target
# gets them a different way — pacman from omarchy/pkglist.txt, apt from
# wsl/pkglist.txt, remote from mise — and parallel lists is exactly how zoxide
# ended up in none of them. So the requirement is declared once here, and
# anything the package manager didn't deliver is backfilled from mise into
# ~/.local. Keys are the binary name, values the mise registry name.
declare -A CORE_CLI_TOOLS=(
    [fd]=fd [rg]=ripgrep [fzf]=fzf [zoxide]=zoxide
    [eza]=eza [bat]=bat [nvim]=neovim
)

export PATH="$HOME/.local/bin:$PATH"
missing_tools=()
for bin in "${!CORE_CLI_TOOLS[@]}"; do
    command -v "$bin" &>/dev/null || missing_tools+=("${CORE_CLI_TOOLS[$bin]}@latest")
done
if ((${#missing_tools[@]})); then
    warn "Missing core CLI tools — backfilling via mise: ${missing_tools[*]}"
    install_mise_stack "${missing_tools[@]}"
    still_missing=()
    for bin in "${!CORE_CLI_TOOLS[@]}"; do
        command -v "$bin" &>/dev/null || still_missing+=("$bin")
    done
    ((${#still_missing[@]})) \
        && warn "Still unavailable after mise: ${still_missing[*]} — yazi's z/Z and search bindings will not work." \
        || info "All core CLI tools present."
else
    info "All core CLI tools present."
fi

# 2. Stow dotfiles — packages are auto-discovered: every directory under
# common/stow/ plus <target>/stow/. `ls <dir>/stow` IS the package list; to add
# a package, drop a directory there. STOW_ONLY (set by remote/setup.sh)
# whitelists a subset.
info "Stowing dotfiles..."
command -v stow &>/dev/null || error "stow not installed — rerun the package step or install it manually."

# Never tree-fold. By default stow links the deepest directory it can — and
# most packages here have `.config/<name>/` as their only child, so they fold:
# `~/.config/foo` becomes a symlink to `repo/.../foo`, and anything written to
# ~/.config/foo/ afterwards lands *inside the repo*. That is where this repo's
# stray secrets.sh, .zcompdump, zsh-syntax-highlighting/ and vendored yazi
# plugins all came from. Blanket, not a list — an allowlist is one forgotten
# entry away from reintroducing the bug. The cost is that a *newly added* file
# in an existing package needs a re-stow to appear.
STOW_FLAGS=(--adopt --no-folding --target="$HOME")

# `stow --adopt` silently absorbs an existing real file into the repo, and the
# revert below then throws its contents away. That is how a machine's
# pre-zfiles ~/.bashrc would vanish. So: ask stow what it *would* refuse to
# overwrite (a plain simulation, no --adopt), and stash those aside first.
STOW_BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/backup/$(date +%Y%m%d%H%M%S)"

backup_stow_conflicts() {
    local stow_dir="$1" pkg="$2" rel conflicts
    # stow reports conflicts on stderr as:
    #   * existing target is neither a link nor a directory: .bashrc
    conflicts=$(stow -n -v -d "$stow_dir" --target="$HOME" "$pkg" 2>&1 \
        | sed -n 's/.*existing target is [^:]*: //p' || true)
    [[ -n "$conflicts" ]] || return 0

    while IFS= read -r rel; do
        [[ -n "$rel" && -e "$HOME/$rel" ]] || continue
        mkdir -p "$STOW_BACKUP_DIR/$(dirname "$rel")"
        cp -a "$HOME/$rel" "$STOW_BACKUP_DIR/$rel"
        warn "Backed up pre-existing ~/$rel → $STOW_BACKUP_DIR/$rel"
    done <<< "$conflicts"
}

stow_selected() {
    ((${#STOW_ONLY[@]} == 0)) && return 0
    [[ " ${STOW_ONLY[*]} " == *" $1 "* ]]
}

# Collect (stow dir, package) pairs and their repo-relative paths.
STOW_DIRS=(common/stow)
[[ -d "$TARGET/stow" ]] && STOW_DIRS+=("$TARGET/stow")

STOW_PKG_PATHS=()
for stow_dir in "${STOW_DIRS[@]}"; do
    for pkg_path in "$stow_dir"/*/; do
        pkg=$(basename "$pkg_path")
        stow_selected "$pkg" && STOW_PKG_PATHS+=("$stow_dir/$pkg")
    done
done

# Snapshot which package files were already dirty. `--adopt` rewrites a repo
# file with the contents of whatever it found in $HOME, so the run has to end
# with a revert — but a blanket revert also throws away uncommitted edits that
# were in flight before bootstrap started. Anything dirty going in stays dirty
# coming out; only what stow itself changed gets reverted.
readarray -t PRE_DIRTY < <(git diff --name-only -- "${STOW_PKG_PATHS[@]}" 2>/dev/null || true)

for pkg_path in "${STOW_PKG_PATHS[@]}"; do
    stow_dir=$(dirname "$pkg_path")
    pkg=$(basename "$pkg_path")
    backup_stow_conflicts "$stow_dir" "$pkg"
    # This links service files to ~/.config/systemd/user/ if structured correctly
    stow "${STOW_FLAGS[@]}" -d "$stow_dir" "$pkg"
done

readarray -t POST_DIRTY < <(git diff --name-only -- "${STOW_PKG_PATHS[@]}" 2>/dev/null || true)
ADOPTED=()
for f in "${POST_DIRTY[@]}"; do
    was_dirty=false
    for p in "${PRE_DIRTY[@]}"; do
        [[ "$p" == "$f" ]] && { was_dirty=true; break; }
    done
    $was_dirty || ADOPTED+=("$f")
done
if ((${#ADOPTED[@]})); then
    git checkout -- "${ADOPTED[@]}"
    info "Reverted ${#ADOPTED[@]} file(s) adopted by stow."
fi
if ((${#PRE_DIRTY[@]})); then
    warn "Left ${#PRE_DIRTY[@]} uncommitted change(s) in stowed packages alone: ${PRE_DIRTY[*]}"
fi

# 3. Shared setup (every target; remote-hostile steps guard themselves)
source common/setup.sh

# 4. Target-specific setup
target_setup

if ! $REMOTE; then
    SECRETS_FILE_DISPLAY="${XDG_CONFIG_HOME:-$HOME/.config}/shell/secrets.env"
    cat <<EOF

>>> AI providers — add your API keys to:
       $SECRETS_FILE_DISPLAY

     Uncomment and fill in the providers you actually use (ANTHROPIC_API_KEY,
     GEMINI_API_KEY, OPENAI_API_KEY, …). The file is sourced by both shells on
     start and is gitignored. Used by pi, opencode, claude code, etc.

>>> Research workflow — manual steps remaining:

  1. Zotero (one-time): install Better BibTeX if not already.
     Edit → Preferences → Better BibTeX → Citation keys: choose a key format.

  2. To start a new research project:
       new-research-project <name>     # creates ~/research/<name>/
     Then open that folder in Obsidian and install the community plugins
     listed in the vault's README.md.

  3. Per-vault: configure Better BibTeX → Automatic export → target the
     vault's references.bib (Format: Better BibLaTeX, On change).

EOF

    if $OMARCHY; then
        info "Done! Log out and back in for shell change, reboot for keyd."
    else
        info "Done! Log out and back in for shell change."
    fi
fi
