#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

info() { echo -e "\033[1;34m>>>\033[0m $1"; }
warn() { echo -e "\033[1;33m!!!\033[0m $1"; }
error() { echo -e "\033[1;31mERR\033[0m $1" >&2; exit 1; }

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


TARGET=linux
$WSL && TARGET=wsl
$OMARCHY && TARGET=omarchy
$REMOTE && TARGET=remote

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

export PINENTRY=/usr/bin/pinentry-gtk
STOW_ONLY=()
target_packages() {
    warn "Plain Linux — no package step. Core CLI tools are backfilled via mise below."
}
target_setup() { :; }
# shellcheck source=/dev/null
[[ -f "$TARGET/setup.sh" ]] && source "$TARGET/setup.sh"

info "Target: $TARGET"

if [[ -n "${ZFILES_SKIP_PKG:-}" ]]; then
    info "Skipping package installation (ZFILES_SKIP_PKG is set)."
else
    target_packages
fi

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

# A root-less box (an HPC login node) may have no stow, and mise doesn't package it. GNU stow
# is a Perl program: build a pinned, checksummed release into ~/.local -- perl + make is all
# it needs. The sha256 matches Arch's PKGBUILD for 2.4.1.
install_stow_from_source() {
    local v=2.4.1 sha=2a671e75fc207303bfe86a9a7223169c7669df0a8108ebdf1a7fe8cd2b88780b
    local tmp mirror
    command -v perl &>/dev/null && command -v make &>/dev/null || return 1
    tmp=$(mktemp -d) || return 1
    for mirror in https://ftpmirror.gnu.org/gnu https://mirrors.kernel.org/gnu https://ftp.gnu.org/gnu; do
        curl -fsSL --connect-timeout 15 --max-time 120 -o "$tmp/stow.tgz" "$mirror/stow/stow-$v.tar.gz" && break
    done
    if echo "$sha  $tmp/stow.tgz" | sha256sum -c --quiet - 2>/dev/null \
        && tar -xzf "$tmp/stow.tgz" -C "$tmp" \
        && (cd "$tmp/stow-$v" && ./configure --prefix="$HOME/.local" && make install) \
            >"$tmp/build.log" 2>&1; then
        rm -rf "$tmp"
        return 0
    fi
    warn "stow download, checksum or build failed (no mirror reachable, or sha256 mismatch); see $tmp"
    return 1
}

info "Stowing dotfiles..."
if ! command -v stow &>/dev/null; then
    info "stow not found — building GNU stow into ~/.local (perl + make, no root)..."
    install_stow_from_source \
        || error "stow not installed and could not be built — install GNU stow manually."
    export PATH="$HOME/.local/bin:$PATH"
fi

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

git config core.hooksPath common/githooks

# The identifiers that hook refuses to publish. Never tracked -- a committed
# list of what you are hiding is itself the disclosure -- so it cannot arrive by
# clone. Seed it here; the hook blocks pushes until the sentinel line is gone,
# because a file that exists and matches nothing is a guard that only looks set
# up. Same deal as secrets.env: the real copy lives in the password manager.
LEAK_PATTERNS="${XDG_CONFIG_HOME:-$HOME/.config}/zfiles/leak-patterns"
if [[ ! -f "$LEAK_PATTERNS" ]]; then
    mkdir -p "$(dirname "$LEAK_PATTERNS")"
    cat > "$LEAK_PATTERNS" << 'PATTERNS'
# Strings this machine must never publish. One extended regex per line; blank
# lines and # comments are ignored. common/githooks/pre-push matches them
# against every line your next push would add.
#
# Not for credentials: GitHub secret scanning and push protection catch those
# server-side, where --no-verify cannot reach. This is for what GitHub cannot
# know -- an employer's name, internal hostnames, unreleased hardware.
#
# Paste the real list from the password manager. Examples, delete them:
#   \bexamplecorp\b
#   \.internal\.examplecorp\.com
#   \bPROJECT-[0-9]{4}\b
#
# Then delete the line below. Until it goes, every push is refused.
UNCONFIGURED
PATTERNS
    chmod 600 "$LEAK_PATTERNS"
    warn "Seeded $LEAK_PATTERNS — fill it in before pushing"
fi

# 3. Shared setup (every target; remote-hostile steps guard themselves)
# shellcheck source=common/setup.sh
source common/setup.sh

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
