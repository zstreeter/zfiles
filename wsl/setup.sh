
PINENTRY=/usr/bin/pinentry-curses

target_packages() {
    info "Installing packages (apt + mise)..."
    sudo apt-get update
    grep -v '^#' "$REPO_DIR/wsl/pkglist.txt" | grep -v '^$' | xargs sudo apt-get install -y

    mkdir -p "$HOME/.local/bin"
    command -v fdfind &>/dev/null && ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
    command -v batcat &>/dev/null && ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"

    install_mise_stack go@latest rust@latest bun@latest node@lts \
                       neovim@latest yazi@latest opencode@latest

    install_herdr

    # Without a userspace OOM killer, WSL thrashes swap until the kernel kills
    # whatever it picks -- observed twice, taking out systemd --user (and with
    # it herdr-navd's restart). earlyoom acts earlier and chooses: Lean servers
    # and node (MCP/agents) first, never systemd/init/dbus/sshd. It fires only
    # when RAM *and* swap are both low; -s 50 acts at ~8 of .wslconfig's 16 GB
    # swap rather than letting it thrash through nearly all of it.
    local eo='EARLYOOM_ARGS="-m 5 -s 50 -r 0 --prefer ^(lean|lake|node)$ --avoid ^(systemd|init|dbus-daemon|sshd)$"'
    if ! grep -qxF "$eo" /etc/default/earlyoom 2>/dev/null; then
        echo "$eo" | sudo tee /etc/default/earlyoom >/dev/null
        sudo systemctl restart earlyoom
    fi
    sudo systemctl enable --now earlyoom

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
    # publish-confluence renders maths with ~/.local/lib/texsvg/tex2svg.js, which
    # needs mathjax-full beside it. The dir is stowed, so install in place.
    if [[ -f "$HOME/.local/lib/texsvg/package.json" ]]; then
        (cd "$HOME/.local/lib/texsvg" && npm install --no-audit --no-fund) \
            || warn "mathjax-full install failed; publish-confluence will not render maths"
    fi

    info "Enabling herdr-navd..."
    systemctl --user daemon-reload
    if systemctl --user enable --now herdr-navd 2>/dev/null; then
        systemctl --user restart herdr-navd 2>/dev/null || true
        info "herdr-navd running on 127.0.0.1:6224"
    else
        warn "could not enable herdr-navd — Caps+hjkl will move windows but not panes/splits."
    fi

    if [[ -f "$REPO_DIR/wsl/windows/install.ps1" ]]; then
        info "Running Windows-side setup..."
        powershell.exe -ExecutionPolicy Bypass -File "$(wslpath -w "$REPO_DIR/wsl/windows/install.ps1")"
    else
        warn "wsl/windows/install.ps1 not present — Windows-side setup skipped."
    fi
}
