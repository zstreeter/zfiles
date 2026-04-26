#!/usr/bin/env bash

function run_yazi() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXX")"
	yazi "$@" --cwd-file="$tmp"
	if cwd="$(cat -- "$tmp")" && [ -n "$cwd" ] && [ "$cwd" != "$PWD" ]; then
		cd -- "$cwd"
	fi
	rm -f -- "$tmp"
}
bindkey -s '^o' 'run_yazi\n'

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

# ssh with agent forwarding forced on (works without ~/.ssh/config tweaks).
# Loads default keys into the agent on demand if it has none.
function sshf() {
	ssh-add -l >/dev/null 2>&1
	[ $? -eq 1 ] && ssh-add 2>/dev/null
	ssh -o ForwardAgent=yes -o AddKeysToAgent=yes "$@"
}
