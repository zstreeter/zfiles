# Bash port of zsh prompt.sh: two lines, left = (conda) [user@host dir],
# right = (git)-[br:branch|state]-[gh:account] right-aligned, second line = ➜.
# Git info comes from the same contrib git-prompt.sh zsh uses.

source "$HOME/.config/shell/git-prompt.sh"

# Prompt colors. Shared with the zsh prompt and the pi statusline so a re-theme
# is one edit; see the role table in palette.sh.
source "$HOME/.config/shell/palette.sh"

__zfiles_prompt() {
    # Route GH_CONFIG_DIR before anything reads the account back. Called from
    # here rather than prepended to PROMPT_COMMAND in git-prompt.sh, because the
    # assignment at the bottom of this file would overwrite that. It is a no-op
    # unless the directory changed. zsh uses a real chpwd hook instead.
    command -v __gh_chpwd >/dev/null 2>&1 && __gh_chpwd

    # c_* are prompt roles, not colors; the mapping lives in palette.sh.
    local reset='\[\e[0m\]' bold='\[\e[1m\]'
    local c_bracket="\[\e[3${ZF_PROMPT_BRACKET}m\]" c_user="\[\e[3${ZF_PROMPT_USER}m\]"
    local c_at="\[\e[3${ZF_PROMPT_AT}m\]"           c_host="\[\e[3${ZF_PROMPT_HOST}m\]"
    local c_dir="\[\e[3${ZF_PROMPT_DIR}m\]"         c_group="\[\e[3${ZF_PROMPT_GROUP}m\]"
    local c_join="\[\e[3${ZF_PROMPT_JOIN}m\]"       c_value="\[\e[3${ZF_PROMPT_VALUE}m\]"
    local c_env="\[\e[3${ZF_PROMPT_ENV}m\]"         c_arrow="\[\e[3${ZF_PROMPT_ARROW}m\]"

    local dir=${PWD##*/}
    [[ $PWD == "$HOME" ]] && dir='~'

    # Plain-text copies measure the visible width for padding.
    local conda_plain='' conda=''
    if [[ -n ${CONDA_DEFAULT_ENV-} ]]; then
        conda_plain="(${CONDA_DEFAULT_ENV}) "
        conda="${bold}${c_env}(${CONDA_DEFAULT_ENV})${reset} "
    fi
    local left_plain="${conda_plain}[${USER}@${HOSTNAME} ${dir}]"
    local left="${conda}${bold}${c_bracket}[${c_user}${USER}${c_at}@${c_host}${HOSTNAME} ${c_dir}${dir}${c_bracket}]${reset}"

    # Both bracket groups hang off one (git) opener, so outside a repo the
    # account still shows as (git)-[gh:account].
    local branch account
    branch=$(__git_ps1 '%s')
    account=$(__gh_ps1)

    local groups_plain='' groups=''
    if [[ -n $branch ]]; then
        groups_plain+="-[br:${branch}]"
        groups+="${c_join}-${c_group}[${c_value}br:${branch}${c_group}]"
    fi
    if [[ -n $account ]]; then
        groups_plain+="-[gh:${account}]"
        groups+="${c_join}-${c_group}[${c_value}gh:${account}${c_group}]"
    fi

    local right_plain='' right=''
    if [[ -n $groups_plain ]]; then
        right_plain="(git)${groups_plain}"
        right="${bold}${c_group}(${reset}${bold}git${c_group})${groups}${reset}"
    fi

    local cols=${COLUMNS:-80}
    local pad=$(( cols - ${#left_plain} - ${#right_plain} - 1 ))
    if (( pad < 1 )); then
        PS1="${left}\n${bold}${c_arrow}➜ ${reset}"
    else
        PS1="${left}$(printf '%*s' "$pad" '')${right}\n${bold}${c_arrow}➜ ${reset}"
    fi
}
PROMPT_COMMAND=__zfiles_prompt
