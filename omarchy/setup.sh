# Omarchy target (Arch + Hyprland desktop). Sourced by bootstrap.sh;
# defines target_packages / target_setup, expects REPO_DIR + helpers.

PINENTRY=/usr/bin/pinentry-gtk

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

    # Install essential base tools explicitly to ensure they exist
    # (pinentry is needed for the GPG config step; xdg-utils for xdg-mime)
    sudo pacman -S --needed --noconfirm pinentry stow xdg-utils

    # Strip comments and blank lines from pkglist.txt
    grep -v '^#' "$REPO_DIR/omarchy/pkglist.txt" | grep -v '^$' \
        | $AUR_HELPER -S --needed --noconfirm -
}

target_setup() {
    # keyd: Caps → Esc (tap) / Super (hold)
    info "Configuring keyd (Caps → Esc/Super)..."
    sudo mkdir -p /etc/keyd
    sudo cp "$REPO_DIR/omarchy/root_etc/keyd/default.conf" /etc/keyd/default.conf
    sudo systemctl enable --now keyd

    # Pimalaya tools (Himalaya & Mirador) — configs come from the stowed
    # himalaya/mirador packages, which only exist on this target.
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
        # AUR_HELPER comes from target_packages; ZFILES_SKIP_PKG skips that
        # step, so re-derive it here rather than crash on an unset variable.
        "${AUR_HELPER:-$(command -v paru || command -v yay || echo paru)}" \
            -S --needed --noconfirm mirador-git
    else
        info "Mirador is already installed."
    fi

    info "Configuring Mirador services..."
    systemctl --user daemon-reload
    systemctl --user enable --now mirador@gmail 2>/dev/null || true
    systemctl --user enable --now mirador@work 2>/dev/null || true

    # Hyprland (Omarchy 4, Lua config): hyprland.lua already requires
    # hypr.monitors / hypr.bindings / hypr.autostart — the stowed
    # omarchy/stow/hypr/.config/hypr/*.lua files ARE those modules. Nothing to
    # wire; Omarchy's migration drops template copies of them, which the
    # stow conflict backup stashes aside.
    info "Reloading Hyprland..."
    hyprctl reload >/dev/null 2>&1 || true

    # Omarchy theme hooks + consumers
    #
    # Theme architecture (see omarchy/hooks/theme-set for full detail):
    #   Templates:   omarchy/stow/omarchy/.config/omarchy/themed/*.tpl (stowed)
    #   Rendered:    ~/.local/state/omarchy/current/theme/<file>  (Omarchy's engine)
    #   Hook output: ~/.local/state/omarchy/current/theme/sioyek-prefs.config (our hook)
    #   Consumers:   user configs symlink into the rendered dir; on theme
    #                switch, Omarchy's `mv next-theme current` swaps everything
    #                atomically and the hook regenerates sioyek/opencode.
    info "Installing Omarchy hooks..."
    local hooks_dir="$HOME/.config/omarchy/hooks"
    mkdir -p "$hooks_dir"
    ln -sfn "$REPO_DIR/omarchy/hooks/theme-set"   "$hooks_dir/theme-set"
    ln -sfn "$REPO_DIR/omarchy/hooks/post-update" "$hooks_dir/post-update"
    chmod +x "$REPO_DIR/omarchy/hooks/theme-set" "$REPO_DIR/omarchy/hooks/post-update"

    # Seed the upstream-template snapshot used by post-update's drift check.
    # On first install we treat the current upstream as "reviewed."
    local snapshot_dir="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/upstream-tpl-seen"
    mkdir -p "$snapshot_dir"
    local user_tpl name upstream
    for user_tpl in "$REPO_DIR"/omarchy/stow/omarchy/.config/omarchy/themed/*.tpl; do
        [[ -f "$user_tpl" ]] || continue
        name=$(basename "$user_tpl")
        upstream="$HOME/.local/share/omarchy/default/themed/$name"
        if [[ -f "$upstream" && ! -f "$snapshot_dir/$name" ]]; then
            cp "$upstream" "$snapshot_dir/$name"
        fi
    done

    # Wire consuming configs to the rendered theme dir. ln -snf is idempotent
    # and replaces any prior real file (e.g., a stale frozen copy from a
    # previous broken setup).
    info "Linking theme consumers to rendered theme dir..."
    local theme_dir="$HOME/.local/state/omarchy/current/theme"
    mkdir -p "$HOME/.config/yazi/flavors/zfiles.yazi" "$HOME/.config/sioyek"
    # yazi 25.12.29 removed `$include`; selection now goes through the flavor
    # system. theme.toml names the flavor "zfiles" on every target — here that
    # name resolves to the rendered Omarchy theme, so yazi follows theme-set.
    rm -f "$HOME/.config/yazi/omarchy-theme.toml"
    rm -rf "$HOME/.config/yazi/flavors/omarchy.yazi"
    ln -snf "$theme_dir/yazi-omarchy-theme.toml"  "$HOME/.config/yazi/flavors/zfiles.yazi/flavor.toml"
    ln -snf "$theme_dir/sioyek-prefs.config"      "$HOME/.config/sioyek/prefs_user.config"
    # herdr config is a plain stowed dotfile (common/stow/herdr), not a theme template.

    # Trigger a full theme re-set so Omarchy renders our user templates and
    # our hook generates its outputs. The theme name lives in theme.name
    # (not in the `current` symlink itself, which points to a real dir).
    if [[ -f "$HOME/.local/state/omarchy/current/theme.name" ]]; then
        local current_theme
        current_theme=$(cat "$HOME/.local/state/omarchy/current/theme.name")
        info "Re-rendering theme: $current_theme"
        omarchy-theme-set "$current_theme" || warn "omarchy-theme-set failed; templates may be stale until next theme switch"
    fi

    # Optional services (work laptops have their own sanctioned docker story)
    info "Enabling services..."
    sudo systemctl enable --now docker 2>/dev/null || true
}
