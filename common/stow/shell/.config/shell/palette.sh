# Prompt palette — one definition, three consumers.
#
# Consumers:
#   zsh  ~/.config/zsh/prompt.sh                       uses %F{$ZF_PROMPT_*}
#   bash ~/.config/bash/prompt.sh                      uses \e[3${ZF_PROMPT_*}m
#   pi   ~/.config/pi/agent/extensions/statusline.ts   parses this file
#
# Values are ANSI palette indices 0-7, which is the one representation all
# three can consume: zsh takes the bare number in %F{n}, bash and the pi
# footer add 30 for a foreground SGR. Staying on the palette (rather than hex)
# is deliberate — it means the prompt follows the terminal colorscheme.
#
# This file is sourced by shells, so it must stay POSIX: NAME=value lines only,
# no arrays, no expansions. The pi extension parses it with a line regex and
# falls back to these same values if the file is missing, so keep the two in
# sync when adding a role.
#
# Roles are named for their job in the prompt, not their color, so a re-theme
# is a change here and nowhere else.

# Left block: [user@host dir] in zsh/bash, [model dir] in the pi footer.
ZF_PROMPT_BRACKET=1   # the enclosing [ ]
ZF_PROMPT_USER=3      # %n / the model id
ZF_PROMPT_AT=2        # the literal @
ZF_PROMPT_HOST=4      # %M / the provider
ZF_PROMPT_DIR=5       # %1d / the working directory

# Right block: (git)-[br:main]-[gh:acct], (pi)-[ctx:87%]
ZF_PROMPT_GROUP=5     # the ( ) and [ ] delimiters
ZF_PROMPT_JOIN=3      # the - joining one group to the next
ZF_PROMPT_VALUE=2     # br:main, gh:acct, ctx:87%
ZF_PROMPT_ALERT=1     # vcs action state (rebase/merge) and the svn/bzr : separator

# Standalone bits.
ZF_PROMPT_ENV=6       # (conda-env) marker
ZF_PROMPT_ARROW=4     # the second-line ➜

# Context-pressure states for the pi footer's ctx readout. No shell consumer.
ZF_PROMPT_CTX_OK=2
ZF_PROMPT_CTX_WARN=3
ZF_PROMPT_CTX_CRIT=1
