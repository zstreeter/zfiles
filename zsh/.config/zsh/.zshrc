# For my sanity, `plug` just seems to be an alias for `source`

# Created by Zap installer
[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh" ] && source "${XDG_DATA_HOME:-$HOME/.local/share}/zap/zap.zsh"

plug "$HOME/.config/zsh/my-prompt.sh"
# Shell-agnostic — the same files bash sources out of ~/.config/shell.
plug "$HOME/.config/shell/aliases.sh"

# Completion system. This has to come *before* fzf-tab (which hooks the
# completion menu) and before anything that wraps zle widgets, so it can no
# longer live at the bottom of the file. Completion plugins that only add to
# $fpath belong above compinit.
plug "conda-incubator/conda-zsh-completion"
fpath=($HOME/.config/lf/_lf $fpath)
autoload -Uz compinit
mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/zsh"
compinit -d "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump-$ZSH_VERSION"

# fzf-tab: the completion menu becomes an fzf picker. Must load after compinit
# and before any widget-wrapping plugin (autosuggestions, syntax-highlighting),
# or it gets its own widgets clobbered.
plug "Aloxaf/fzf-tab"

# From Marketplace
plug "zap-zsh/supercharge"
plug "zap-zsh/exa"
plug "zap-zsh/vim"
plug "hlissner/zsh-autopair"
plug "MichaelAquilina/zsh-you-should-use"
plug "zap-zsh/fzf"

# My commands
plug "$HOME/.config/shell/commands.sh"

# Per-tool init (interactive-only)
plug "$HOME/.config/zsh/bun.zsh"
plug "$HOME/.config/zsh/mamba.zsh"

# Widget wrappers load last — syntax-highlighting must be the final plugin
# sourced (its own README), and autosuggestions has to sit after fzf-tab.
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"

# fzf-tab settings live at the bottom so nothing sourced above can override
# them (zap-zsh/supercharge sets `menu select`, which fights fzf-tab). zstyles
# are read at completion time, so being last costs nothing.
zstyle ':completion:*' menu no                       # required: no zsh menu
zstyle ':completion:*' file-sort modification
zstyle ':fzf-tab:*' fzf-flags --height=60% --layout=reverse
zstyle ':fzf-tab:*' switch-group '<' '>'             # cycle completion groups
# Directory previews, using tools zfiles already guarantees (bootstrap step 1b).
if (( $+commands[eza] )); then
    zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --icons=auto --color=always $realpath'
    zstyle ':fzf-tab:complete:z:*'  fzf-preview 'eza -1 --icons=auto --color=always $realpath'
fi
