# For my sanity, `plug` just seems to be an alias for `source`

# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

# rust env
. "$HOME/.local/share/cargo/env"

# Hopefully fast-syntax-highlighting will be in the ZAP marketplace one day
plug "$HOME/.local/share/zap/plugins/f-sy-h/F-Sy-H.plugin.zsh"
f-sy-h $HOME/.config/zsh/f-sy-h-catppuccin-macchiato >/dev/null

plug "$HOME/.config/zsh/my-prompt.sh"
plug "$HOME/.config/zsh/exports.zsh" # Exports must be before aliases
plug "$HOME/.config/zsh/aliases.zsh"

# From Marketplace
plug "zsh-users/zsh-autosuggestions"
plug "zap-zsh/supercharge"
plug "zap-zsh/exa"
plug "zap-zsh/vim"
plug "hlissner/zsh-autopair"
plug "MichaelAquilina/zsh-you-should-use"
plug "conda-incubator/conda-zsh-completion"
plug "zap-zsh/fzf"

# My commands
plug "$HOME/.config/zsh/commands.sh"

# Load and initialise completion system
fpath=($HOME/.config/lf/_lf $fpath)
autoload -Uz compinit
compinit -d "$XDG_CACHE_HOME"/zsh/zcompdump="$ZSH_VERSION"

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/home/zstreet/.local/miniconda/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/home/zstreet/.local/miniconda/etc/profile.d/conda.sh" ]; then
        . "/home/zstreet/.local/miniconda/etc/profile.d/conda.sh"
    else
        export PATH="/home/zstreet/.local/miniconda/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<
