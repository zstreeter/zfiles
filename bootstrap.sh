#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Orthogonal machine facts — each step gates on the fact it cares about.
# OMARCHY: full desktop overlay (Hyprland source, theme hooks, keyd, services).
# WSL: Windows work laptop; keyboard/WM/terminal live on the Windows side.
# REMOTE: a work server reached over ssh from a herdr pane. Bash prompt, yazi
#         and neovim only, all user-local — never sudo, never rearrange $HOME.
# PKG: which package manager drives step 1.

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

# ZFILES_SKIP_PKG=1 forces the "no package manager" branch. Step 1 is the only
# part of this script that needs sudo and the only part that takes minutes;
# skipping it makes re-runs (fixing a config, re-stowing after an edit) cheap.
PKG=none
if $REMOTE || [[ -n "${ZFILES_SKIP_PKG:-}" ]]; then
    # No root on work servers. Everything comes from mise into ~/.local.
    PKG=none
elif command -v pacman &>/dev/null; then
    PKG=pacman
elif command -v apt-get &>/dev/null; then
    PKG=apt
fi

# True core — anything that makes sense in a bare terminal on any Linux.
# `shell` holds the shell-agnostic env/aliases/commands/git-prompt that zsh and
# bash both source out of ~/.config/shell.
CORE_PACKAGES=(shell zsh bash yazi scripts opencode pi herdr)
# Omarchy/desktop-specific packages — only stowed when OMARCHY=true.
# `omarchy` ships user template overrides at ~/.config/omarchy/themed/ that
# Omarchy's template engine renders on every theme switch. cura/sioyek/xdg/
# wireplumber are desktop- or hardware-bound, so they ride with Omarchy too.
OMARCHY_PACKAGES=(hypr himalaya mirador omarchy cura sioyek xdg wireplumber)
# WSL-specific packages (wezterm, windows-side configs) land here as the
# Windows keybinding/terminal design settles.
WSL_PACKAGES=()
# Remote servers get exactly the three things worth having in an ssh pane:
# the bash prompt (shell+bash), yazi, and neovim (cloned in step 6, not stowed).
# No zsh — those are bash terminals — and nothing desktop-, agent- or mail-bound.
REMOTE_PACKAGES=(shell bash yazi)

if $REMOTE; then
    STOW_PACKAGES=("${REMOTE_PACKAGES[@]}")
else
    STOW_PACKAGES=("${CORE_PACKAGES[@]}")
    if $OMARCHY; then
        STOW_PACKAGES+=("${OMARCHY_PACKAGES[@]}")
    fi
    if $WSL && ((${#WSL_PACKAGES[@]})); then
        STOW_PACKAGES+=("${WSL_PACKAGES[@]}")
    fi
fi

info() { echo -e "\033[1;34m>>>\033[0m $1"; }
warn() { echo -e "\033[1;33m!!!\033[0m $1"; }
error() { echo -e "\033[1;31mERR\033[0m $1" >&2; exit 1; }

if $REMOTE; then
    info "Remote target — bash prompt, yazi and neovim, user-local only."
elif $OMARCHY; then
    info "Omarchy detected — installing full overlay."
elif $WSL; then
    info "WSL detected — installing core packages for the work laptop."
else
    info "No Omarchy detected — installing core packages only."
fi

# Installs mise into ~/.local/bin if absent, then pins the given tools globally.
# Shared by the apt branch (noble ships neovim stale and yazi not at all) and by
# the remote target (no root, so mise is the *only* source of binaries there).
# Tools are pinned one at a time on purpose: one name missing from mise's
# registry shouldn't take the rest of the toolchain down with it.
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

# 1. Install packages
if $REMOTE; then
    # No sudo, no package manager — mise is the only source of binaries here.
    # Just the two headline tools; step 1b backfills the CLI set on every target.
    info "Installing user-local toolchain via mise (no root)..."
    install_mise_stack neovim@latest yazi@latest
elif [[ $PKG == pacman ]]; then
    info "Installing packages (pacman)..."
    AUR_HELPER=$(command -v paru || command -v yay || true)
    if [[ -z "$AUR_HELPER" ]]; then
        warn "No AUR helper found. Installing paru..."
        sudo pacman -S --needed --noconfirm base-devel git
        tmpdir=$(mktemp -d)
        git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
        (cd "$tmpdir/paru" && makepkg -si --noconfirm)
        rm -rf "$tmpdir"
        AUR_HELPER="paru"
    fi

    # Install essential base tools explicitly to ensure they exist
    # (pinentry is needed for the GPG config step below)
    # (xdg-utils is needed for xdg-mime)
    sudo pacman -S --needed --noconfirm pinentry stow xdg-utils

    # Strip comments and blank lines from pkglist.txt
    grep -v '^#' pkglist.txt | grep -v '^$' | $AUR_HELPER -S --needed --noconfirm -
elif [[ $PKG == apt ]]; then
    # Ubuntu path (WSL work laptop). apt covers the stable system tools
    # (pkglist-ubuntu.txt); mise covers everything noble ships stale or not
    # at all — see the mapping research on zfiles issue #7.
    info "Installing packages (apt)..."
    sudo apt-get update
    grep -v '^#' pkglist-ubuntu.txt | grep -v '^$' | xargs sudo apt-get install -y

    # Debian renames: expose the upstream binary names
    mkdir -p "$HOME/.local/bin"
    command -v fdfind &>/dev/null && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    command -v batcat &>/dev/null && ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"

    # mise-first TUI stack (apt neovim is stale, yazi absent from noble)
    install_mise_stack go@latest rust@latest bun@latest node@lts \
                       neovim@latest yazi@latest opencode@latest

    command -v jupyter-lab &>/dev/null || pipx install jupyterlab
    command -v rga &>/dev/null || cargo install ripgrep_all

    if ! command -v quarto &>/dev/null; then
        info "Installing quarto from official .deb..."
        QUARTO_DEB=$(curl -fsSL https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest \
            | grep -o 'https://[^"]*linux-amd64\.deb' | head -1)
        if [[ -n "$QUARTO_DEB" ]]; then
            tmpdeb=$(mktemp --suffix=.deb)
            curl -fsSL -o "$tmpdeb" "$QUARTO_DEB"
            sudo dpkg -i "$tmpdeb"
            rm -f "$tmpdeb"
        else
            warn "Could not resolve quarto .deb URL; install manually."
        fi
    fi
else
    warn "No supported package manager (pacman/apt) — skipping package install."
fi

# 1b. Load-bearing CLI tools, and the backstop that guarantees them.
#
# These aren't garnish: yazi's keymap binds z/Z to zoxide and its find/search to
# fd, rg and fzf, and the shared shell aliases assume eza and bat. Each target
# gets them a different way — pacman from pkglist.txt, apt from
# pkglist-ubuntu.txt, remote from mise — and three parallel lists is exactly how
# zoxide ended up in none of them. So the requirement is declared once here, and
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

# 2. Default applications are declarative — defined in xdg/.config/mimeapps.list
# (stowed in step 9). Entries that point at uninstalled .desktop files
# silently no-op, so it's safe to ship the full list cross-platform.

# 3. Configure keyd (omarchy-only — on WSL the keyboard is remapped on the
# Windows side by kanata, and plain servers don't want the Caps/Super overload)
if $OMARCHY; then
    info "Configuring keyd (Caps → Esc/Super)..."
    sudo mkdir -p /etc/keyd
    sudo cp root_etc/keyd/default.conf /etc/keyd/default.conf
    sudo systemctl enable --now keyd
fi

# 4. Configure GPG Agent (Pinentry GTK) — skipped on remote: a work server's
# gpg setup is the server's business, and relocating GNUPGHOME under someone
# else's machine is exactly the kind of surprise this target avoids.
# shell/env.sh sets GNUPGHOME=$XDG_DATA_HOME/gnupg. Bootstrap may run under bash
# without that loaded, so derive the target path the same way.
if ! $REMOTE; then
    info "Configuring GPG Agent..."
    GNUPGHOME_TARGET="${GNUPGHOME:-${XDG_DATA_HOME:-$HOME/.local/share}/gnupg}"

    # Relocate legacy ~/.gnupg once. Stop the running agent first so it doesn't
    # hold open file handles in the source tree mid-move.
    if [[ -d "$HOME/.gnupg" && ! -e "$GNUPGHOME_TARGET" ]]; then
        info "Relocating $HOME/.gnupg → $GNUPGHOME_TARGET"
        gpgconf --kill gpg-agent 2>/dev/null || true
        mkdir -p "$(dirname "$GNUPGHOME_TARGET")"
        mv "$HOME/.gnupg" "$GNUPGHOME_TARGET"
    fi

    mkdir -p "$GNUPGHOME_TARGET"
    chmod 700 "$GNUPGHOME_TARGET"

    # Ensure the right pinentry is set (idempotent): GUI on Omarchy, curses on
    # WSL/headless so pass and signed commits still work in a bare terminal.
    PINENTRY="/usr/bin/pinentry-gtk"
    $WSL && PINENTRY="/usr/bin/pinentry-curses"
    if ! grep -q "pinentry-program $PINENTRY" "$GNUPGHOME_TARGET/gpg-agent.conf" 2>/dev/null; then
        echo "pinentry-program $PINENTRY" >> "$GNUPGHOME_TARGET/gpg-agent.conf"
        echo "    Added $(basename "$PINENTRY") to gpg-agent.conf"
    fi

    # Reload agent (auto-starts under the new GNUPGHOME) to apply changes
    GNUPGHOME="$GNUPGHOME_TARGET" gpg-connect-agent reloadagent /bye || true
fi

# 5. Configure zsh with XDG and Zap — skipped on remote, which is bash-only
# (that's why the shared config lives in `shell`, not `zsh`). No chsh on a
# machine whose login shell isn't ours to change.
if ! $REMOTE; then
info "Configuring zsh..."

cat > "$HOME/.zshenv" << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
EOF

# Secrets live beside the rest of the shared shell config now. Migrate the
# pre-`shell`-package location once; xdg_relocate (§8d) runs later, so do it
# here where the file is about to be read.
SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/shell/secrets.env"
SECRETS_LEGACY="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/secrets.env"
if [[ -f "$SECRETS_LEGACY" && ! -f "$SECRETS_FILE" ]]; then
    info "Relocating $SECRETS_LEGACY → $SECRETS_FILE"
    mkdir -p "$(dirname "$SECRETS_FILE")"
    mv "$SECRETS_LEGACY" "$SECRETS_FILE"
fi
if [[ ! -f "$SECRETS_FILE" ]]; then
    mkdir -p "$(dirname "$SECRETS_FILE")"
    cat > "$SECRETS_FILE" << 'SECRETS'
# API keys — fill these in, this file is never tracked by git.
# Sourced by shell/.config/shell/env.sh on every shell start.
# Uncomment and set the providers you actually use.

# --- AI providers (used by pi, opencode, claude code, etc.) ---
# export ANTHROPIC_API_KEY=""
# export OPENAI_API_KEY=""
# export GEMINI_API_KEY=""
# export GOOGLE_API_KEY=""
# export OPENROUTER_API_KEY=""
# export DEEPSEEK_API_KEY=""
# export GROQ_API_KEY=""
# export CEREBRAS_API_KEY=""
# export XAI_API_KEY=""
# export MISTRAL_API_KEY=""
# export FIREWORKS_API_KEY=""
# export KIMI_API_KEY=""
# export OPENCODE_API_KEY=""
# export AI_GATEWAY_API_KEY=""

# --- Source-control / registry tokens ---
# export GITHUB_TOKEN=""
SECRETS
    chmod 600 "$SECRETS_FILE"
    info "Created $SECRETS_FILE — add your API keys there."
else
    info "Secrets file already exists at $SECRETS_FILE"
fi

ZAP_DIR="$HOME/.local/share/zap"
if [[ -d "$ZAP_DIR" ]]; then
    info "Zap is already installed."
else
    info "Installing Zap zsh plugin manager..."
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) \
        --branch release-v1 \
        --keep
fi

if [[ "$SHELL" != */zsh ]]; then
    info "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)"
fi
fi  # ! $REMOTE

# 5c. Hook bash into the zfiles config. Deliberately an *append* to whatever
# ~/.bashrc already exists rather than a stowed file: on a work server that
# file carries site setup (lmod, `module`, conda init) we must not clobber, and
# on this side it means `stow --adopt` can never swallow the machine's bashrc.
# Same pattern as the generated ~/.zshenv above. Idempotent via the marker.
ensure_bash_hook() {
    local target="$1" body="$2"
    if [[ -f "$target" ]] && grep -qF '# >>> zfiles >>>' "$target"; then
        info "bash hook already present in $target"
        return
    fi
    # Keep a copy of a pre-existing file before touching it — same safety net
    # the stow step applies, and the reason it lives outside the stow tree.
    if [[ -s "$target" ]]; then
        local backup="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/backup"
        mkdir -p "$backup"
        cp -a "$target" "$backup/$(basename "$target").$(date +%Y%m%d%H%M%S)"
    fi
    printf '\n# >>> zfiles >>>\n%s\n# <<< zfiles <<<\n' "$body" >> "$target"
    info "Appended zfiles hook to $target"
}

# A bash *login* shell — which is what ssh hands you — reads the first of
# .bash_profile / .bash_login / .profile that exists, and never .bashrc. Most
# distros' stock .profile already bridges to .bashrc, so only intervene when
# nothing in the chain does. Creating a .bash_profile unconditionally would
# shadow an existing ~/.profile and silently drop whatever it sets up.
ensure_login_chain() {
    local f first=""
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [[ -f "$f" ]] && { first="$f"; break; }
    done

    if [[ -z "$first" ]]; then
        ensure_bash_hook "$HOME/.bash_profile" \
            '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
        return
    fi

    if grep -q '\.bashrc' "$first"; then
        info "Login shells already reach ~/.bashrc via ${first/#$HOME/\~}"
        return
    fi

    # $BASH_VERSION guard: ~/.profile is also read by /bin/sh, which would
    # choke on bashrc's shopt/bind/[[ ]].
    ensure_bash_hook "$first" \
        '[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
}

info "Hooking bash into zfiles config..."
ensure_bash_hook "$HOME/.bashrc" \
    '[ -f "$HOME/.config/bash/rc.sh" ] && . "$HOME/.config/bash/rc.sh"'
ensure_login_chain

# 5b. ble.sh — bash syntax highlighting/autosuggestions/autopair, giving the
# bash config (bash/.config/bash/rc.sh) parity with the zsh plugins. On remote
# this *is* the line editor, since bash is the only shell there.
BLESH_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/blesh"
if [[ -f "$BLESH_DIR/ble.sh" ]]; then
    info "ble.sh already installed."
elif command -v make &>/dev/null && command -v gawk &>/dev/null; then
    info "Installing ble.sh (bash line editor)..."
    tmpdir=$(mktemp -d)
    git clone --recursive --depth 1 --shallow-submodules \
        https://github.com/akinomyoga/ble.sh.git "$tmpdir/ble.sh"
    make -C "$tmpdir/ble.sh" install PREFIX="$HOME/.local"
    rm -rf "$tmpdir"
else
    warn "make/gawk not found — skipping ble.sh (bash highlighting)."
fi

# 6. Clone neovim config (SMART INSTALL). Runs on every target including
# remote — neovim is one of the three things a work server is supposed to get.
info "Setting up neovim config..."
NVIM_DIR="$HOME/.config/nvim"
NVIM_REPO_URL="https://github.com/zstreeter/nvim.git"

install_my_nvim() {
    git clone "$NVIM_REPO_URL" "$NVIM_DIR"
}

# Displace a foreign config to a timestamped backup rather than deleting it.
# The plugin state in ~/.local/share/nvim belongs to that config, so it moves
# with it — on a work server someone else's nvim data is not ours to delete.
displace_nvim() {
    local stamp; stamp=$(date +%Y%m%d%H%M%S)
    warn "Backing up existing neovim config → ~/.config/nvim.bak.$stamp"
    mv "$NVIM_DIR" "$HOME/.config/nvim.bak.$stamp"
    if [[ -d "$HOME/.local/share/nvim" ]]; then
        mv "$HOME/.local/share/nvim" "$HOME/.local/share/nvim.bak.$stamp"
    fi
    install_my_nvim
}

if [[ -d "$NVIM_DIR" ]]; then
    if [[ -d "$NVIM_DIR/.git" ]]; then
        NVIM_ORIGIN=$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)
        if [[ "$NVIM_ORIGIN" == *zstreeter/nvim* ]]; then
            info "Correct Neovim config found, pulling latest..."
            git -C "$NVIM_DIR" pull --ff-only || warn "nvim pull failed (local changes?) — left as-is."
        else
            warn "Unknown Neovim git repo found ($NVIM_ORIGIN)."
            displace_nvim
        fi
    else
        warn "Non-git Neovim config found."
        displace_nvim
    fi
else
    install_my_nvim
fi

# Symlink Omarchy theme to neovim plugins
OMARCHY_THEME="$HOME/.config/omarchy/current/theme/neovim.lua"
NVIM_THEME_LINK="$NVIM_DIR/lua/plugins/omarchy-theme.lua"

if [[ -f "$OMARCHY_THEME" ]]; then
    mkdir -p "$(dirname "$NVIM_THEME_LINK")"
    ln -sf "$OMARCHY_THEME" "$NVIM_THEME_LINK"
    info "Symlinked Omarchy theme to neovim plugins"
else
    info "No Omarchy theme here — neovim uses its own default colorscheme."
fi

# 7. Install herdr (agent/terminal multiplexer; replaces tmux). Not in the
# Arch repos, so use the official installer. Config is wired in §13.
# Never on remote: herdr runs on the *local* machine, and the server is just
# what's running inside one of its panes.
if $REMOTE; then
    :
elif ! command -v herdr &>/dev/null; then
    info "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
else
    info "herdr already installed."
fi

# 8. Install Pimalaya Tools (Himalaya & Mirador) — omarchy-only since configs
# (himalaya/mirador stow packages) are only stowed on omarchy
if $OMARCHY; then
    info "Checking Pimalaya tools..."

    if command -v cargo &>/dev/null; then
        # himalaya-tui needs the v2 config schema, and crates.io still ships
        # v1.2.0 — so install the CLI v2 from git too. Keep both binaries on v2
        # or the shared ~/.config/himalaya/config.toml won't parse.
        if himalaya --version 2>/dev/null | grep -qE 'v?2\.'; then
            info "Himalaya v2 already installed."
        else
            info "Installing Himalaya v2 from git via cargo..."
            cargo install --locked --git https://github.com/pimalaya/himalaya.git
        fi

        # himalaya-tui: official TUI, not yet released to crates.io — git only.
        # Shares himalaya's config. Bound to prefix+m in herdr.
        if ! command -v himalaya-tui &>/dev/null; then
            info "himalaya-tui not found. Installing from git via cargo..."
            cargo install --locked --git https://github.com/pimalaya/himalaya-tui.git
        else
            info "himalaya-tui is already installed."
        fi
    else
        warn "Cargo not found! Skipping Himalaya installation."
    fi

    if ! command -v mirador &>/dev/null; then
        info "Mirador not found. Installing via AUR..."
        $AUR_HELPER -S --needed --noconfirm mirador-git
    else
        info "Mirador is already installed."
    fi
fi

# 8b/8c/8d are all "rearrange $HOME" steps. None of them run on remote: a work
# server's home directory layout is not ours to reorganize, and pi/mamba/docker
# aren't part of the three things the remote target promises.
if ! $REMOTE; then

# 8b. Install pi coding agent via upstream installer (used by pi.nvim).
info "Checking pi coding agent..."
if command -v pi &>/dev/null; then
    info "pi is already installed ($(pi --version 2>/dev/null || echo unknown))."
else
    info "Installing pi via pi.dev installer..."
    curl -fsSL https://pi.dev/install.sh | sh
    info "pi installed."
fi

# 8c. Migrate pi data from legacy ~/.pi to XDG (~/.config/pi)
# Pi defaults to ~/.pi/agent but respects $PI_CODING_AGENT_DIR (set in
# shell/env.sh to $XDG_CONFIG_HOME/pi/agent). Move pre-existing data
# once so authed sessions / API keys aren't orphaned.
PI_OLD_DIR="$HOME/.pi/agent"
PI_NEW_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/pi/agent"
if [[ -d "$PI_OLD_DIR" && -n "$(ls -A "$PI_OLD_DIR" 2>/dev/null)" ]]; then
    info "Migrating pi data: $PI_OLD_DIR → $PI_NEW_DIR"
    mkdir -p "$PI_NEW_DIR"
    cp -an "$PI_OLD_DIR"/. "$PI_NEW_DIR"/
    rm -rf "$PI_OLD_DIR"
    rmdir "$HOME/.pi" 2>/dev/null || true
fi

# 8d. XDG hygiene — relocate well-known dotfiles to XDG paths and remove
# dead artifacts. Each relocate runs only when the legacy path exists and
# the XDG target doesn't, so this is safe to rerun.
xdg_relocate() {
    local old="$1" new="$2"
    if [[ -e "$old" && ! -e "$new" ]]; then
        info "Relocating $old → $new"
        mkdir -p "$(dirname "$new")"
        mv "$old" "$new"
    fi
}

xdg_relocate "$HOME/.docker"         "${XDG_CONFIG_HOME:-$HOME/.config}/docker"
xdg_relocate "$HOME/.password-store" "${XDG_DATA_HOME:-$HOME/.local/share}/password-store"
xdg_relocate "$HOME/.XCompose"       "${XDG_CONFIG_HOME:-$HOME/.config}/X11/XCompose"
xdg_relocate "$HOME/.cargo"          "${XDG_DATA_HOME:-$HOME/.local/share}/cargo"
xdg_relocate "$HOME/.npm"            "${XDG_CACHE_HOME:-$HOME/.cache}/npm"
xdg_relocate "$HOME/.bun"            "${XDG_DATA_HOME:-$HOME/.local/share}/bun"

# Dead artifacts — recreated on demand by their tools if ever needed.
# ~/.zshrc gets clobbered by `mamba shell init`; the canonical zshrc lives
# in $ZDOTDIR (zsh/.config/zsh/.zshrc) so any $HOME/.zshrc is leftover noise.
rm -f "$HOME/.cdb_history" "$HOME/.zshrc"
rm -rf "$HOME/.mamba" "$HOME/.nv"

# ~/.tmux.conf is a leftover from the pre-herdr days (see 9f0a6e6) and now
# dangles at a target that no package provides. stow trips over it with a
# "BUG in find_stowed_path?" warning on every run. Only removed when it is in
# fact a broken symlink — a real tmux.conf is left alone.
if [[ -L "$HOME/.tmux.conf" && ! -e "$HOME/.tmux.conf" ]]; then
    info "Removing dangling ~/.tmux.conf (pre-herdr leftover)"
    rm -f "$HOME/.tmux.conf"
fi

fi  # ! $REMOTE

# 9. Stow dotfiles
info "Stowing dotfiles..."
# Both package branches in step 1 install stow; fail loudly if neither ran.
command -v stow &>/dev/null || error "stow not installed — rerun step 1 or install it manually."

# Never tree-fold. By default stow links the deepest directory it can — and
# every package here has `.config/<name>/` as its only child, so every one of
# them folds: `~/.config/foo` becomes a symlink to `repo/foo/.config/foo`, and
# anything written to ~/.config/foo/ afterwards lands *inside the repo*. That is
# where this repo's stray secrets.sh, .zcompdump, zsh-syntax-highlighting/ and
# vendored yazi plugins all came from; opencode's herdr plugin followed the same
# path on the very run that added an allowlist without `opencode` on it.
#
# So it's blanket, not a list — an allowlist is one forgotten entry away from
# reintroducing the bug, and folding buys nothing but a few inodes. The cost is
# that a *newly added* file in an existing package needs a re-stow to appear.
STOW_FLAGS=(--adopt --no-folding --target="$HOME")

# `stow --adopt` silently absorbs an existing real file into the repo, and the
# `git checkout -- .` below then throws its contents away. That is how a
# machine's pre-zfiles ~/.bashrc would vanish. So: ask stow what it *would*
# refuse to overwrite (a plain simulation, no --adopt), and stash those aside
# first. Generic, so it protects every future package too.
STOW_BACKUP_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/backup/$(date +%Y%m%d%H%M%S)"

backup_stow_conflicts() {
    local pkg="$1" rel conflicts
    # stow reports conflicts on stderr as:
    #   * existing target is neither a link nor a directory: .bashrc
    conflicts=$(stow -n -v --target="$HOME" "$pkg" 2>&1 \
        | sed -n 's/.*existing target is [^:]*: //p' || true)
    [[ -n "$conflicts" ]] || return 0

    while IFS= read -r rel; do
        [[ -n "$rel" && -e "$HOME/$rel" ]] || continue
        mkdir -p "$STOW_BACKUP_DIR/$(dirname "$rel")"
        cp -a "$HOME/$rel" "$STOW_BACKUP_DIR/$rel"
        warn "Backed up pre-existing ~/$rel → $STOW_BACKUP_DIR/$rel"
    done <<< "$conflicts"
}

# Snapshot which package files were already dirty. `--adopt` rewrites a repo
# file with the contents of whatever it found in $HOME, so the run has to end
# with a revert — but a blanket revert also throws away uncommitted edits that
# were in flight before bootstrap started (which is exactly how this script ate
# its own source-path changes the first time it ran). Anything dirty going in
# stays dirty coming out; only what stow itself changed gets reverted.
readarray -t PRE_DIRTY < <(git diff --name-only -- "${STOW_PACKAGES[@]}" 2>/dev/null || true)

for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ -d "$pkg" ]]; then
        backup_stow_conflicts "$pkg"
        # This links service files to ~/.config/systemd/user/ if structured correctly
        stow "${STOW_FLAGS[@]}" "$pkg"
    else
        warn "Package '$pkg' not found, skipping"
    fi
done

readarray -t POST_DIRTY < <(git diff --name-only -- "${STOW_PACKAGES[@]}" 2>/dev/null || true)
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

# 9b. Wire herdr agent-state integrations (live working/blocked/done in the
# sidebar). Hook files are herdr-versioned generated code, so we invoke the
# generator instead of vendoring them — re-run this anytime to upgrade. Each
# install self-guards on the agent being present; pi needs its extensions dir.
if ! $REMOTE && command -v herdr &>/dev/null; then
    info "Installing herdr agent integrations..."
    mkdir -p "$HOME/.config/pi/agent/extensions"
    for agent in claude opencode pi; do
        herdr integration install "$agent" 2>/dev/null \
            || warn "herdr $agent integration skipped (agent not installed yet)"
    done
fi

# 10. Configure Mirador Services (omarchy-only — service files come from stowed mirador package)
if $OMARCHY; then
    info "Configuring Mirador services..."
    systemctl --user daemon-reload
    systemctl --user enable --now mirador@gmail 2>/dev/null || true
    systemctl --user enable --now mirador@work 2>/dev/null || true
fi

# 11. Install Yazi plugins, and fill the flavor slot on non-Omarchy targets.
#
# theme.toml asks for a flavor called "zfiles" on every machine. Omarchy points
# that name at the rendered theme in §13 so yazi tracks theme switches; WSL and
# servers have no theme engine, so the name resolves to Catppuccin Mocha here.
# Without this, yazi errors out on an unknown flavor.
info "Setting up Yazi plugins..."
if command -v ya &>/dev/null; then
    # The four plugins we use are vendored in the repo and arrive as stowed
    # symlinks, so they work on a machine with no network and stay pinned to a
    # reviewed revision. `ya pkg` can't manage them in that state — it sees the
    # symlink as a locally-modified package and aborts with a scary warning —
    # so only fetch a plugin that isn't already there.
    YAZI_PLUGINS=(full-border smart-enter git jump-to-char)
    missing=()
    for plugin in "${YAZI_PLUGINS[@]}"; do
        [[ -e "$HOME/.config/yazi/plugins/$plugin.yazi/main.lua" ]] || missing+=("$plugin")
    done
    if ((${#missing[@]})); then
        for plugin in "${missing[@]}"; do
            ya pkg add "yazi-rs/plugins:$plugin" || warn "could not fetch yazi plugin '$plugin'"
        done
        ya pkg install || true
        info "Fetched missing yazi plugins: ${missing[*]}"
    else
        info "Yazi plugins already present (vendored in-repo) — nothing to fetch."
    fi

    if ! $OMARCHY; then
        info "Installing Catppuccin Mocha yazi flavor..."
        ya pkg add yazi-rs/flavors:catppuccin-mocha || true
        FLAVOR_DIR="$HOME/.config/yazi/flavors"
        if [[ -d "$FLAVOR_DIR/catppuccin-mocha.yazi" ]]; then
            ln -snf catppuccin-mocha.yazi "$FLAVOR_DIR/zfiles.yazi"
            info "Flavor 'zfiles' → catppuccin-mocha"
        else
            warn "catppuccin-mocha flavor not installed — yazi will complain about flavor 'zfiles'."
        fi
    fi
else
    warn "Yazi (ya) binary not found, skipping plugin setup."
fi

# 12. Configure Hyprland to source zfiles bindings (omarchy-only)
if $OMARCHY; then
    info "Configuring Hyprland..."
    HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
    ZFILES_SOURCE='source = ~/.config/hypr/zfilesbindings.conf'

    if [[ -f "$HYPR_CONF" ]]; then
        if ! grep -qF "$ZFILES_SOURCE" "$HYPR_CONF"; then
            echo -e "\n# zfiles overlay\n$ZFILES_SOURCE" >> "$HYPR_CONF"
            info "Added zfilesbindings.conf to hyprland.conf"
        else
            info "zfilesbindings.conf already sourced in hyprland.conf"
        fi
    else
        warn "hyprland.conf not found, skipping"
    fi
fi

# 13. Install Omarchy theme hook + wire up consumers (omarchy-only)
#
# Theme architecture (see hooks/theme-set for full detail):
#   Templates:   omarchy/.config/omarchy/themed/*.tpl  (stowed in step #9)
#   Rendered:    ~/.config/omarchy/current/theme/<file>  (Omarchy's engine)
#   Hook output: ~/.config/omarchy/current/theme/sioyek-prefs.config (our hook)
#   Consumers:   user configs symlink into the rendered dir; on theme
#                switch, Omarchy's `mv next-theme current` swaps everything
#                atomically and the hook regenerates sioyek/opencode.
if $OMARCHY; then
    info "Installing Omarchy hooks..."
    HOOKS_DIR="$HOME/.config/omarchy/hooks"
    mkdir -p "$HOOKS_DIR"
    ln -sfn "$REPO_DIR/hooks/theme-set"   "$HOOKS_DIR/theme-set"
    ln -sfn "$REPO_DIR/hooks/post-update" "$HOOKS_DIR/post-update"
    chmod +x "$REPO_DIR/hooks/theme-set" "$REPO_DIR/hooks/post-update"

    # Seed the upstream-template snapshot used by post-update's drift check.
    # On first install we treat the current upstream as "reviewed."
    SNAPSHOT_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/upstream-tpl-seen"
    mkdir -p "$SNAPSHOT_DIR"
    for user_tpl in "$REPO_DIR"/omarchy/.config/omarchy/themed/*.tpl; do
        [[ -f "$user_tpl" ]] || continue
        name=$(basename "$user_tpl")
        upstream="$HOME/.local/share/omarchy/default/themed/$name"
        if [[ -f "$upstream" && ! -f "$SNAPSHOT_DIR/$name" ]]; then
            cp "$upstream" "$SNAPSHOT_DIR/$name"
        fi
    done

    # Wire consuming configs to the rendered theme dir. ln -snf is idempotent
    # and replaces any prior real file (e.g., a stale frozen copy from a
    # previous broken setup).
    info "Linking theme consumers to rendered theme dir..."
    THEME_DIR="$HOME/.config/omarchy/current/theme"
    mkdir -p "$HOME/.config/mako" "$HOME/.config/yazi/flavors/zfiles.yazi" "$HOME/.config/sioyek"
    # yazi 25.12.29 removed `$include`; selection now goes through the flavor
    # system. theme.toml names the flavor "zfiles" on every target — here that
    # name resolves to the rendered Omarchy theme, so yazi follows theme-set.
    rm -f "$HOME/.config/yazi/omarchy-theme.toml"
    rm -rf "$HOME/.config/yazi/flavors/omarchy.yazi"
    ln -snf "$THEME_DIR/mako.ini"                 "$HOME/.config/mako/config"
    ln -snf "$THEME_DIR/yazi-omarchy-theme.toml"  "$HOME/.config/yazi/flavors/zfiles.yazi/flavor.toml"
    ln -snf "$THEME_DIR/sioyek-prefs.config"      "$HOME/.config/sioyek/prefs_user.config"
    # herdr config is a plain stowed dotfile (zfiles/herdr), not a theme template.

    # Trigger a full theme re-set so Omarchy renders our user templates and
    # our hook generates its outputs. The theme name lives in theme.name
    # (not in the `current` symlink itself, which points to a real dir).
    if [[ -f "$HOME/.config/omarchy/current/theme.name" ]]; then
        CURRENT_THEME=$(cat "$HOME/.config/omarchy/current/theme.name")
        info "Re-rendering theme: $CURRENT_THEME"
        omarchy-theme-set "$CURRENT_THEME" || warn "omarchy-theme-set failed; templates may be stale until next theme switch"
    fi
fi

# 14. Enable optional services (omarchy-only — work laptops have their own
# sanctioned docker story, and plain servers opt in manually)
if $OMARCHY; then
    info "Enabling services..."
    sudo systemctl enable --now docker 2>/dev/null || true
fi

# 14b. Set up research workspace (the `scripts` package isn't stowed on remote,
# and a work server isn't where the Obsidian/Zotero workflow lives)
if ! $REMOTE; then
    info "Setting up research workspace..."
    mkdir -p "$HOME/research"

    # Seed the research workflow README on first install (don't clobber user edits)
    RESEARCH_README="$HOME/research/README.md"
    README_TEMPLATE="${XDG_DATA_HOME:-$HOME/.local/share}/zfiles/research-readme.md"
    if [[ ! -f "$RESEARCH_README" && -f "$README_TEMPLATE" ]]; then
        cp "$README_TEMPLATE" "$RESEARCH_README"
        info "Installed research workflow README to $RESEARCH_README"
    fi

    if ! command -v new-research-project &>/dev/null; then
        warn "new-research-project not on PATH. Ensure ~/.local/bin is in PATH (zsh)."
    fi
fi

# 15. Windows-side setup (WSL only) — registers the logon scheduled task,
# copies the kanata config, and sets env-var pointers so kanata/GlazeWM/
# WezTerm on the Windows side read their configs from this repo. The script
# arrives with the Windows keybinding/terminal design (zfiles issues #11/#13).
if $WSL; then
    if [[ -f windows/install.ps1 ]]; then
        info "Running Windows-side setup..."
        powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w windows/install.ps1)"
    else
        warn "windows/install.ps1 not present yet — Windows-side setup skipped."
    fi
fi

if $REMOTE; then
    cat <<EOF

>>> Remote setup complete. Installed, all under \$HOME:

       ~/.config/shell   shared env, aliases, commands, git-prompt
       ~/.config/bash    rc.sh + prompt.sh (hooked from ~/.bashrc)
       ~/.config/yazi    file manager config + plugins
       ~/.config/nvim    github.com/zstreeter/nvim
       ~/.local/share/mise  neovim, yazi, fd, rg, fzf, zoxide, bat, eza
                            (on PATH via `mise activate`, run from commands.sh)

     Your existing ~/.bashrc was appended to, not replaced — everything the
     server set up (module/lmod, conda init, site profile) is untouched above
     the "# >>> zfiles >>>" marker.

     Start a new login shell (or \`exec bash -l\`) to pick it up.
     To update later:  zfiles-update

EOF
    info "Done!"
    exit 0
fi

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
