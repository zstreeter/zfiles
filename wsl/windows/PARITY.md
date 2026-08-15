# Keybinding parity: Omarchy → Windows (zfiles issue #11)

The spec the Windows configs are written from. "Caps" below is the held
Caps Lock: keyd's `overload(meta, esc)` on Omarchy, the driver-level
Caps→F13 remap + `caps.ahk`'s f14 channel on Windows (see the README's
[Caps Lock Behavior] for why F13/F14 and not Super).

Stack (decided): **AutoHotkey** (`autohotkey/caps.ahk`, kanata blocked by
Zscaler) + **GlazeWM** (`glazewm/config.yaml`) + **Zebar** (waybar stand-in)
+ **PowerToys Run** (launcher) + **WezTerm** (`wezterm/wezterm.lua`).

Every binding that is *active* on the Omarchy machine (Omarchy defaults
media/clipboard/tiling-v2/utilities + `~/.config/hypr/bindings.conf` +
`zfilesbindings.conf` overrides) appears in exactly one section.

## Mapped — same chord, same behavior

| Omarchy | Action | Windows |
|---|---|---|
| Caps+H/J/K/L | seamless focus: nvim → herdr → WM | `caps.ahk` → `herdr-navd` → GlazeWM (same walk) |
| Caps+←↓↑→ | focus window | `f14+arrows` |
| Caps+Q | close window | `caps.ahk` WinClose (deliberately not via GlazeWM) |
| Caps+W | browser, new window | `f14+w` → chrome `--new-window` |
| Caps+Return | terminal | `f14+enter` → WezTerm (opens straight into WSL) |
| Caps+Space | app launcher (walker) | `caps.ahk` → PowerToys Run |
| Caps+1..0 | switch workspace | `f14+1..0` |
| Caps+Shift+1..0 | move window to workspace | `f14+shift+1..0` (moves and follows) |
| Caps+Shift+H/J/K/L, Shift+arrows | swap/move window | `f14+shift+hjkl/arrows` → `move --direction` |
| Caps+Tab / Shift+Tab / Ctrl+Tab | next / prev / former workspace | `f14+tab` / `f14+shift+tab` / `f14+ctrl+tab` |
| Caps+Shift+Alt+arrows | move workspace to monitor | `f14+shift+alt+arrows` (+hjkl aliases) |
| Caps+`-` / `=` (±Shift) | resize window | `f14+oem_minus/oem_plus` (±shift) |
| Caps+`\` | toggle split orientation (zfiles rebind) | `f14+oem_pipe` → `toggle-tiling-direction` |
| Caps+F | fullscreen | `f14+f` |
| Caps+T | toggle floating | `f14+t` |
| Caps+Shift+A | Claude webapp | `f14+shift+a` → chrome `--app=claude.ai` |
| Caps+Shift+Alt+A | Gemini webapp | `f14+shift+alt+a` → chrome `--app` |
| Caps+Shift+E | email: nvim +Himalaya | `f14+shift+e` → WezTerm → wsl nvim +Himalaya — **see Gaps** |
| Caps+Ctrl+L | lock | `f14+ctrl+l` → `LockWorkStation` (Win+L is winlogon-reserved) |

## Substituted — different chord, Windows-native feature

| Omarchy | Action | Windows substitute |
|---|---|---|
| PRINT | screenshot | `f14+shift+s` → snipping overlay (mirrors Win+Shift+S) |
| Caps+PRINT | color picker | PowerToys Color Picker (Win+Shift+C) |
| Caps+Ctrl+PRINT | OCR text extraction | PowerToys Text Extractor (Win+Shift+T) |
| Caps+C/V/X | universal copy/paste/cut | unnecessary — Ctrl+C/V/X already universal on Windows |
| Caps+Ctrl+V | clipboard manager | Win+V (clipboard history) |
| Caps+Ctrl+E | emoji picker | Win+`.` |
| Alt+Tab | cycle windows | Windows' own Alt+Tab; plus `f14+c` (`wm-cycle-focus`) |
| Ctrl+Alt+Tab | focus other monitor | `f14+alt+1/2` (absolute) and `f14+alt+hjkl` (directional, skips terminal layers) |
| Caps+Ctrl+A/B/W | audio/bluetooth/wifi panels | Win+A quick settings |
| Caps+, family | notifications (mako) | Win+N notification center |
| Caps+Ctrl+Z | cursor zoom | Magnifier (Win+`=`) |
| Caps+Ctrl+X / F9 | dictation (voxtype) | Win+H voice typing |
| Caps+R / Caps+Shift+R | screen-record toggle (zfiles) | Game Bar (Win+Alt+R) |
| Caps+Ctrl+N | nightlight | Settings → Night light (scheduled) |
| XF86 media/brightness keys | volume/brightness/players | handled by Windows itself |
| Caps+drag (mouse move/resize) | move/resize window | GlazeWM handles tiling; floating windows use normal Windows drag |

## Dropped — explicitly absent, with reasons

| Omarchy | Why absent on Windows |
|---|---|
| Caps+G, Caps+Alt+G | window grouping — GlazeWM has no tabbed/stacked containers |
| Caps+S, Caps+Alt+S | scratchpad — no special-workspace concept |
| Caps+P | pseudo-tiling — no equivalent |
| Caps+Ctrl+F, Caps+Alt+F | tiled-fullscreen / full-width variants — `f14+f` covers the need |
| Caps+O | pop window out (float+pin) — no pin concept |
| Caps+Shift+Alt+1..0 | *silent* move to workspace — GlazeWM move is bound with follow; add plain `move --workspace N` bindings if ever missed |
| Ctrl+Alt+Delete (close all) | reserved by Windows (SAS) |
| Caps+/ | Omarchy keybindings cheat-sheet — this file is the cheat sheet |
| Caps+Backspace family | transparency/gaps/aspect toggles — Hyprland-only concepts |
| omarchy-menu family (Caps+Esc, Caps+Alt+Space, Caps+Ctrl+C/O/H, theme/background menus) | no Omarchy menu system on Windows |
| Caps+Shift+Space | toggle waybar — Zebar runs unconditionally |
| Caps+Ctrl+I, Caps+Ctrl+Delete, lid switch | idle/display/lid — corporate power policy + Windows handles the dock |
| Caps+Ctrl+S/PERIOD, reminders, time/battery/weather | omarchy-* scripts with no Windows counterpart; clock/battery live in Zebar |
| Caps+Shift+F (nautilus) | Win+E / Explorer |
| Caps+Shift+M/Alt+M (music), Shift+G/Alt+G/Ctrl+G (messengers), Shift+P (photos), Shift+Y (youtube), Shift+/ (1password) | personal apps — not for the work laptop |
| Caps+Shift+N (editor), Caps+Shift+T (btop), Caps+Shift+D (lazydocker) | run them in a WezTerm/WSL pane instead |
| Caps+Alt+Return (tmux) | stale on Omarchy too — tmux was replaced by herdr (9f0a6e6); should be unbound there, not ported |

## Windows-only — no Omarchy counterpart

| Chord | Action |
|---|---|
| `f14+m` | toggle-minimized |
| `f14+shift+r` | GlazeWM reload config |
| `f14+shift+p` | GlazeWM pause |
| `f14+shift+ctrl+e` | GlazeWM exit (deliberately awkward) |
| `f14+alt+hjkl` | focus straight to WM, skipping nvim/herdr arbitration |

## Known gaps

- **Caps+Shift+E launches `nvim +Himalaya`, but himalaya is not in
  `wsl/pkglist.txt`** — email was excluded from the WSL target at charting.
  Either the binding goes, or himalaya gets installed after all. Until
  decided, the chord opens nvim with a failing plugin. (Tracked on the map.)
- WezTerm nightly (needed for kitty-graphics fixes) is a manual install —
  `install.ps1` only copies configs.
