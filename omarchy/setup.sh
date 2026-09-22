# Omarchy target (Arch + Hyprland desktop). Sourced by bootstrap.sh;
# defines target_packages / target_setup, expects REPO_DIR + helpers.
# shellcheck shell=bash

export PINENTRY=/usr/bin/pinentry-gtk

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

    systemctl --user disable --now mirador@gmail mirador@work 2>/dev/null || true
    [[ -L "$HOME/.config/mirador/config.toml" ]] && rm "$HOME/.config/mirador/config.toml"
    [[ -L "$HOME/.config/systemd/user/mirador@.service" ]] && rm "$HOME/.config/systemd/user/mirador@.service"
    rmdir "$HOME/.config/mirador" 2>/dev/null || true
    cargo uninstall mirador >/dev/null 2>&1 || true
    if pacman -Qq mirador-git &>/dev/null; then
        sudo pacman -Rns --noconfirm mirador-git
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
    rm -f "$HOME/.config/hypr/hypridle.conf" "$HOME/.config/hypr/hyprlock.conf"
    if hyprctl reload >/dev/null 2>&1; then
        if [[ -n "$(hyprctl configerrors)" ]]; then
            hyprctl configerrors >&2
            return 1
        fi
    else
        warn "Hyprland is not running; deployed overlay will load next session."
    fi

    local legacy_hook
    for legacy_hook in theme-set post-update; do
        if [[ -L "$HOME/.config/omarchy/hooks/$legacy_hook" \
            && "$(readlink -m "$HOME/.config/omarchy/hooks/$legacy_hook")" == "$REPO_DIR/"* ]]; then
            rm "$HOME/.config/omarchy/hooks/$legacy_hook"
        fi
    done

    local snapshot_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/upstream-tpl-seen"
    mkdir -p "$snapshot_dir"
    local user_tpl name upstream
    for user_tpl in "$REPO_DIR"/omarchy/stow/omarchy/.config/omarchy/themed/*.tpl; do
        [[ -f "$user_tpl" ]] || continue
        name=$(basename "$user_tpl")
        upstream="${OMARCHY_PATH:-/usr/share/omarchy}/default/themed/$name"
        if [[ -f "$upstream" && ! -f "$snapshot_dir/$name" ]]; then
            cp "$upstream" "$snapshot_dir/$name"
        fi
    done

    info "Linking theme consumers to rendered theme dir..."
    local theme_dir="$HOME/.local/state/omarchy/current/theme"
    mkdir -p "$HOME/.config/yazi/flavors/zfiles.yazi" "$HOME/.config/sioyek"
    rm -f "$HOME/.config/yazi/omarchy-theme.toml"
    rm -rf "$HOME/.config/yazi/flavors/omarchy.yazi"
    ln -snf "$theme_dir/yazi-omarchy-theme.toml"  "$HOME/.config/yazi/flavors/zfiles.yazi/flavor.toml"
    ln -snf "$theme_dir/sioyek-prefs.config"      "$HOME/.config/sioyek/prefs_user.config"

    if [[ -f "$HOME/.local/state/omarchy/current/theme.name" ]]; then
        local current_theme
        current_theme=$(cat "$HOME/.local/state/omarchy/current/theme.name")
        info "Rendering overlay for theme: $current_theme"
        OMARCHY_THEME_HEADLESS=1 OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy-theme-set "$current_theme"
        bash "$HOME/.config/omarchy/hooks/theme-set.d/zfiles" "$current_theme"
    fi

    info "Reconciling services..."
    systemctl --user try-restart wireplumber.service
    sudo systemctl enable --now docker.socket
    sudo systemctl disable docker.service 2>/dev/null || true
}
