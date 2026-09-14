# Remote work-server target (reached over ssh from a herdr pane). Sourced by
# bootstrap.sh --remote; never sudo, never a package manager, never chsh —
# everything lands under $HOME. See remote/install.sh for the entry point.

# The stow subset a remote gets: bash prompt + shared shell config + yazi.
# No zsh (those are bash terminals), nothing desktop- or mail-bound.
#
# The trailing packages are skills — plain markdown under ~/.agents/skills that
# every harness reads. They are here because an agent running ON the work
# server should still know how this pipeline is built: that Quarto reads
# Obsidian notes directly, that filters belong at `at: pre-ast`, that
# references.bib is generated and must not be hand-edited. Nothing in them
# needs a GUI, and being wrong about those on a remote box costs exactly as
# much as being wrong locally.
#
# `scripts` is still excluded, so no research workspace is created here — a
# work server is not where the vault lives. The skills describe the workflow;
# they do not install it.
#
# `measure` and `paperctl` are the two that carry a real program rather than
# only a skill. `measure` belongs here most of all: the benchmarks run on this
# box, and this is where an agent's context reset is most likely to turn a
# measured number into a remembered one. `paperctl` earns its place differently
# — a work server has no mail client to read, and its config says so
# (`[target.remote.mail] backend = "none"`), but searching arXiv and filing a
# paper need nothing but outbound HTTPS. Python 3 and git are all either needs.
STOW_ONLY=(shell bash yazi measure paperctl obsidian quarto pandoc zotero latex reverify)

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
