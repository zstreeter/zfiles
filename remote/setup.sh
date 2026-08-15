# Remote work-server target (reached over ssh from a herdr pane). Sourced by
# bootstrap.sh --remote; never sudo, never a package manager, never chsh —
# everything lands under $HOME. See remote/install.sh for the entry point.

# The stow subset a remote gets: bash prompt + shared shell config + yazi.
# No zsh (those are bash terminals), nothing desktop-, agent- or mail-bound.
STOW_ONLY=(shell bash yazi)

target_packages() {
    # No sudo, no package manager — mise is the only source of binaries here.
    # Just the two headline tools; the core-CLI backfill in bootstrap.sh
    # covers fd/rg/fzf/zoxide/eza/bat on every target.
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
