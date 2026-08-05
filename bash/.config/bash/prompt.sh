# Bash port of zsh my-prompt.sh: two lines, left = (conda) [user@host dir],
# right = (git)-[branch|state] right-aligned, second line = ➜.
# Git info comes from the same contrib git-prompt.sh zsh uses.

source "$HOME/.config/zsh/git-prompt.sh"

__zfiles_prompt() {
    local reset='\[\e[0m\]' bold='\[\e[1m\]'
    local red='\[\e[31m\]' green='\[\e[32m\]' yellow='\[\e[33m\]'
    local blue='\[\e[34m\]' magenta='\[\e[35m\]' cyan='\[\e[36m\]'

    local dir=${PWD##*/}
    [[ $PWD == "$HOME" ]] && dir='~'

    # Plain-text copies measure the visible width for padding.
    local conda_plain='' conda=''
    if [[ -n ${CONDA_DEFAULT_ENV-} ]]; then
        conda_plain="(${CONDA_DEFAULT_ENV}) "
        conda="${bold}${cyan}(${CONDA_DEFAULT_ENV})${reset} "
    fi
    local left_plain="${conda_plain}[${USER}@${HOSTNAME} ${dir}]"
    local left="${conda}${bold}${red}[${yellow}${USER}${green}@${blue}${HOSTNAME} ${magenta}${dir}${red}]${reset}"

    local branch
    branch=$(__git_ps1 '%s')
    local right_plain='' right=''
    if [[ -n $branch ]]; then
        right_plain="(git)-[${branch}]"
        right="${bold}${magenta}(${reset}${bold}git${magenta})${yellow}-${magenta}[${green}${branch}${magenta}]${reset}"
    fi

    local cols=${COLUMNS:-80}
    local pad=$(( cols - ${#left_plain} - ${#right_plain} - 1 ))
    if (( pad < 1 )); then
        PS1="${left}\n${bold}${blue}➜ ${reset}"
    else
        PS1="${left}$(printf '%*s' "$pad" '')${right}\n${bold}${blue}➜ ${reset}"
    fi
}
PROMPT_COMMAND=__zfiles_prompt
