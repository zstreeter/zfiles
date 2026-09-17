#!/usr/bin/env bash

if [[ -d "$OMARCHY_PATH/default/bash" ]]; then
	source "$OMARCHY_PATH/default/bash/aliases"
	source "$OMARCHY_PATH/default/bash/functions"
fi

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
[ -n "${ZSH_VERSION:-}" ] && bindkey -s '^o' 'run_yazi\n'

SSH_AGENT_SOCK="$HOME/.ssh/agent/socket"
if [ -z "$SSH_CONNECTION" ] && command -v ssh-agent >/dev/null 2>&1 \
   && { [ -z "$SSH_AUTH_SOCK" ] || [ "$SSH_AUTH_SOCK" = "$SSH_AGENT_SOCK" ]; }; then
	mkdir -p "${SSH_AGENT_SOCK%/*}" && chmod 700 "${SSH_AGENT_SOCK%/*}"
	if [ -S "$SSH_AGENT_SOCK" ]; then
		SSH_AUTH_SOCK="$SSH_AGENT_SOCK" ssh-add -l >/dev/null 2>&1
		[ $? -eq 2 ] && rm -f "$SSH_AGENT_SOCK"
	fi
	[ -S "$SSH_AGENT_SOCK" ] || eval "$(ssh-agent -a "$SSH_AGENT_SOCK" -s)" >/dev/null 2>&1
	[ -S "$SSH_AGENT_SOCK" ] && export SSH_AUTH_SOCK="$SSH_AGENT_SOCK"
fi
unset SSH_AGENT_SOCK

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

function sshf() {
	ssh-add -l >/dev/null 2>&1
	[ $? -eq 1 ] && ssh-add 2>/dev/null
	ssh -o ForwardAgent=yes -o AddKeysToAgent=yes "$@"
}

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
