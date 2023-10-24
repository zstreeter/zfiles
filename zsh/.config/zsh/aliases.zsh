# Use lunarvim for neovim if present.
[ -x "$(command -v lvim)" ] && alias nvim="lvim" vimdiff="lvim -d"

alias \
	wget='wget --hsts-file="$XDG_CACHE_HOME/wget-hsts"'
