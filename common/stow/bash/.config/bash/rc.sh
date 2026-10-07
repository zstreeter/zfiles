
[[ -f "$HOME/.config/shell/env.sh" ]] && source "$HOME/.config/shell/env.sh"

export HISTFILE="${XDG_STATE_HOME:-$HOME/.local/state}/bash/history"
mkdir -p "${HISTFILE%/*}"

[[ -d "$HOME/.dotnet" ]] && export PATH="$HOME/.dotnet:$PATH"
[[ -f "$HOME/.local/bin/env" ]] && . "$HOME/.local/bin/env"

[[ $- != *i* ]] && return

BLESH="${XDG_DATA_HOME:-$HOME/.local/share}/blesh/ble.sh"
[[ -f "$BLESH" ]] && source "$BLESH" --attach=none

HISTSIZE=10000
HISTFILESIZE=20000
HISTCONTROL=ignoreboth
shopt -s histappend checkwinsize globstar autocd 2>/dev/null

set -o vi

# commands.sh first: it activates mise, and aliases.sh guards on tools mise may provide (eza).
[[ -f "$HOME/.config/shell/commands.sh" ]] && source "$HOME/.config/shell/commands.sh"
[[ -f "$HOME/.config/shell/aliases.sh" ]] && source "$HOME/.config/shell/aliases.sh"

if command -v fzf &>/dev/null; then
    if fzf --bash &>/dev/null; then
        eval "$(fzf --bash)"
    elif [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]]; then
        source /usr/share/doc/fzf/examples/key-bindings.bash
        [[ -f /usr/share/doc/fzf/examples/completion.bash ]] && source /usr/share/doc/fzf/examples/completion.bash
    fi
fi

bind -x '"\C-o": run_yazi' 2>/dev/null

[[ -f "$HOME/.config/bash/prompt.sh" ]] && source "$HOME/.config/bash/prompt.sh"

[[ ! ${BLE_VERSION-} ]] || ble-attach
