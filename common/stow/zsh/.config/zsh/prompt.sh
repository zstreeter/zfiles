#/usr/bin/env bash

# __git_ps1 (unused here -- vcs_info covers the branch) and __gh_ps1, which the
# right side does use. Sourced once at load rather than from inside set-prompt
# so 650 lines aren't re-read on every prompt and __gh_ps1's cache survives.
source "$HOME/.config/shell/git-prompt.sh"

# Prompt colors. Shared with bash's prompt and the pi statusline so a re-theme
# is one edit; see the role table in palette.sh.
source "$HOME/.config/shell/palette.sh"

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
  setopt prompt_subst
  autoload -Uz vcs_info
  # No trailing space in the formats — the gh group is appended after these,
  # and the space that keeps the block off the right edge goes on last.
  zstyle ':vcs_info:*' actionformats \
      "%F{$ZF_PROMPT_GROUP}(%f%s%F{$ZF_PROMPT_GROUP})%F{$ZF_PROMPT_JOIN}-%F{$ZF_PROMPT_GROUP}[%F{$ZF_PROMPT_VALUE}br:%b%F{$ZF_PROMPT_JOIN}|%F{$ZF_PROMPT_ALERT}%a%F{$ZF_PROMPT_GROUP}]%f"
  zstyle ':vcs_info:*' formats       \
      "%F{$ZF_PROMPT_GROUP}(%f%s%F{$ZF_PROMPT_GROUP})%F{$ZF_PROMPT_JOIN}-%F{$ZF_PROMPT_GROUP}[%F{$ZF_PROMPT_VALUE}br:%b%F{$ZF_PROMPT_GROUP}]%f"
  zstyle ':vcs_info:(sv[nk]|bzr):*' branchformat "%b%F{$ZF_PROMPT_ALERT}:%F{$ZF_PROMPT_JOIN}%r"
  zstyle ':vcs_info:*' enable git
  precmd() { vcs_info }

  # Add conda environment to prompt
  if [ ! -z "$CONDA_DEFAULT_ENV" ]
  then
    local top_left="%B%F{$ZF_PROMPT_ENV}($CONDA_DEFAULT_ENV)%f %F{$ZF_PROMPT_BRACKET}[%f%F{$ZF_PROMPT_USER}%n%f%F{$ZF_PROMPT_AT}@%f%F{$ZF_PROMPT_HOST}%M %f%F{$ZF_PROMPT_DIR}%1d%f%F{$ZF_PROMPT_BRACKET}]%f%b"
  else
      local top_left="%B%F{$ZF_PROMPT_BRACKET}[%f%F{$ZF_PROMPT_USER}%n%f%F{$ZF_PROMPT_AT}@%f%F{$ZF_PROMPT_HOST}%M %f%F{$ZF_PROMPT_DIR}%1d%f%F{$ZF_PROMPT_BRACKET}]%f%b"
  fi

  # Git info, plus the gh account hanging off the same (git) opener. Outside a
  # repo vcs_info is empty, so open the block here to get (git)-[gh:account].
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
