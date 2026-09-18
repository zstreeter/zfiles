# Shared setup for every target. Sourced by bootstrap.sh AFTER packages and
# stow; expects REPO_DIR, OMARCHY, WSL, REMOTE, PINENTRY and info/warn/error.
# Steps a work server must not run (gpg, zsh/chsh, pi, $HOME rearranging)
# guard themselves on $REMOTE.
# shellcheck shell=bash

if ! $REMOTE; then
    info "Configuring GPG Agent..."
    GNUPGHOME_TARGET="${GNUPGHOME:-${XDG_DATA_HOME:-$HOME/.local/share}/gnupg}"

    if [[ -d "$HOME/.gnupg" && ! -e "$GNUPGHOME_TARGET" ]]; then
        info "Relocating $HOME/.gnupg → $GNUPGHOME_TARGET"
        gpgconf --kill gpg-agent 2>/dev/null || true
        mkdir -p "$(dirname "$GNUPGHOME_TARGET")"
        mv "$HOME/.gnupg" "$GNUPGHOME_TARGET"
    fi

    mkdir -p "$GNUPGHOME_TARGET"
    chmod 700 "$GNUPGHOME_TARGET"

    if ! grep -q "pinentry-program $PINENTRY" "$GNUPGHOME_TARGET/gpg-agent.conf" 2>/dev/null; then
        echo "pinentry-program $PINENTRY" >> "$GNUPGHOME_TARGET/gpg-agent.conf"
        echo "    Added $(basename "$PINENTRY") to gpg-agent.conf"
    fi

    GNUPGHOME="$GNUPGHOME_TARGET" gpg-connect-agent reloadagent /bye || true
fi

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
# THE single home for every API key and token. Real credentials only.
# Never tracked by git, chmod 600, sourced by shell/.config/shell/env.sh on
# every shell start. If a tool needs a credential, it reads an env var and the
# export goes here -- not into a committed config file, not into a second env
# file beside the tool. (There was one of those for Claude Code; it shadowed a
# key defined here and was merged back in on 2026-09-17.)
#
# Not a credential? Two other homes:
#   env.sh    tracked -- model names, flags, anything safe to publish
#   local.env untracked -- private but not secret: internal endpoints, an
#             employer's site names, paths under a corporate profile
#
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

# --- Research ---
# alphaXiv bookmarks, read by `paperctl pull` and by the alphaxiv CLI. Mint at
# alphaxiv.org -> Settings -> API Keys. arXiv, Crossref and OpenAlex need no
# key at all, so paperctl's other sources have nothing to put here.
# export ALPHAXIV_API_KEY=""
SECRETS
    chmod 600 "$SECRETS_FILE"
    info "Created $SECRETS_FILE — add your API keys there."
else
    info "Secrets file already exists at $SECRETS_FILE"
fi

# Private-but-not-secret settings. Only created on demand -- most machines have
# nothing to put in it, and an empty file invites someone to put a key in it.
LOCAL_ENV="${XDG_CONFIG_HOME:-$HOME/.config}/shell/local.env"
if [[ -f "$LOCAL_ENV" ]]; then
    chmod 600 "$LOCAL_ENV"
    info "Machine-local settings already exist at $LOCAL_ENV"
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

ensure_bash_hook() {
    local target="$1" body="$2"
    if [[ -f "$target" ]] && grep -qF '# >>> zfiles >>>' "$target"; then
        info "bash hook already present in $target"
        return
    fi
    if [[ -s "$target" ]]; then
        local backup="${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/backup"
        mkdir -p "$backup"
        cp -a "$target" "$backup/$(basename "$target").$(date +%Y%m%d%H%M%S)"
    fi
    printf '\n# >>> zfiles >>>\n%s\n# <<< zfiles <<<\n' "$body" >> "$target"
    info "Appended zfiles hook to $target"
}

ensure_login_chain() {
    local f first=""
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
        [[ -f "$f" ]] && { first="$f"; break; }
    done

    if [[ -z "$first" ]]; then
        # Write these variables literally for login time.
        # shellcheck disable=SC2016
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
    # Write these variables literally for login time.
    # shellcheck disable=SC2016
    ensure_bash_hook "$first" \
        '[ -n "$BASH_VERSION" ] && [ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
}

info "Hooking bash into zfiles config..."
# Write these variables literally for shell startup.
# shellcheck disable=SC2016
ensure_bash_hook "$HOME/.bashrc" \
    '[ -f "$HOME/.config/bash/rc.sh" ] && . "$HOME/.config/bash/rc.sh"'
ensure_login_chain

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

info "Setting up neovim config..."
NVIM_DIR="$HOME/.config/nvim"
NVIM_REPO_URL="https://github.com/zstreeter/nvim.git"

install_my_nvim() {
    git clone "$NVIM_REPO_URL" "$NVIM_DIR"
}

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

OMARCHY_THEME="$HOME/.local/state/omarchy/current/theme/neovim.lua"
NVIM_THEME_LINK="$NVIM_DIR/lua/plugins/theme.lua"
LEGACY_NVIM_THEME_LINK="$NVIM_DIR/lua/plugins/omarchy-theme.lua"

[[ -L "$LEGACY_NVIM_THEME_LINK" ]] && rm "$LEGACY_NVIM_THEME_LINK"

if [[ -f "$OMARCHY_THEME" ]]; then
    mkdir -p "$(dirname "$NVIM_THEME_LINK")"
    ln -sfn "$OMARCHY_THEME" "$NVIM_THEME_LINK"
    info "Symlinked Omarchy theme to neovim plugins"
else
    info "No Omarchy theme here — neovim uses its own default colorscheme."
fi

if $REMOTE; then
    :
elif ! command -v herdr &>/dev/null; then
    info "Installing herdr..."
    curl -fsSL https://herdr.dev/install.sh | sh
else
    info "herdr already installed."
fi

if ! $REMOTE; then

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

PI_TEMPLATE="$PI_NEW_DIR/settings.example.json"
PI_SETTINGS="$PI_NEW_DIR/settings.json"
if command -v pi &>/dev/null && [[ -f "$PI_TEMPLATE" ]]; then
    info "Syncing pi packages from settings.example.json..."
    while IFS= read -r pkg; do
        [[ -z "$pkg" ]] && continue
        if [[ -f "$PI_SETTINGS" ]] && jq -e --arg p "$pkg" \
            '(.packages // []) | map(if type == "string" then . else .source end) | index($p) != null' \
            "$PI_SETTINGS" >/dev/null 2>&1; then
            continue
        fi
        info "  pi install $pkg"
        pi install "$pkg" || warn "  failed: $pkg (continuing)"
    done < <(jq -r '.packages[]' "$PI_TEMPLATE")

    if $OMARCHY; then
        PI_THEME="omarchy-system"
        PI_OMARCHY_SRC="$HOME/.local/state/omarchy/current/theme/pi.json"
        if [[ -f "$PI_OMARCHY_SRC" ]]; then
            mkdir -p "$PI_NEW_DIR/themes"
            cat "$PI_OMARCHY_SRC" > "$PI_NEW_DIR/themes/omarchy-system.json"
        fi
    else
        PI_THEME=$(jq -r '.theme // empty' "$PI_TEMPLATE")
    fi
    if [[ -n "$PI_THEME" && -f "$PI_SETTINGS" ]] \
        && [[ "$(jq -r '.theme // empty' "$PI_SETTINGS")" != "$PI_THEME" ]]; then
        info "Setting pi theme: $PI_THEME"
        tmp=$(mktemp "$PI_SETTINGS.XXXXXX")
        jq --arg t "$PI_THEME" '.theme = $t' "$PI_SETTINGS" > "$tmp" && mv "$tmp" "$PI_SETTINGS"
    fi
fi

AGENTPAL_REPO="${AGENTPAL_REPO:-$HOME/Documents/DevicePals/AgentPal}"
AGENTPAL_EXT="$AGENTPAL_REPO/integrations/pi/agentpal.ts"
if [[ -f "$AGENTPAL_EXT" ]]; then
    mkdir -p "$PI_NEW_DIR/extensions"
    if [[ "$(readlink -f "$PI_NEW_DIR/extensions/agentpal.ts" 2>/dev/null)" != "$AGENTPAL_EXT" ]]; then
        info "Linking AgentPal pi extension from $AGENTPAL_REPO"
        ln -sfn "$AGENTPAL_EXT" "$PI_NEW_DIR/extensions/agentpal.ts"
    fi
fi

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

rm -f "$HOME/.cdb_history" "$HOME/.zshrc"
rm -rf "$HOME/.mamba" "$HOME/.nv"

if [[ -L "$HOME/.tmux.conf" && ! -e "$HOME/.tmux.conf" ]]; then
    info "Removing dangling ~/.tmux.conf (pre-herdr leftover)"
    rm -f "$HOME/.tmux.conf"
fi

if command -v herdr &>/dev/null; then
    info "Installing herdr agent integrations..."
    mkdir -p "$HOME/.config/pi/agent/extensions"
    for agent in claude opencode pi; do
        herdr integration install "$agent" 2>/dev/null \
            || warn "herdr $agent integration skipped (agent not installed yet)"
    done
fi

if [[ -d "$HOME/.config/opencode/plugins" ]] \
    && ! [[ -d "$HOME/.config/opencode/node_modules/@opencode-ai/plugin" ]] \
    && command -v npm &>/dev/null; then
    info "Pre-installing opencode plugin SDK (bun can't reach the registry)..."
    (cd "$HOME/.config/opencode" && npm install --no-audit --no-fund @opencode-ai/plugin) \
        || warn "opencode plugin SDK install failed — opencode will be slow to first paint."
fi

fi  # ! $REMOTE

info "Setting up Yazi plugins..."
if command -v ya &>/dev/null; then
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

if ! $REMOTE; then
    info "Setting up research workspace..."
    mkdir -p "$HOME/research"

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

if command -v agent-skills &>/dev/null; then
    info "Linking agent skills..."
    agent-skills || warn "agent-skills failed; run it by hand to see why"
elif [[ -d "$HOME/.agents/skills" ]]; then
    info "Agent skills in ~/.agents/skills (pi reads these natively)"
fi


if [[ -d "$HOME/.agents/skills/measure" ]] && ! command -v measure &>/dev/null; then
    warn "measure skill is installed but 'measure' is not on PATH.
      Check that ~/.local/bin is in PATH and that the 'measure' package stowed."
fi
