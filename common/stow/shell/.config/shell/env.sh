
export EDITOR="nvim"
if command -v ghostty >/dev/null 2>&1; then
    export TERMINAL="ghostty"
    export TERMINAL_PROG="ghostty"
fi
export FILE_MANAGER="yazi"

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

export TMUX_TMPDIR="$XDG_RUNTIME_DIR"
export ANDROID_SDK_HOME="$XDG_CONFIG_HOME/android"
export CABAL_CONFIG="$XDG_DATA_HOME/cabal"
export CARGO_HOME="$XDG_DATA_HOME/cargo"
export RUSTUP_HOME="$XDG_DATA_HOME/rustup"
export GOPATH="$XDG_DATA_HOME/go"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export ANSIBLE_CONFIG="$XDG_CONFIG_HOME/ansible/ansible.cfg"
export UNISON="$XDG_DATA_HOME/unison"
export HISTFILE="$XDG_DATA_HOME/history"
export MBSYNCRC="$XDG_CONFIG_HOME/mbsync/config"
export ELECTRUMDIR="$XDG_DATA_HOME/electrum"
export PYTHONSTARTUP="$XDG_CONFIG_HOME/python/pythonrc"
export SQLITE_HISTORY="$XDG_DATA_HOME/sqlite_history"
export GNUPGHOME="$XDG_DATA_HOME/gnupg"
export GOPATH="$XDG_DATA_HOME/go"
export GOMODCACHE="$XDG_CACHE_HOME/go/mod"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export NPM_CONFIG_CACHE="$XDG_CACHE_HOME/npm"
export PI_CODING_AGENT_DIR="$XDG_CONFIG_HOME/pi/agent"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
export PASSWORD_STORE_DIR="$XDG_DATA_HOME/password-store"
export XCOMPOSEFILE="$XDG_CONFIG_HOME/X11/XCompose"
export WGETRC="$XDG_CONFIG_HOME/wgetrc"
export LESSHISTFILE="$XDG_CONFIG_HOME/less/history"
export LESSKEY="$XDG_CONFIG_HOME/less/keys"
export HISTFILE="$XDG_STATE_HOME/zsh/history"
export GDBHISTFILE="$XDG_DATA_HOME"/gdb/history
export STACK_XDG=1

export CONDA_ROOT="$HOME/.local/miniconda"

export BUN_INSTALL="$XDG_DATA_HOME/bun"
export PATH="$BUN_INSTALL/bin:$PATH"

export PATH="$CARGO_HOME/bin:$PATH"

if [[ -z "$OMARCHY_PATH" ]]; then
    if [[ -d /usr/share/omarchy ]]; then
        export OMARCHY_PATH=/usr/share/omarchy
    else
        export OMARCHY_PATH="$XDG_DATA_HOME/omarchy"
    fi
fi
export SUDO_EDITOR="$EDITOR"
export BAT_THEME=ansi
export PATH="$PATH:$HOME/.local/bin"
[[ -d "$OMARCHY_PATH/bin" ]] && export PATH="$OMARCHY_PATH/bin:$PATH"

# AI settings. Model names and on/off switches only -- public strings, safe to
# commit, and the same on every machine. The key that talks to these models is
# not here; see secrets.env below.
export ANTHROPIC_MODEL="claude-opus-5"
export ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-5"
export ANTHROPIC_DEFAULT_FABLE_MODEL="claude-fable-5"
export ANTHROPIC_DEFAULT_SONNET_MODEL="Claude-Sonnet-4.8"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="Claude-Haiku-4.5"
export CLAUDE_CODE_SUBAGENT_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL}"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS=1

# Secrets and machine-local values, both outside the repo, both gitignored,
# both chmod 600, sourced last so they win over anything above.
#
#   secrets.env  real credentials only -- API keys and tokens. Created by
#                bootstrap from the template in common/setup.sh.
#   local.env    private but not secret: internal endpoints, an employer's
#                Confluence site, paths under a corporate profile. Not
#                credentials, but their *values* match ~/.config/zfiles/
#                leak-patterns, so they cannot be committed either.
#
# There used to be a third file, ~/.config/claude-code/env.sh, on the theory
# that `claude` read it too. It did not -- Claude Code takes env from
# settings.json, so the only reader was this line. Two files meant
# one provider's key was defined in both, and because the second was sourced
# last it silently won: editing it in secrets.env did nothing at all. Merged
# away 2026-09-17. If a tool ever really does read its own env file, source it
# here explicitly and say which tool -- do not add one on a hunch.
[ -f "$XDG_CONFIG_HOME/shell/secrets.env" ] && . "$XDG_CONFIG_HOME/shell/secrets.env"
[ -f "$XDG_CONFIG_HOME/shell/local.env" ] && . "$XDG_CONFIG_HOME/shell/local.env"

export UV_NATIVE_TLS=1
export FZF_DEFAULT_OPTS="--layout=reverse --height 40%"
export LESS=-R
export LESS_TERMCAP_mb="$(printf '%b' '[1;31m')"
export LESS_TERMCAP_md="$(printf '%b' '[1;36m')"
export LESS_TERMCAP_me="$(printf '%b' '[0m')"
export LESS_TERMCAP_so="$(printf '%b' '[01;44;33m')"
export LESS_TERMCAP_se="$(printf '%b' '[0m')"
export LESS_TERMCAP_us="$(printf '%b' '[1;32m')"
export LESS_TERMCAP_ue="$(printf '%b' '[0m')"
export LESSOPEN="| /usr/bin/highlight -O ansi %s 2>/dev/null"
