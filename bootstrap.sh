#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

# Packages to stow (directories with dotfiles)
STOW_PACKAGES=(cura hypr tmux yazi zathura zsh)

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

# Strip comments and blank lines from pkglist
grep -v '^#' pkglist.txt | grep -v '^$' | $AUR_HELPER -S --needed --noconfirm -

# 2. Configure keyd
info "Configuring keyd (Caps → Esc/Super)..."
sudo mkdir -p /etc/keyd
sudo cp root_etc/keyd/default.conf /etc/keyd/default.conf
sudo systemctl enable --now keyd

# 3. Configure zsh with XDG
info "Configuring zsh..."

# Create ~/.zshenv to set ZDOTDIR (must be in $HOME, can't be stowed)
cat > "$HOME/.zshenv" << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
EOF

# Change default shell to zsh if not already
if [[ "$SHELL" != */zsh ]]; then
    info "Changing default shell to zsh..."
    chsh -s "$(command -v zsh)"
fi

# 4. Clone neovim config
info "Setting up neovim config..."
NVIM_DIR="$HOME/.config/nvim"
if [[ -d "$NVIM_DIR/.git" ]]; then
    info "Neovim config exists, pulling latest..."
    git -C "$NVIM_DIR" pull
else
    if [[ -d "$NVIM_DIR" ]]; then
        warn "Existing nvim config found, backing up to nvim.bak"
        mv "$NVIM_DIR" "$HOME/.config/nvim.bak"
    fi
    git clone https://github.com/zstreeter/nvim.git "$NVIM_DIR"
fi

# 5. Stow dotfiles
info "Stowing dotfiles..."
command -v stow &>/dev/null || sudo pacman -S --needed --noconfirm stow

for pkg in "${STOW_PACKAGES[@]}"; do
    if [[ -d "$pkg" ]]; then
        stow --adopt --target="$HOME" "$pkg"
    else
        warn "Package '$pkg' not found, skipping"
    fi
done

# Restore repo state (adopt pulls in local changes)
git checkout -- .

# 6. Configure Hyprland to source zfiles bindings
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

# 7. Install Omarchy theme hook
info "Installing Omarchy theme hook..."
HOOKS_DIR="$HOME/.config/omarchy/hooks"
mkdir -p "$HOOKS_DIR"
cp "$REPO_DIR/hooks/theme-set" "$HOOKS_DIR/theme-set"
chmod +x "$HOOKS_DIR/theme-set"

# Run hook for current theme to generate initial configs
if [[ -d "$HOME/.config/omarchy/current/theme" ]]; then
    CURRENT_THEME=$(basename "$(readlink -f "$HOME/.config/omarchy/current")" 2>/dev/null || echo "unknown")
    info "Generating theme configs for: $CURRENT_THEME"
    "$HOOKS_DIR/theme-set" "$CURRENT_THEME"
fi

# 8. Enable optional services
info "Enabling services..."
sudo systemctl enable --now docker 2>/dev/null || true
systemctl --user enable --now email-sync.timer 2>/dev/null || true

info "Done! Log out and back in for shell change, reboot for keyd."
