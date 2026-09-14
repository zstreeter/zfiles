# WSL Ubuntu target (Windows work laptop). Sourced by bootstrap.sh;
# defines target_packages / target_setup, expects REPO_DIR + helpers.
# Keyboard/WM/terminal live on the Windows side — see wsl/windows/.

PINENTRY=/usr/bin/pinentry-curses

target_packages() {
    info "Installing packages (apt + mise)..."
    # apt covers the stable system tools (wsl/pkglist.txt); mise covers
    # everything noble ships stale or not at all — see the mapping research
    # on zfiles issue #7.
    sudo apt-get update
    grep -v '^#' "$REPO_DIR/wsl/pkglist.txt" | grep -v '^$' | xargs sudo apt-get install -y

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
        local quarto_deb tmpdeb
        quarto_deb=$(curl -fsSL https://api.github.com/repos/quarto-dev/quarto-cli/releases/latest \
            | grep -o 'https://[^"]*linux-amd64\.deb' | head -1)
        if [[ -n "$quarto_deb" ]]; then
            tmpdeb=$(mktemp --suffix=.deb)
            curl -fsSL -o "$tmpdeb" "$quarto_deb"
            sudo dpkg -i "$tmpdeb"
            rm -f "$tmpdeb"
        else
            warn "Could not resolve quarto .deb URL; install manually."
        fi
    fi
}

target_setup() {
    # herdr-navd — the resident daemon that arbitrates a focus move across
    # nvim splits → herdr panes → GlazeWM windows. Caps+hjkl on the Windows
    # side reaches it over localhost; see the header of
    # common/stow/herdr/.local/bin/herdr-navd for why the Linux half has to be
    # resident rather than a script.
    #
    # WSL-only because the outermost hop talks to GlazeWM. On Omarchy the same
    # job belongs to hypr's herdr-nav script, which Hyprland spawns per
    # keypress.
    info "Enabling herdr-navd..."
    systemctl --user daemon-reload
    if systemctl --user enable --now herdr-navd 2>/dev/null; then
        # A stowed unit that changed on disk needs the restart; enable --now is
        # a no-op once it's already running.
        systemctl --user restart herdr-navd 2>/dev/null || true
        info "herdr-navd running on 127.0.0.1:6224"
    else
        warn "could not enable herdr-navd — Caps+hjkl will move windows but not panes/splits."
    fi

    # Windows-side setup — installs AutoHotkey and GlazeWM, copies their
    # configs plus WezTerm's onto the Windows side, registers both logon
    # tasks, and switches WSL to mirrored networking so herdr-navd can reach
    # GlazeWM's IPC server on 127.0.0.1.
    if [[ -f "$REPO_DIR/wsl/windows/install.ps1" ]]; then
        info "Running Windows-side setup..."
        powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$REPO_DIR/wsl/windows/install.ps1")"
    else
        warn "wsl/windows/install.ps1 not present — Windows-side setup skipped."
    fi
}
