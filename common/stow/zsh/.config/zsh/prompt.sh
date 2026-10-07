
source "$HOME/.config/shell/git-prompt.sh"

source "$HOME/.config/shell/palette.sh"

function prompt-length() {
  emulate -L zsh
  local COLUMNS=${2:-$COLUMNS}
  local -i x y=$#1 m
  if (( y )); then
    while (( ${${(%):-$1%$y(l.1.0)}[-1]} )); do
      x=y
      (( y *= 2 ));
    done
    local xy
    while (( y > x + 1 )); do
      m=$(( x + (y - x) / 2 ))
      typeset ${${(%):-$1%$m(l.x.y)}[-1]}=$m
    done
  fi
  echo $x
}

function fill-line() {
  emulate -L zsh
  local left_len=$(prompt-length $1)
  local right_len=$(prompt-length $2 9999)
  local pad_len=$((COLUMNS - left_len - right_len - ${ZLE_RPROMPT_INDENT:-1}))
  if (( pad_len < 1 )); then
    echo -E - ${1}
  else
    local pad=${(pl.$pad_len.. .)}  # pad_len spaces
    echo -E - ${1}${pad}${2}
  fi
}
function set-prompt() {
  emulate -L zsh

  setopt prompt_subst
  autoload -Uz vcs_info
  zstyle ':vcs_info:*' actionformats \
      "%F{$ZF_PROMPT_GROUP}(%f%s%F{$ZF_PROMPT_GROUP})%F{$ZF_PROMPT_JOIN}-%F{$ZF_PROMPT_GROUP}[%F{$ZF_PROMPT_VALUE}br:%b%F{$ZF_PROMPT_JOIN}|%F{$ZF_PROMPT_ALERT}%a%F{$ZF_PROMPT_GROUP}]%f"
  zstyle ':vcs_info:*' formats       \
      "%F{$ZF_PROMPT_GROUP}(%f%s%F{$ZF_PROMPT_GROUP})%F{$ZF_PROMPT_JOIN}-%F{$ZF_PROMPT_GROUP}[%F{$ZF_PROMPT_VALUE}br:%b%F{$ZF_PROMPT_GROUP}]%f"
  zstyle ':vcs_info:(sv[nk]|bzr):*' branchformat "%b%F{$ZF_PROMPT_ALERT}:%F{$ZF_PROMPT_JOIN}%r"
  zstyle ':vcs_info:*' enable git
  precmd() { vcs_info }

  if [ ! -z "$CONDA_DEFAULT_ENV" ]
  then
    local top_left="%B%F{$ZF_PROMPT_ENV}($CONDA_DEFAULT_ENV)%f %F{$ZF_PROMPT_BRACKET}[%f%F{$ZF_PROMPT_USER}%n%f%F{$ZF_PROMPT_AT}@%f%F{$ZF_PROMPT_HOST}${ZF_HOST} %f%F{$ZF_PROMPT_DIR}%1d%f%F{$ZF_PROMPT_BRACKET}]%f%b"
  else
      local top_left="%B%F{$ZF_PROMPT_BRACKET}[%f%F{$ZF_PROMPT_USER}%n%f%F{$ZF_PROMPT_AT}@%f%F{$ZF_PROMPT_HOST}${ZF_HOST} %f%F{$ZF_PROMPT_DIR}%1d%f%F{$ZF_PROMPT_BRACKET}]%f%b"
  fi

  local gh_group=""
  local gh_account="$(__gh_ps1)"
  if [[ -n $gh_account ]]; then
    gh_group="%F{$ZF_PROMPT_JOIN}-%F{$ZF_PROMPT_GROUP}[%F{$ZF_PROMPT_VALUE}gh:${gh_account}%F{$ZF_PROMPT_GROUP}]%f"
    [[ -z ${vcs_info_msg_0_} ]] && gh_group="%F{$ZF_PROMPT_GROUP}(%fgit%F{$ZF_PROMPT_GROUP})${gh_group}"
  fi

  local right_info="${vcs_info_msg_0_}${gh_group}"
  local top_right="%B${right_info:+${right_info} }%b"
  local bottom_left="%B%F{$ZF_PROMPT_ARROW}%{➜ %2G%}%f%b" 
  local bottom_right=""

  PROMPT="$(fill-line "$top_left" "$top_right")"$'\n'$bottom_left
  RPROMPT=$bottom_right
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd set-prompt
setopt noprompt{bang,subst} prompt{cr,percent,sp}
