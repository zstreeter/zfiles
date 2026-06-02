#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Detect whether we're on top of Omarchy. When false, omarchy-specific steps
# (Hyprland source, theme-hook install, mirador/gammastep services) are skipped
# and only cross-platform packages are stowed.
OMARCHY=false
if [[ -d "$HOME/.local/share/omarchy" || -d "$HOME/.config/omarchy" ]]; then
    OMARCHY=true
fi

# Cross-platform packages — safe on any Linux
CORE_PACKAGES=(cura tmux yazi sioyek zsh scripts opencode pi xdg wireplumber)
# Omarchy/Hyprland-specific packages — only stowed when OMARCHY=true.
# `omarchy` ships user template overrides at ~/.config/omarchy/themed/ that
# Omarchy's template engine renders on every theme switch.
OMARCHY_PACKAGES=(hypr himalaya mirador omarchy)

STOW_PACKAGES=("${CORE_PACKAGES[@]}")
if $OMARCHY; then
    STOW_PACKAGES+=("${OMARCHY_PACKAGES[@]}")
fi

info() { echo -e "\033[1;34m>>>\033[0m $1"; }
warn() { echo -e "\033[1;33m!!!\033[0m $1"; }
error() { echo -e "\033[1;31mERR\033[0m $1" >&2; exit 1; }

if $OMARCHY; then
    info "Omarchy detected — installing full overlay."
else
    info "No Omarchy detected — installing core packages only."
fi

# 1. Install packages
info "Installing packages..."

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

# 2. Default applications are declarative — defined in xdg/.config/mimeapps.list
# (stowed in step 9). Entries that point at uninstalled .desktop files
# silently no-op, so it's safe to ship the full list cross-platform.

# 3. Configure keyd
info "Configuring keyd (Caps → Esc/Super)..."
sudo mkdir -p /etc/keyd
sudo cp root_etc/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd

# 4. Configure GPG Agent (Pinentry GTK)
# zsh/exports.zsh sets GNUPGHOME=$XDG_DATA_HOME/gnupg. Bootstrap may run
# under bash without that loaded, so derive the target path the same way.
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

# Ensure pinentry-gtk is set (idempotent)
if ! grep -q "pinentry-program /usr/bin/pinentry-gtk" "$GNUPGHOME_TARGET/gpg-agent.conf" 2>/dev/null; then
    echo "pinentry-program /usr/bin/pinentry-gtk" >> "$GNUPGHOME_TARGET/gpg-agent.conf"
    echo "    Added pinentry-gtk to gpg-agent.conf"
fi

# Reload agent (auto-starts under the new GNUPGHOME) to apply changes
GNUPGHOME="$GNUPGHOME_TARGET" gpg-connect-agent reloadagent /bye || true

# 5. Configure zsh with XDG and Zap
info "Configuring zsh..."

cat > "$HOME/.zshenv" << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
EOF

SECRETS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/secrets.env"
if [[ ! -f "$SECRETS_FILE" ]]; then
    mkdir -p "$(dirname "$SECRETS_FILE")"
    cat > "$SECRETS_FILE" << 'SECRETS'
# API keys — fill these in, this file is never tracked by git.
# Sourced by zsh/.config/zsh/exports.zsh on every shell start.
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

# 6. Clone neovim config (SMART INSTALL)
info "Setting up neovim config..."
NVIM_DIR="$HOME/.config/nvim"
MY_REPO_URL="https://github.com/zstreeter/nvim.git"

install_my_nvim() {
    git clone "$MY_REPO_URL" "$NVIM_DIR"
}

if [[ -d "$NVIM_DIR" ]]; then
    if [[ -d "$NVIM_DIR/.git" ]]; then
        REMOTE_URL=$(git -C "$NVIM_DIR" remote get-url origin 2>/dev/null || true)
        if [[ "$REMOTE_URL" == *zstreeter/nvim* ]]; then
            info "Correct Neovim config found, pulling latest..."
            git -C "$NVIM_DIR" pull
        else
            warn "Unknown Neovim git repo found. Backing up..."
            rm -rf "$HOME/.config/nvim.omarchy.bak"
            mv "$NVIM_DIR" "$HOME/.config/nvim.omarchy.bak"
            rm -rf "$HOME/.local/share/nvim"
            install_my_nvim
        fi
    else
        warn "Default Omarchy config found. Backing up..."
        rm -rf "$HOME/.config/nvim.omarchy.bak"
        mv "$NVIM_DIR" "$HOME/.config/nvim.omarchy.bak"
        rm -rf "$HOME/.local/share/nvim"
        install_my_nvim
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
    warn "Omarchy theme not found, skipping neovim symlink"
fi

# 7. Install Tmux Plugin Manager (TPM)
info "Setting up Tmux Plugin Manager..."
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
    mkdir -p "$TPM_DIR"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    info "TPM already installed."
fi

# 8. Install Pimalaya Tools (Himalaya & Mirador) — omarchy-only since configs
# (himalaya/mirador stow packages) are only stowed on omarchy
if $OMARCHY; then
    info "Checking Pimalaya tools..."

    if command -v cargo &>/dev/null; then
        if ! command -v himalaya &>/dev/null; then
            info "Himalaya not found. Installing via cargo..."
            cargo install himalaya
        else
            info "Himalaya is already installed."
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
# zsh/exports.zsh to $XDG_CONFIG_HOME/pi/agent). Move pre-existing data
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

# 9. Stow dotfiles
info "Stowing dotfiles..."
# Ensure stow is installed
command -v stow &>/dev/null || sudo pacman -S --needed --noconfirm stow

# Packages that must NOT be tree-folded. By default stow links the deepest
# directory it can — so a package whose only child is `.config/foo/` becomes
# `~/.config/foo` -> repo/.../foo, and a later `ln -s` into ~/.config/foo/
# would land in the repo. These packages get a runtime theme symlink (see
# step #13) into ~/.config/<pkg>/, so the directory must stay real.
NO_FOLD_PACKAGES=(yazi sioyek)

for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ -d "$pkg" ]]; then
        flags=(--adopt --target="$HOME")
        if [[ " ${NO_FOLD_PACKAGES[*]} " == *" $pkg "* ]]; then
            flags+=(--no-folding)
        fi
        # This links service files to ~/.config/systemd/user/ if structured correctly
        stow "${flags[@]}" "$pkg"
    else
        warn "Package '$pkg' not found, skipping"
    fi
done

# Restore repo state (adopt pulls in local changes)
git checkout -- .

# 10. Configure Mirador Services (omarchy-only — service files come from stowed mirador package)
if $OMARCHY; then
    info "Configuring Mirador services..."
    systemctl --user daemon-reload
    systemctl --user enable --now mirador@gmail 2>/dev/null || true
    systemctl --user enable --now mirador@work 2>/dev/null || true
fi

# 11. Install Yazi Plugins
info "Setting up Yazi plugins..."
if command -v ya &>/dev/null; then
    ya pkg add yazi-rs/plugins:full-border || true
    ya pkg add yazi-rs/plugins:smart-enter || true
    ya pkg install
    ya pkg upgrade
    info "Yazi plugins installed and upgraded."
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
    mkdir -p "$HOME/.config/mako" "$HOME/.config/yazi/flavors/omarchy.yazi" "$HOME/.config/sioyek"
    # yazi 25.12.29 removed `$include`; selection now goes through the flavor
    # system, so the rendered theme is exposed as flavors/omarchy.yazi/flavor.toml.
    rm -f "$HOME/.config/yazi/omarchy-theme.toml"
    ln -snf "$THEME_DIR/mako.ini"                 "$HOME/.config/mako/config"
    ln -snf "$THEME_DIR/yazi-omarchy-theme.toml"  "$HOME/.config/yazi/flavors/omarchy.yazi/flavor.toml"
    ln -snf "$THEME_DIR/sioyek-prefs.config"      "$HOME/.config/sioyek/prefs_user.config"

    # Trigger a full theme re-set so Omarchy renders our user templates and
    # our hook generates its outputs. The theme name lives in theme.name
    # (not in the `current` symlink itself, which points to a real dir).
    if [[ -f "$HOME/.config/omarchy/current/theme.name" ]]; then
        CURRENT_THEME=$(cat "$HOME/.config/omarchy/current/theme.name")
        info "Re-rendering theme: $CURRENT_THEME"
        omarchy-theme-set "$CURRENT_THEME" || warn "omarchy-theme-set failed; templates may be stale until next theme switch"
    fi
fi

# 14. Enable optional services
info "Enabling services..."
sudo systemctl enable --now docker 2>/dev/null || true

# 14b. Set up research workspace
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

SECRETS_FILE_DISPLAY="${XDG_CONFIG_HOME:-$HOME/.config}/zsh/secrets.env"
cat <<EOF

>>> AI providers — add your API keys to:
       $SECRETS_FILE_DISPLAY

     Uncomment and fill in the providers you actually use (ANTHROPIC_API_KEY,
     GEMINI_API_KEY, OPENAI_API_KEY, …). The file is sourced by zsh on shell
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

info "Done! Log out and back in for shell change, reboot for keyd."
