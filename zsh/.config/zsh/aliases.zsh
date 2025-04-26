# Use lunarvim for neovim if present.
[ -x "$(command -v lvim)" ] && alias nvim="lvim" vimdiff="lvim -d"

alias \
	wget='wget --hsts-file="$XDG_CACHE_HOME/wget-hsts"' \
  freecad='QT_QPA_PLATFORM=xcb freecad' \
  openscad='QT_QPA_PLATFORM=xcb openscad' \
  ultimaker-cura='QT_QPA_PLATFORM=xcb UltiMaker-Cura-5.8.1-linux-X64.AppImage' \
  rpi-imager='QT_QPA_PLATFORM=xcb rpi-imager'
