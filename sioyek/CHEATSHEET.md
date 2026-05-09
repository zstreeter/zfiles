# Sioyek Cheat Sheet

Personal reference for sioyek, with zathura-style keybindings layered on top
via `keys_user.config`. Defaults live in `/etc/sioyek/keys.config`.

## Custom (zathura-style) bindings

| Key   | Action                  | Sioyek command            |
|-------|-------------------------|---------------------------|
| `J`   | Zoom out                | `zoom_out`                |
| `K`   | Zoom in                 | `zoom_in`                 |
| `h`   | Previous page           | `previous_page`           |
| `l`   | Next page               | `next_page`               |
| `j`   | Scroll down (1 screen)  | `screen_down`             |
| `k`   | Scroll up (1 screen)    | `screen_up`               |
| `a`   | Best-fit (smart width)  | `fit_to_page_width_smart` |
| `s`   | Fit width               | `fit_to_page_width`       |
| `i`   | Toggle dark / invert    | `toggle_dark_mode`        |

These overrides displace some sioyek defaults — see "What we gave up" below.

## Sioyek defaults that already match zathura

| Key     | Action                          |
|---------|---------------------------------|
| `+`     | Zoom in                         |
| `-`     | Zoom out                        |
| `=`     | Fit to page width               |
| `gg`    | Go to first page                |
| `G`     | Go to last page                 |
| `r`     | Rotate clockwise                |
| `R`     | Rotate counter-clockwise        |
| `t`     | Table of contents               |
| `/`     | Search forward                  |
| `n`     | Next search result              |
| `N`     | Previous search result          |
| `o`     | Open document                   |
| `<C-o>` | Open embedded document          |
| `<f8>`  | Toggle dark mode (also via `i`) |

## Sioyek superpowers (no zathura equivalent)

| Key      | Action                                             |
|----------|----------------------------------------------------|
| `f`      | Smart jump under cursor (follow ref/link/citation) |
| `<C-]>`  | Goto definition                                    |
| `<tab>`  | Goto portal (jump-back point)                      |
| `gp`     | Goto portal                                        |
| `gb`/`gB`| Goto bookmark                                      |
| `gh`/`gH`| Goto highlight                                     |
| `gnh`    | Goto next highlight                                |
| `gNh`    | Goto previous highlight                            |
| `^`      | Goto left smart (column-aware)                     |
| `$`      | Goto right smart                                   |
| `gC`     | Previous chapter                                   |
| `<bs>`   | Previous state (history back)                      |
| `<C-f>`  | Search (alternative to `/`)                        |
| `<f9>`   | Fit to page width                                  |
| `<f10>`  | Fit to page width smart                            |

`f` (smart jump) is sioyek's killer feature — hover a citation/reference and
hit `f` to jump to it. `<bs>` (Backspace) jumps back. Worth learning.

## What we gave up

The custom rebinds replace these sioyek defaults:

| Key | Was                       | Now                  | Workaround                       |
|-----|---------------------------|----------------------|----------------------------------|
| `h` | `add_highlight`           | `previous_page`      | Use the menu / select-then-mouse |
| `l` | `overview_definition`     | `next_page`          | Use `<C-]>` for goto_definition  |
| `j` | `move_visual_mark_down`   | `screen_down`        | Use `<down>` arrow               |
| `k` | `move_visual_mark_up`     | `screen_up`          | Use `<up>` arrow                 |

If `add_highlight` matters to you, rebind it to a different key in
`keys_user.config` (e.g. `add_highlight H`).

## Modifier syntax (for editing keys_user.config)

- Plain letter: `a`
- Capital (= shift+letter): `A` or `<S-a>`
- Control: `<C-a>`
- Alt: `<A-a>`
- Combined: `<C-S-a>`
- Special keys: `<space>`, `<tab>`, `<backspace>`, `<up>`, `<down>`, `<left>`, `<right>`, `<home>`, `<end>`, `<pageup>`, `<pagedown>`, `<f1>`...`<f12>`

Sequences: just concatenate, e.g. `gg` for "press g twice."

## Reloading

Sioyek does **not** hot-reload its config. After editing `keys_user.config`
or `prefs_user.config`, fully quit and relaunch sioyek.

## Files

- `~/.config/sioyek/keys_user.config` — symlink to `zfiles/sioyek/.config/sioyek/keys_user.config` (this overlay)
- `~/.config/sioyek/prefs_user.config` — symlink to `~/.config/omarchy/current/theme/sioyek-prefs.config` (rendered per-theme by the omarchy hook)
- `/etc/sioyek/keys.config` — system defaults (read-only reference)
- `/etc/sioyek/prefs.config` — system pref defaults (read-only reference)
