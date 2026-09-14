#!/usr/bin/env bash

# Pull in omarchy's portable bash aliases and functions. They're plain POSIX-ish
# shell so zsh sources them cleanly, which means omarchy updates flow through
# automatically without re-porting per release.
if [[ -d "$OMARCHY_PATH/default/bash" ]]; then
	source "$OMARCHY_PATH/default/bash/aliases"
	source "$OMARCHY_PATH/default/bash/functions"
fi

# Tool integrations — this file is sourced by both zsh and bash.
# starship is skipped — handled by zsh prompt.sh / bash prompt.sh.
# fzf is handled by the zap-zsh/fzf plugin (zsh) / .bashrc (bash).
if [ -n "${ZSH_VERSION:-}" ]; then _zfiles_shell=zsh; else _zfiles_shell=bash; fi
command -v mise &>/dev/null && eval "$(mise activate $_zfiles_shell)"
command -v zoxide &>/dev/null && eval "$(zoxide init $_zfiles_shell)"
unset _zfiles_shell

function run_yazi() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
# bash binds ^o in .bashrc (bind -x); bindkey is zsh-only
[ -n "${ZSH_VERSION:-}" ] && bindkey -s '^o' 'run_yazi\n'

# Persistent ssh-agent at ~/.ssh/agent/socket shared across shells. Skipped
# inside SSH sessions (preserves forwarded SSH_AUTH_SOCK) and when another
# agent (keyring, 1Password, etc.) has set SSH_AUTH_SOCK to something else.
SSH_AGENT_SOCK="$HOME/.ssh/agent/socket"
if [ -z "$SSH_CONNECTION" ] && command -v ssh-agent >/dev/null 2>&1 \
   && { [ -z "$SSH_AUTH_SOCK" ] || [ "$SSH_AUTH_SOCK" = "$SSH_AGENT_SOCK" ]; }; then
	mkdir -p "${SSH_AGENT_SOCK%/*}" && chmod 700 "${SSH_AGENT_SOCK%/*}"
	# Drop a stale socket whose agent is gone (ssh-add exit 2 = no agent).
	if [ -S "$SSH_AGENT_SOCK" ]; then
		SSH_AUTH_SOCK="$SSH_AGENT_SOCK" ssh-add -l >/dev/null 2>&1
		[ $? -eq 2 ] && rm -f "$SSH_AGENT_SOCK"
	fi
	[ -S "$SSH_AGENT_SOCK" ] || eval "$(ssh-agent -a "$SSH_AGENT_SOCK" -s)" >/dev/null 2>&1
	[ -S "$SSH_AGENT_SOCK" ] && export SSH_AUTH_SOCK="$SSH_AGENT_SOCK"
fi
unset SSH_AGENT_SOCK

# Load identities into the agent above. Lives here rather than its own file
# because it is the second half of that block: the agent is useless empty.
#
# The github.com entries in ~/.ssh/config point IdentityFile at *.pub on
# purpose, so the same config works on remote nodes over agent forwarding. That
# only resolves when the agent already holds the matching private key -- with an
# empty agent ssh tries to parse the .pub as a private key ("error in
# libcrypto"), offers nothing, and every clone/push fails "Permission denied
# (publickey)".
#
# Skips keys already loaded rather than re-running `ssh-add` blindly: a
# passphrase-protected key would otherwise prompt on every new shell.
# Suffixed keys first, bare key last. A suffix names the identity the key
# belongs to (id_ed25519_<account>), so those are the specific cases and the
# unsuffixed key is the fallback for everything else -- the same precedence
# ~/.gitconfig's includeIf rules apply to the matching author identity. Which
# keys exist is a property of the machine, not of this repository, so this
# globs rather than naming them and skips whatever is absent. The glob lives
# inside the function so zsh's nullglob can be scoped to it: at top level an
# unmatched pattern is a hard error under zsh's default nomatch.
function load_ssh_keys() {
	[ -n "$ZSH_VERSION" ] && setopt localoptions nullglob
	local loaded key fp
	loaded=$(ssh-add -l 2>/dev/null)
	[ $? -eq 2 ] && return 0 # no agent reachable; nothing to load into
	for key in "$HOME"/.ssh/id_ed25519_* "$HOME/.ssh/id_ed25519"; do
		[ -f "$key" ] || continue # private keys are not synced to remote nodes
		case "$key" in *.pub) continue ;; esac # a glob picks up the public half too
		fp=$(ssh-keygen -lf "$key" 2>/dev/null | awk '{print $2}')
		case "$loaded" in *"$fp"*) [ -n "$fp" ] && continue ;; esac
		ssh-add -q "$key" 2>/dev/null
	done
}

load_ssh_keys

# ssh with agent forwarding forced on (works without ~/.ssh/config tweaks).
# Loads default keys into the agent on demand if it has none.
function sshf() {
	ssh-add -l >/dev/null 2>&1
	[ $? -eq 1 ] && ssh-add 2>/dev/null
	ssh -o ForwardAgent=yes -o AddKeysToAgent=yes "$@"
}

# Pull the latest zfiles and re-run bootstrap for whichever checkout is here.
# ~/.zfiles is the sparse remote-server clone; ~/zfiles is the full local one.
function zfiles-update() {
	if [ -d "$HOME/.zfiles/.git" ]; then
		git -C "$HOME/.zfiles" pull --ff-only && "$HOME/.zfiles/bootstrap.sh" --remote
	elif [ -d "$HOME/zfiles/.git" ]; then
		git -C "$HOME/zfiles" pull --ff-only && "$HOME/zfiles/bootstrap.sh"
	else
		echo "zfiles-update: no checkout found at ~/.zfiles or ~/zfiles" >&2
		return 1
	fi
}
