# Omarchy target (Arch + Hyprland desktop). Sourced by bootstrap.sh;
# defines target_packages / target_setup, expects REPO_DIR + helpers.
# shellcheck shell=bash

export PINENTRY=/usr/bin/pinentry-gtk
# shellcheck disable=SC2034  # read by common/setup.sh
STATIC_THEME=false  # Omarchy renders every theme consumer; see hooks/theme-set.d

target_packages() {
    info "Installing packages (pacman)..."

    AUR_HELPER=$(command -v paru || command -v yay || true)
    if [[ -z "$AUR_HELPER" ]]; then
        warn "No AUR helper found. Installing paru..."
        sudo pacman -S --needed --noconfirm base-devel git
        local tmpdir
        tmpdir=$(mktemp -d)
        git clone https://aur.archlinux.org/paru.git "$tmpdir/paru"
        (cd "$tmpdir/paru" && makepkg -si --noconfirm)
        rm -rf "$tmpdir"
        AUR_HELPER="paru"
    fi

    sudo pacman -S --needed --noconfirm pinentry stow xdg-utils

    grep -v '^#' "$REPO_DIR/omarchy/pkglist.txt" | grep -v '^$' \
        | $AUR_HELPER -S --needed --noconfirm -

    # sioyek-git links the exact libmupdf soname (libmupdf.so.28.0, not .28),
    # so a libmupdf point release leaves it unable to start until rebuilt.
    # The pacman hook in root_etc warns at upgrade time; this repairs it.
    if ldd /usr/bin/sioyek 2>/dev/null | grep -q 'not found'; then
        warn "sioyek is linked against a library that is gone; rebuilding sioyek-git..."
        $AUR_HELPER -S --rebuild --noconfirm sioyek-git
    fi
}

target_setup() {
    info "Configuring keyd (Caps → Esc/Super)..."
    sudo mkdir -p /etc/keyd
    sudo cp "$REPO_DIR/omarchy/root_etc/keyd/default.conf" /etc/keyd/default.conf
    sudo systemctl enable --now keyd

    info "Installing pacman hook (warn when libmupdf changes under sioyek-git)..."
    sudo install -Dm644 "$REPO_DIR/omarchy/root_etc/pacman.d/hooks/sioyek-rebuild.hook" \
        /etc/pacman.d/hooks/sioyek-rebuild.hook

    info "Checking Pimalaya tools..."
    if command -v cargo &>/dev/null; then
        export CARGO_HOME="$HOME/.local/share/cargo"
        export RUSTUP_HOME="$HOME/.local/share/rustup"
        export PATH="$CARGO_HOME/bin:$PATH"
        mkdir -p "$CARGO_HOME"

        if himalaya --version 2>/dev/null | grep -qE 'v?2\.'; then
            info "Himalaya v2 already installed."
        else
            info "Installing Himalaya v2 from git via cargo..."
            cargo install --locked --git https://github.com/pimalaya/himalaya.git
        fi

        if ! command -v himalaya-tui &>/dev/null; then
            info "himalaya-tui not found. Installing from git via cargo..."
            cargo install --locked --git https://github.com/pimalaya/himalaya-tui.git
        else
            info "himalaya-tui is already installed."
        fi

        info "Installing/updating Carillon from git..."
        cargo install --locked --git https://github.com/pimalaya/carillon.git
    else
        warn "Cargo not found! Skipping Pimalaya installation."
    fi

    if [[ -x "$HOME/.local/share/cargo/bin/carillon" ]]; then
        info "Configuring Carillon services..."
        systemctl --user daemon-reload
        systemctl --user enable carillon@gmail carillon@work
        systemctl --user restart carillon@gmail carillon@work
    else
        warn "Carillon is unavailable; email watcher services were not started."
    fi

    info "Deploying Hyprland overlay..."
    local source name
    mkdir -p "$HOME/.config/hypr"
    for source in "$REPO_DIR"/omarchy/config/hypr/*.lua; do
        name=$(basename "$source")
        cp "$source" "$HOME/.config/hypr/$name.tmp"
        mv "$HOME/.config/hypr/$name.tmp" "$HOME/.config/hypr/$name"
    done
    if hyprctl reload >/dev/null 2>&1; then
        if [[ -n "$(hyprctl configerrors)" ]]; then
            hyprctl configerrors >&2
            return 1
        fi
    else
        warn "Hyprland is not running; deployed overlay will load next session."
    fi

    info "Linking theme consumers to rendered theme dir..."
    local theme_dir="$HOME/.local/state/omarchy/current/theme"
    mkdir -p "$HOME/.config/yazi/flavors/zfiles.yazi" "$HOME/.config/sioyek"
    ln -snf "$theme_dir/yazi-omarchy-theme.toml"  "$HOME/.config/yazi/flavors/zfiles.yazi/flavor.toml"
    ln -snf "$theme_dir/sioyek-prefs.config"      "$HOME/.config/sioyek/prefs_user.config"

    local nvim_plugins="$HOME/.config/nvim/lua/plugins"
    if [[ -d "$nvim_plugins" ]]; then
        ln -sfn "$theme_dir/neovim.lua" "$nvim_plugins/theme.lua"
    fi

    # Same path an Omarchy update takes: re-render the theme, baseline the
    # upstream templates, and check the overlay just deployed actually loaded.
    info "Running the post-update hook (theme render + overlay check)..."
    bash "$HOME/.config/omarchy/hooks/post-update.d/zfiles"

    info "Reconciling services..."
    systemctl --user try-restart wireplumber.service
}
