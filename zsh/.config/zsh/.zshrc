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
