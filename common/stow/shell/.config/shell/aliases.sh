[ -x "$(command -v lvim)" ] && alias nvim="lvim" vimdiff="lvim -d"

alias \
	wget='wget --hsts-file="$XDG_CACHE_HOME/wget-hsts"' \
  freecad='QT_QPA_PLATFORM=xcb freecad' \
  openscad='QT_QPA_PLATFORM=xcb openscad' \
  ultimaker-cura='QT_QPA_PLATFORM=xcb UltiMaker-Cura-5.8.1-linux-X64.AppImage' \
  rpi-imager='QT_QPA_PLATFORM=xcb rpi-imager'

# eza listings, shared by bash and zsh so `l` means the same command (and highlights the same) in both.
if command -v eza >/dev/null 2>&1; then
	alias ls='eza --icons=auto' l='eza -lbF' ll='eza -la' lt='eza --tree --level=2'
fi
