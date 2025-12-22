#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Packages to stow (directories with dotfiles)
STOW_PACKAGES=(cura hypr tmux yazi zathura zsh himalaya mirador)

info() { echo -e "\033[1;34m>>>\033[0m $1"; }
warn() { echo -e "\033[1;33m!!!\033[0m $1"; }
error() { echo -e "\033[1;31mERR\033[0m $1" >&2; exit 1; }

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
sudo pacman -S --needed --noconfirm pinentry stow

# Strip comments and blank lines from pkglist.txt
grep -v '^#' pkglist.txt | grep -v '^$' | $AUR_HELPER -S --needed --noconfirm -

# 2. Configure keyd
info "Configuring keyd (Caps → Esc/Super)..."
sudo mkdir -p /etc/keyd
sudo cp root_etc/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd

# 3. Configure GPG Agent (Pinentry GTK)
info "Configuring GPG Agent..."
mkdir -p ~/.gnupg
chmod 700 ~/.gnupg

# Ensure pinentry-gtk is set (idempotent)
if ! grep -q "pinentry-program /usr/bin/pinentry-gtk" ~/.gnupg/gpg-agent.conf 2>/dev/null; then
    echo "pinentry-program /usr/bin/pinentry-gtk" >> ~/.gnupg/gpg-agent.conf
    echo "    Added pinentry-gtk to gpg-agent.conf"
fi

# Reload agent to apply changes
gpg-connect-agent reloadagent /bye || true

# 4. Configure zsh with XDG and Zap
info "Configuring zsh..."

cat > "$HOME/.zshenv" << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
EOF

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

# 5. Clone neovim config (SMART INSTALL)
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

# 6. Install Tmux Plugin Manager (TPM)
info "Setting up Tmux Plugin Manager..."
TPM_DIR="$HOME/.config/tmux/plugins/tpm"
if [[ ! -d "$TPM_DIR" ]]; then
    mkdir -p "$TPM_DIR"
    git clone https://github.com/tmux-plugins/tpm "$TPM_DIR"
else
    info "TPM already installed."
fi

# 7. Install Pimalaya Tools (Himalaya & Mirador)
info "Checking Pimalaya tools..."

# Himalaya via Cargo
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

# Mirador via AUR (Moved from Cargo to AUR as requested)
if ! command -v mirador &>/dev/null; then
    info "Mirador not found. Installing via AUR..."
    $AUR_HELPER -S --needed --noconfirm mirador-git
else
    info "Mirador is already installed."
fi

# 8. Stow dotfiles
info "Stowing dotfiles..."
# Ensure stow is installed
command -v stow &>/dev/null || sudo pacman -S --needed --noconfirm stow

for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ -d "$pkg" ]]; then
        # This links mirador service files to ~/.config/systemd/user/
        stow --adopt --target="$HOME" "$pkg"
    else
        warn "Package '$pkg' not found, skipping"
    fi
done

# Restore repo state (adopt pulls in local changes)
git checkout -- .

# 9. Configure Mirador Services
# Must happen AFTER stowing so the service files exist
info "Configuring Mirador services..."
systemctl --user daemon-reload
# Enable specific instances defined in your config
systemctl --user enable --now mirador@gmail 2>/dev/null || true
systemctl --user enable --now mirador@work 2>/dev/null || true

# 10. Install Yazi Plugins
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

# 11. Configure Hyprland to source zfiles bindings
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

# 12. Install Omarchy theme hook
info "Installing Omarchy theme hook..."
HOOKS_DIR="$HOME/.config/omarchy/hooks"
mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/theme-set" "$HOOKS_DIR/theme-set"
chmod +x "$HOOKS_DIR/theme-set"

if [[ -d "$HOME/.config/omarchy/current/theme" ]]; then
    CURRENT_THEME=$(basename "$(readlink -f "$HOME/.config/omarchy/current")" 2>/dev/null || echo "unknown")
    info "Generating theme configs for: $CURRENT_THEME"
    "$HOOKS_DIR/theme-set" "$CURRENT_THEME"
fi

# 13. Enable optional services
info "Enabling services..."
sudo systemctl enable --now docker 2>/dev/null || true

info "Done! Log out and back in for shell change, reboot for keyd."
