# Bash mirror of the zsh setup. Shared files (env, aliases, commands, git
# prompt) live in ~/.config/shell and are sourced from both shells; only the
# prompt and line-editor pieces here are bash-specific.
#
# This file is NOT stowed over ~/.bashrc. Bootstrap appends a guarded source
# line to whatever ~/.bashrc already exists, so a server's site setup (lmod,
# module, conda init) survives untouched. See ensure_bash_hook() in bootstrap.sh.

# Shared environment (plain exports, bash-safe)
[[ -f "$HOME/.config/shell/env.sh" ]] && source "$HOME/.config/shell/env.sh"

# env.sh points HISTFILE at zsh's history — keep bash history separate.
export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
mkdir -p "${HISTFILE%/*}"

# Machine-local PATH extras (kept from the pre-zfiles ~/.bashrc)
[[ -d "$HOME/.dotnet" ]] && export PATH="$HOME/.dotnet:$PATH"
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

# Interactive-only from here
[[ $- != *i* ]] && return

# ble.sh — syntax highlighting, autosuggestions, autopair (zsh-plugin parity).
# Installed by bootstrap into $XDG_DATA_HOME/blesh; degrade gracefully without.
BLESH="${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh"
[[ -f "$BLESH" ]] && source "$BLESH" --attach=none

HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
shopt -s histappend checkwinsize globstar autocd 2>/dev/null

# vi mode (zap-zsh/vim parity)
set -o vi

# Shared aliases + commands (mise, zoxide, run_yazi, ssh-agent, sshf)
[[ -f "$HOME/.config/shell/aliases.sh" ]] && source "$HOME/.config/shell/aliases.sh"
[[ -f "$HOME/.config/shell/commands.sh" ]] && source "$HOME/.config/shell/commands.sh"

# eza aliases (zap-zsh/exa parity; omarchy's bash aliases add their own where present)
if command -v eza &>/dev/null; then
    alias ls='eza --icons=auto'
    alias l='eza -lbF'
    alias ll='eza -la'
    alias lt='eza --tree --level=2'
fi

# fzf keybindings (zap-zsh/fzf parity): fzf >= 0.48 self-serves; older
# Ubuntu/Debian ship the scripts under /usr/share/doc.
if command -v fzf &>/dev/null; then
    if fzf --bash &>/dev/null; then
        eval "$(fzf --bash)"
    elif [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
        source /usr/share/doc/fzf/examples/key-bindings.bash
        [[ -f /usr/share/doc/fzf/examples/completion.bash ]] && source /usr/share/doc/fzf/examples/completion.bash
    fi
fi

# Ctrl-O opens yazi and cd's to where you quit (bindkey parity)
bind -x '"\C-o": run_yazi' 2>/dev/null

# Two-line prompt with right-aligned git info (my-prompt.sh parity)
[[ -f "$HOME/.config/bash/prompt.sh" ]] && source "$HOME/.config/bash/prompt.sh"

# Attach ble.sh last (its documented pattern)
[[ ! ${BLE_VERSION-} ]] || ble-attach
