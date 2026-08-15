# Shared setup for every target. Sourced by bootstrap.sh AFTER packages and
# stow; expects REPO_DIR, OMARCHY, WSL, REMOTE, PINENTRY and info/warn/error.
# Steps a work server must not run (gpg, zsh/chsh, pi, $HOME rearranging)
# guard themselves on $REMOTE.

# GPG agent — skipped on remote: a work server's gpg setup is the server's
# business, and relocating GNUPGHOME under someone else's machine is exactly
# the kind of surprise that target avoids.
# shell/env.sh sets GNUPGHOME=$XDG_DATA_HOME/gnupg. Bootstrap may run under
# bash without that loaded, so derive the target path the same way.
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

    # Idempotent: the target's setup.sh picks PINENTRY (GUI on Omarchy, curses
    # on WSL) so pass and signed commits work in a bare terminal.
    if ! grep -q "pinentry-program $PINENTRY" "$GNUPGHOME_TARGET/gpg-agent.conf" 2>/dev/null; then
        echo "pinentry-program $PINENTRY" >> "$GNUPGHOME_TARGET/gpg-agent.conf"
        echo "    Added $(basename "$PINENTRY") to gpg-agent.conf"
    fi

    # Reload agent (auto-starts under the new GNUPGHOME) to apply changes
    GNUPGHOME="$GNUPGHOME_TARGET" gpg-connect-agent reloadagent /bye || true
fi

# Configure zsh with XDG and Zap — skipped on remote, which is bash-only
# (that's why the shared config lives in `shell`, not `zsh`). No chsh on a
# machine whose login shell isn't ours to change.
if ! $REMOTE; then
info "Configuring zsh..."

cat > "$HOME/.zshenv" << 'EOF'
export ZDOTDIR="${XDG_CONFIG_HOME:-$HOME/.config}/zsh"
[[ -f "$ZDOTDIR/.zshenv" ]] && source "$ZDOTDIR/.zshenv"
EOF

# Secrets live beside the rest of the shared shell config now. Migrate the
# pre-`shell`-package location once; xdg_relocate runs later, so do it here
# where the file is about to be read.
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

# Hook bash into the zfiles config. Deliberately an *append* to whatever
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

# ble.sh — bash syntax highlighting/autosuggestions/autopair, giving the
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

# Clone neovim config (SMART INSTALL). Runs on every target including
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

# Install herdr (agent/terminal multiplexer; replaces tmux). Not in the Arch
# repos, so use the official installer. Never on remote: herdr runs on the
# *local* machine, and the server is just what's inside one of its panes.
if $REMOTE; then
    :
elif ! command -v herdr &>/dev/null; then
    info "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
else
    info "herdr already installed."
fi

# The remaining agent/$HOME steps don't run on remote: a work server's home
# directory layout is not ours to reorganize, and pi/mamba/docker aren't part
# of the three things the remote target promises.
if ! $REMOTE; then

# Install pi coding agent via upstream installer (used by pi.nvim).
info "Checking pi coding agent..."
if command -v pi &>/dev/null; then
    info "pi is already installed ($(pi --version 2>/dev/null || echo unknown))."
else
    info "Installing pi via pi.dev installer..."
    curl -fsSL https://pi.dev/install.sh | sh
    info "pi installed."
fi

# Migrate pi data from legacy ~/.pi to XDG (~/.config/pi)
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

# XDG hygiene — relocate well-known dotfiles to XDG paths and remove
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

# Wire herdr agent-state integrations (live working/blocked/done in the
# sidebar). Hook files are herdr-versioned generated code, so we invoke the
# generator instead of vendoring them — re-run this anytime to upgrade. Each
# install self-guards on the agent being present; pi needs its extensions dir.
if command -v herdr &>/dev/null; then
    info "Installing herdr agent integrations..."
    mkdir -p "$HOME/.config/pi/agent/extensions"
    for agent in claude opencode pi; do
        herdr integration install "$agent" 2>/dev/null \
            || warn "herdr $agent integration skipped (agent not installed yet)"
    done
fi

fi  # ! $REMOTE

# Install Yazi plugins, and fill the flavor slot on non-Omarchy targets.
#
# theme.toml asks for a flavor called "zfiles" on every machine. Omarchy points
# that name at the rendered theme in omarchy/setup.sh so yazi tracks theme
# switches; WSL and servers have no theme engine, so the name resolves to
# Catppuccin Mocha here. Without this, yazi errors out on an unknown flavor.
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

# Static sioyek colors on non-Omarchy desktops — same idea as the yazi flavor
# slot above. ~/.local/bin/sioyek always launches in custom color mode, and
# Omarchy's theme-set hook is what normally symlinks prefs_user.config at the
# rendered theme. A target with no theme engine gets the same Catppuccin Mocha
# palette the yazi flavor falls back to. Never clobber: sioyek itself writes to
# this file when settings change in the UI.
#
# Not on WSL. There is no Linux sioyek to configure there — ~/.local/bin/sioyek
# routes to the Windows build, whose prefs are a portable-install file next to
# the exe that wsl/windows/install.ps1 writes from wsl/windows/sioyek/
# prefs_user.config. Writing a Linux prefs file here would only be a decoy for
# the next person wondering why editing it changes nothing.
if ! $OMARCHY && ! $REMOTE && ! $WSL && [[ -d "$HOME/.config/sioyek" ]]; then
    SIOYEK_PREFS="$HOME/.config/sioyek/prefs_user.config"
    if [[ -e "$SIOYEK_PREFS" ]]; then
        info "Sioyek prefs already present at ${SIOYEK_PREFS/#$HOME/\~} — leaving it alone."
    else
        info "Writing static sioyek colors (Catppuccin Mocha)..."
        cat > "$SIOYEK_PREFS" << 'EOF'
# Static fallback written by bootstrap — no theme engine on this target.
# Catppuccin Mocha, matching the yazi flavor fallback. Sioyek wants each
# channel as a float in [0.0, 1.0]. On Omarchy this file is instead a symlink
# to the theme-set hook's rendered sioyek-prefs.config.
background_color 0.118 0.118 0.180
custom_background_color 0.118 0.118 0.180
custom_text_color 0.804 0.839 0.957
text_highlight_color 0.976 0.886 0.686
synctex_highlight_color 0.537 0.706 0.980
link_highlight_color 0.537 0.706 0.980
search_highlight_color 0.345 0.357 0.439
EOF
    fi
fi

# Research workspace (the `scripts` package isn't stowed on remote, and a work
# server isn't where the Obsidian/Zotero workflow lives)
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
