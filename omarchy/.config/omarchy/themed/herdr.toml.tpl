# herdr config — rendered by Omarchy's template engine on every theme switch.
# Source: omarchy/.config/omarchy/themed/herdr.toml.tpl (zfiles)
# Rendered to: ~/.config/omarchy/current/theme/herdr.toml
# Live config symlinks here (see bootstrap.sh §13); hooks/theme-set hot-reloads
# a running herdr. Colors below track the active Omarchy palette.
#
# Translated from the old ~/.config/tmux/tmux.conf. Key names follow herdr's
# docs — verify against `herdr --default-config` and adjust if any differ.

[keys]
prefix = "ctrl+a"               # tmux: set -g prefix C-a

split_vertical   = "prefix+v"   # tmux: bind v split-window -h (side by side)
split_horizontal = "prefix+s"   # tmux: bind s split-window -v (stacked)
close_pane       = "prefix+x"

# Prefix+hjkl still works inside herdr, but SUPER+hjkl (Hyprland binding ->
# scripts/herdr-nav) is the seamless path: nvim splits -> herdr panes -> windows.
focus_pane_left  = "prefix+h"
focus_pane_down  = "prefix+j"
focus_pane_up    = "prefix+k"
focus_pane_right = "prefix+l"

zoom        = "prefix+f"        # fullscreen the focused pane (tmux: bind f)
resize_mode = "prefix+r"        # herdr default; resize mode, then hjkl to nudge
copy_mode   = "prefix+space"    # tmux: bind Space copy-mode

# Launch-in-pane commands (temp pane, closes when the command exits).
# prefix+y avoids the zsh ^o run_yazi binding (cwd-on-exit) — different job:
# this browses in a scratch pane, ^o still cd's the shell.
[[keys.command]]
key     = "prefix+y"
type    = "pane"
command = "yazi"

# himalaya-tui: the official Pimalaya mail TUI (shares himalaya's config).
[[keys.command]]
key     = "prefix+m"
type    = "pane"
command = "himalaya-tui"

[ui]
pane_borders = false            # zen: no boxes around split panes
pane_gaps    = false            # zen: no spacing between panes

[ui.sound]
enabled = false                 # no bell on agent state change

# Theme tracks Omarchy. panel_bg reset lets the terminal/Omarchy bg show
# through (matches your old `status-style bg=default`).
[theme.custom]
panel_bg = "reset"
accent   = "{{ accent }}"
green    = "{{ color2 }}"       # herdr "done"
blue     = "{{ color4 }}"       # herdr accent/info
red      = "{{ color1 }}"       # herdr "blocked"
yellow   = "{{ color3 }}"       # herdr "working"
