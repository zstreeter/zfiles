# zfiles_target -- which machine shape this is: omarchy, wsl, remote or linux.
# The one definition: bootstrap.sh sources it from the repo, scripts from
# ~/.config/shell. POSIX sh, so bash, zsh and sh can all source it.
#
# ZFILES_TARGET wins (bootstrap --remote sets it; tests steer with it). Remote
# can't be sniffed, so bootstrap leaves a marker on a remote box; the rest is
# probed.
zfiles_target() {
    if [ -n "${ZFILES_TARGET:-}" ]; then
        printf '%s\n' "$ZFILES_TARGET"
    elif [ -e "${XDG_STATE_HOME:-$HOME/.local/state}/zfiles/remote" ]; then
        echo remote
    elif [ -d /usr/share/omarchy ] || [ -d "$HOME/.local/share/omarchy" ]; then
        echo omarchy
    elif grep -qi microsoft /proc/version 2>/dev/null; then
        echo wsl
    else
        echo linux
    fi
}
