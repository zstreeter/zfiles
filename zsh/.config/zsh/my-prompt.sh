#/usr/bin/env bash

# Usage: prompt-length TEXT [COLUMNS]
#
# If you run `print -P TEXT`, how many characters will be printed
# on the last line?
#
# Or, equivalently, if you set PROMPT=TEXT with prompt_subst
# option unset, on which column will the cursor be?
#
# The second argument specifies terminal width. Defaults to the
# real terminal width.
#
# Assumes that `%{%}` and `%G` don't lie.
#
# Examples:
#
#   prompt-length ''            => 0
#   prompt-length 'abc'         => 3
#   prompt-length $'abc\nxy'    => 2
#   prompt-length '❎'          => 2
#   prompt-length $'\t'         => 8
#   prompt-length $'\u274E'     => 2
#   prompt-length '%F{red}abc'  => 3
#   prompt-length $'%{a\b%Gb%}' => 1
#   prompt-length '%D'          => 8
#   prompt-length '%1(l..ab)'   => 2
#   prompt-length '%(!.a.)'     => 1 if root, 0 if not
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

# Usage: fill-line LEFT RIGHT
#
# Prints LEFT<spaces>RIGHT with enough spaces in the middle
# to fill a terminal line.
function fill-line() {
  emulate -L zsh
  local left_len=$(prompt-length $1)
  local right_len=$(prompt-length $2 9999)
  local pad_len=$((COLUMNS - left_len - right_len - ${ZLE_RPROMPT_INDENT:-1}))
  if (( pad_len < 1 )); then
    # Not enough space for the right part. Drop it.
    echo -E - ${1}
  else
    local pad=${(pl.$pad_len.. .)}  # pad_len spaces
    echo -E - ${1}${pad}${2}
  fi
}
# Sets PROMPT and RPROMPT.
#
# Requires: prompt_percent and no_prompt_subst.
function set-prompt() {
  emulate -L zsh

  # git info
  source "$HOME/.config/zsh/git-prompt.sh"
  setopt prompt_subst
  autoload -Uz vcs_info
  zstyle ':vcs_info:*' actionformats \
      '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{3}|%F{1}%a%F{5}]%f '
  zstyle ':vcs_info:*' formats       \
      '%F{5}(%f%s%F{5})%F{3}-%F{5}[%F{2}%b%F{5}]%f '
  zstyle ':vcs_info:(sv[nk]|bzr):*' branchformat '%b%F{1}:%F{3}%r'
  zstyle ':vcs_info:*' enable git
  precmd() { vcs_info }

  # Add conda environment to prompt
  if [ ! -z "$CONDA_DEFAULT_ENV" ]
  then
    local top_left="%B%F{cyan}($CONDA_DEFAULT_ENV)%f %F{red}[%f%F{yellow}%n%f%F{green}@%f%F{blue}%M %f%F{magenta}%1d%f%F{red}]%f%b"
  else
      local top_left='%B%F{red}[%f%F{yellow}%n%f%F{green}@%f%F{blue}%M %f%F{magenta}%1d%f%F{red}]%f%b'
  fi

  local top_right="%B${vcs_info_msg_0_}%b" # Git info
  local bottom_left='%B%F{blue}%{➜ %2G%}%f%b' 
  local bottom_right=""

  PROMPT="$(fill-line "$top_left" "$top_right")"$'\n'$bottom_left
  RPROMPT=$bottom_right
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd set-prompt
setopt noprompt{bang,subst} prompt{cr,percent,sp}
