# For my sanity, `plug` just seems to be an alias for `source`

# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

# rust
PATH=$HOME/.local/share/cargo/bin:$PATH

plug "$HOME/.config/zsh/my-prompt.sh"
# plug "$HOME/.config/zsh/exports.zsh" # Exports must be before aliases
plug "$HOME/.config/zsh/aliases.zsh"

# From Marketplace
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"
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

# >>> mamba initialize >>>
# !! Contents within this block are managed by 'mamba shell init' !!
export MAMBA_EXE='/home/zstreet/.miniforge3/bin/mamba';
export MAMBA_ROOT_PREFIX='/home/zstreet/.miniforge3';
__mamba_setup="$("$MAMBA_EXE" shell hook --shell zsh --root-prefix "$MAMBA_ROOT_PREFIX" 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__mamba_setup"
else
    alias mamba="$MAMBA_EXE"  # Fallback on help from mamba activate
fi
unset __mamba_setup
# <<< mamba initialize <<<
