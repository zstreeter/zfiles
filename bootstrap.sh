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

# The package step is the slow, privileged part. ZFILES_SKIP_PKG=1 leaves the
# overlay and setup reconciliation active while skipping package installation.

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
export PINENTRY=/usr/bin/pinentry-gtk
STOW_ONLY=()
target_packages() {
    warn "Plain Linux — no package step. Core CLI tools are backfilled via mise below."
}
target_setup() { :; }
# shellcheck source=/dev/null
[[ -f "$TARGET/setup.sh" ]] && source "$TARGET/setup.sh"

info "Target: $TARGET"

# 1. Target packages
if [[ -n "${ZFILES_SKIP_PKG:-}" ]]; then
    info "Skipping package installation (ZFILES_SKIP_PKG is set)."
else
    target_packages
fi

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
    if ((${#still_missing[@]})); then
        warn "Still unavailable after mise: ${still_missing[*]} — yazi's z/Z and search bindings will not work."
    else
        info "All core CLI tools present."
    fi
else
    info "All core CLI tools present."
fi

# 2. Stow dotfiles — packages are auto-discovered: every directory under
# common/stow/ plus <target>/stow/. `ls <dir>/stow` IS the package list; to add
# a package, drop a directory there. STOW_ONLY (set by remote/setup.sh)
# whitelists a subset.
info "Stowing dotfiles..."
command -v stow &>/dev/null || error "stow not installed — rerun the package step or install it manually."

# Never tree-fold or adopt. Folding lets runtime files land in the repository;
# adoption lets pre-existing machine config overwrite tracked source files.
STOW_FLAGS=(--no-folding --target="$HOME")
STOW_BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/backup/$(date +%Y%m%d%H%M%S).$$"
BACKED_UP=()
RETIRED=()
declare -A PRESENT_STOW_TARGETS=()

backup_stow_conflicts() {
    local stow_dir="$1" pkg="$2" rel conflicts
    conflicts=$(stow -n -v -d "$stow_dir" --target="$HOME" "$pkg" 2>&1 \
        | sed -n 's/.*existing target is [^:]*: //p' || true)
    [[ -n "$conflicts" ]] || return 0

    while IFS= read -r rel; do
        [[ -n "$rel" && ( -e "$HOME/$rel" || -L "$HOME/$rel" ) ]] || continue
        mkdir -p "$STOW_BACKUP_DIR/$(dirname "$rel")"
        mv "$HOME/$rel" "$STOW_BACKUP_DIR/$rel"
        BACKED_UP+=("$rel")
        warn "Backed up pre-existing ~/$rel → $STOW_BACKUP_DIR/$rel"
    done <<< "$conflicts"
}

restore_stow_state() {
    local rel

    for rel in "${!CURRENT_STOW_TARGETS[@]}"; do
        [[ ${PRESENT_STOW_TARGETS[$rel]+present} ]] && continue
        target="$HOME/$rel"
        if [[ -L "$target" && "$(readlink -m "$target")" == "$REPO_DIR/"* ]]; then
            rm "$target"
        fi
    done

    for rel in "${BACKED_UP[@]}"; do
        [[ -e "$STOW_BACKUP_DIR/$rel" || -L "$STOW_BACKUP_DIR/$rel" ]] || continue
        rm -f "$HOME/$rel"
        mkdir -p "$HOME/$(dirname "$rel")"
        mv "$STOW_BACKUP_DIR/$rel" "$HOME/$rel"
    done

    for rel in "${RETIRED[@]}"; do
        [[ -L "$STOW_BACKUP_DIR/retired/$rel" ]] || continue
        mkdir -p "$HOME/$(dirname "$rel")"
        mv "$STOW_BACKUP_DIR/retired/$rel" "$HOME/$rel"
    done
    warn "Stow failed; restored the previous target state."
}

stow_selected() {
    ((${#STOW_ONLY[@]} == 0)) && return 0
    [[ " ${STOW_ONLY[*]} " == *" $1 "* ]]
}

# Collect packages and the target paths they currently own.
STOW_DIRS=(common/stow)
[[ -d "$TARGET/stow" ]] && STOW_DIRS+=("$TARGET/stow")
STOW_PKG_PATHS=()
declare -A CURRENT_STOW_TARGETS=()
for stow_dir in "${STOW_DIRS[@]}"; do
    for pkg_path in "$stow_dir"/*/; do
        pkg=$(basename "$pkg_path")
        if stow_selected "$pkg"; then
            STOW_PKG_PATHS+=("$stow_dir/$pkg")
            while IFS= read -r source; do
                CURRENT_STOW_TARGETS["${source#"$pkg_path"}"]=1
            done < <(find "$pkg_path" \( -type f -o -type l \) -print)
        fi
    done
done

for rel in "${!CURRENT_STOW_TARGETS[@]}"; do
    [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] && PRESENT_STOW_TARGETS["$rel"]=1
done

# A manifest gives deletion the inverse of auto-discovery: remove only retired
# targets that are still links into this repository.
STOW_MANIFEST="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/stow-targets"
if [[ -f "$STOW_MANIFEST" ]]; then
    trap restore_stow_state ERR
    while IFS= read -r rel; do
        [[ -n "$rel" ]] || continue
        [[ -n "$rel" && ! ${CURRENT_STOW_TARGETS[$rel]+present} ]] || continue
        target="$HOME/$rel"
        if [[ -L "$target" && "$(readlink -m "$target")" == "$REPO_DIR/"* ]]; then
            mkdir -p "$STOW_BACKUP_DIR/retired/$(dirname "$rel")"
            mv "$target" "$STOW_BACKUP_DIR/retired/$rel"
            RETIRED+=("$rel")
            info "Removed retired stow target ~/$rel"
        fi
    done < "$STOW_MANIFEST"
fi

trap restore_stow_state ERR
for pkg_path in "${STOW_PKG_PATHS[@]}"; do
    stow_dir=$(dirname "$pkg_path")
    pkg=$(basename "$pkg_path")
    backup_stow_conflicts "$stow_dir" "$pkg"
    stow "${STOW_FLAGS[@]}" -d "$stow_dir" "$pkg"
done
trap - ERR
rm -rf "$STOW_BACKUP_DIR/retired"

mkdir -p "$(dirname "$STOW_MANIFEST")"
printf '%s\n' "${!CURRENT_STOW_TARGETS[@]}" | sort > "$STOW_MANIFEST.tmp"
mv "$STOW_MANIFEST.tmp" "$STOW_MANIFEST"

# 3. Shared setup (every target; remote-hostile steps guard themselves)
# shellcheck source=common/setup.sh
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
