# Remote target: someone else's server, everything under $HOME. Sourced by
# bootstrap.sh; expects REPO_DIR + helpers.
# shellcheck shell=bash

# shellcheck disable=SC2034  # read by bootstrap.sh / common/setup.sh
OWNS_HOME=false
mapfile -t STOW_ONLY < <(grep -v '^#' "$REPO_DIR/remote/stow.txt" | grep -v '^$')
# An empty STOW_ONLY means *every* package -- never let a missing list do that here.
((${#STOW_ONLY[@]})) || error "no packages read from remote/stow.txt"

target_packages() {
    info "Installing user-local toolchain via mise (no root)..."
    install_mise_stack neovim@latest yazi@latest
}

target_setup() {
    cat <<EOF

>>> Remote setup complete. Installed, all under \$HOME:

       ~/.config/shell   shared env, aliases, commands, git-prompt
       ~/.config/bash    rc.sh + prompt.sh (hooked from ~/.bashrc)
       ~/.config/yazi    file manager config + plugins
       ~/.config/nvim    github.com/zstreeter/nvim
       ~/.local/share/mise  neovim, yazi, fd, rg, fzf, zoxide, bat, eza
                            (on PATH via \`mise activate\`, run from commands.sh)

     Your existing ~/.bashrc was appended to, not replaced — everything the
     server set up (module/lmod, conda init, site profile) is untouched above
     the "# >>> zfiles >>>" marker.

     Start a new login shell (or \`exec bash -l\`) to pick it up.
     To update later:  zfiles-update

EOF
    info "Done!"
}
