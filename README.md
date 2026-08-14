# ZFiles

Personal dotfiles. Primarily an overlay for
[Omarchy](https://github.com/basecamp/omarchy) — adding zsh, custom keybindings,
and additional tools — but the same `bootstrap.sh` also targets WSL, plain
Linux, and root-less work servers. See [Targets](#targets).

## What This Does

This overlay extends Omarchy with:

- **Zsh** - Shell configuration (Omarchy uses bash by default)
- **Keyd** - Caps Lock → Escape (tap) / Super (hold)
- **Hyprland bindings** - Custom keybindings layered on top of Omarchy's defaults
- **Theme integration** - herdr, Sioyek and Yazi follow Omarchy's theme automatically
- **Neovim** - Personal config synced with Omarchy themes
- **Additional tools** - herdr, yazi, sioyek, cura

## Installation

```bash
git clone https://github.com/zstreeter/zfiles.git ~/zfiles
cd ~/zfiles
chmod +x bootstrap.sh
./bootstrap.sh
```

Reboot after installation for keyd to take effect.

### Targets

`bootstrap.sh` gates every step on four orthogonal facts:

- **Remote** (`--remote` flag or `ZFILES_TARGET=remote`) — the only one that
  can't be sniffed, so it's explicit. A work server you `ssh` into from a herdr
  pane. Installs **only** the bash prompt, yazi, and neovim, entirely under
  `$HOME`: **never sudo, never a package manager, never `chsh`**. See
  [Remote servers](#remote-servers) below.
- **Omarchy** (`~/.config/omarchy/` or `~/.local/share/omarchy/` exists) —
  full overlay: core + Hyprland bindings, keyd, theme hooks, himalaya/mirador,
  cura/sioyek/xdg/wireplumber, docker.
- **WSL** (`/proc/version` mentions Microsoft) — core packages via apt + mise
  (`pkglist-ubuntu.txt`; neovim/yazi/go/rust/bun/opencode via mise since noble
  is stale or missing them) and pinentry-curses, plus `sioyek`/`xdg` so PDFs
  open in sioyek under WSLg. The Windows side runs from `windows/install.ps1`
  (bootstrap step 15) — see [The Windows side](#the-windows-side).
- **Package manager** (pacman vs apt) — picks the install branch in step 1.
  Forced to `none` on remote.

Core packages on every target:

| Package    | Purpose                            |
|------------|------------------------------------|
| `shell`    | Shell-agnostic config sourced by **both** zsh and bash: `env.sh`, `aliases.sh`, `commands.sh`, `git-prompt.sh` |
| `zsh`      | zsh-only bits (`.zshrc`, prompt, zap plugins) |
| `bash`     | bash-only bits (`rc.sh`, prompt) — see [The bash hook](#the-bash-hook) |
| `yazi`     | File manager                       |
| `herdr`    | Terminal workspace manager + `herdr-navd` (WSL only; see [Seamless navigation](#seamless-navigation)) |
| `opencode` | opencode agent config              |
| `pi`       | pi agent config                    |
| `scripts`  | `new-research-project`, `publish-post` helpers + vault template |

Skipped without Omarchy: Hyprland source, keyd, theme-set hook,
mirador/himalaya email tools, docker, and the desktop/hardware packages
(cura, wireplumber). `sioyek` and `xdg` are also stowed on WSL — the theme-set
hook is Omarchy-only, so sioyek falls back to a static `prefs_user.config`
there.

Remote gets `shell`, `bash`, and `yazi` only — no zsh, no herdr, no pi, no
desktop anything.

### Remote servers

The workflow is: herdr runs on the local machine, one pane holds an `ssh`
session to a work server. Those are bash terminals with no root. One line gets
zfiles' bash prompt, yazi, and neovim onto that server:

```bash
curl -fsSL https://raw.githubusercontent.com/zstreeter/zfiles/main/remote/install.sh | sh
```

What it does:

1. Blobless **sparse** clone of only `shell bash yazi remote` into `~/.zfiles`
   (falls back to a shallow full clone on git < 2.25 — still small).
2. `exec ~/.zfiles/bootstrap.sh --remote`, which:
   - appends a guarded hook to `~/.bashrc` (never replaces it),
   - installs `neovim yazi fd ripgrep fzf zoxide bat eza` via **mise** into
     `~/.local` — no root, nothing touched outside `$HOME`,
   - stows `shell bash yazi`, clones the neovim config, installs yazi plugins
     and the Catppuccin Mocha flavor.

Nothing herdr-related ships to the server; herdr stays local and the server is
just what's running inside one of its panes.

To re-run later, `zfiles-update` (defined in `shell/commands.sh`) pulls and
re-bootstraps whichever checkout it finds.

### The bash hook

`~/.bashrc` is **appended to, not replaced**. Bootstrap adds an idempotent
block:

```sh
# >>> zfiles >>>
[ -f "$HOME/.config/bash/rc.sh" ] && . "$HOME/.config/bash/rc.sh"
# <<< zfiles <<<
```

so a server's site setup (lmod, `module`, conda init) survives untouched, and
`stow --adopt` can never swallow a pre-existing `~/.bashrc` into the repo. If
the login chain (`.bash_profile` → `.bash_login` → `.profile`) doesn't already
reach `~/.bashrc`, bootstrap wires that up too. Anything it overwrites or
displaces first lands in `~/.local/state/zfiles/backup/`.

### À la carte stowing

Each package directory is independent. To install just one:

```bash
cd ~/zfiles
stow --target=$HOME sioyek      # symlinks .config/sioyek/ into $HOME
stow --target=$HOME zsh         # etc.
```

Bootstrap is just the orchestrator — `stow` itself is per-package.

## Structure

```
zfiles/
├── bootstrap.sh          # Main installer (--remote for servers)
├── pkglist.txt           # Packages to install
├── remote/
│   └── install.sh        # curl-able entry point for work servers
├── hooks/
│   └── theme-set         # Generates theme configs when Omarchy theme changes
├── root_etc/
│   └── keyd/
│       └── default.conf  # Caps Lock remapping
├── hypr/                 # Hyprland custom bindings
├── yazi/                 # File manager config
├── sioyek/               # PDF viewer config
├── shell/                # Shell-agnostic config (zsh + bash both source it)
├── zsh/                  # zsh-only config
├── bash/                 # bash-only config (rc.sh, prompt.sh)
├── herdr/                # Terminal workspace manager + herdr-navd (WSL)
├── wsl/                  # Linux→Windows routing layer (winapp)
├── windows/              # WSL host-side configs + install.ps1 (bootstrap §15)
└── cura/                 # 3D printing slicer config
```

## Customization

### Hyprland Keybindings

Edit `hypr/.config/hypr/zfilesbindings.conf` to add your own bindings:

```bash
# Example: Vim-style window focus
bindd = SUPER, H, Focus left, movefocus, l
bindd = SUPER, J, Focus down, movefocus, d
bindd = SUPER, K, Focus up, movefocus, u
bindd = SUPER, L, Focus right, movefocus, r
```

These are loaded after Omarchy's defaults, so you can override or extend them.

### Caps Lock Behavior

The keyd config (`root_etc/keyd/default.conf`) maps Caps Lock to:
- **Tap** → Escape
- **Hold** → Super (for Hyprland bindings)

On WSL the same remap has to happen on the Windows host — WSL2 has no
`/dev/input`, so keyd can never see the keyboard. `windows/autohotkey/caps.ahk`
reproduces it, with one difference: **hold → `F14`, not Super**. Windows itself
owns a large slice of Super (Win+E, Win+R, Win+number, the Start menu on bare
press), so Caps-as-Super collides constantly. `F14` is a private channel — no
physical key emits it, nothing binds it, and it carries no modifier semantics
that could leak into an app. GlazeWM can still match on it because its
keybinding matcher tests whether *any* listed key is held, not just real
modifiers. So `f14+h` in `windows/glazewm/config.yaml` is what `SUPER+H` is on
Omarchy. See [The Windows side](#the-windows-side).

**The intent is that there is no Caps Lock key.** `install.ps1` writes a
`Scancode Map` to `HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout`
turning scancode `0x3A` into `0x64` (F13) in the keyboard driver, so Windows
would never see a Caps Lock key and the lock state could not latch. This is not
tidiness: `caps.ahk` used to hold the lock off from userspace with
`SetCapsLockState "AlwaysOff"`, which leaves a hole exactly the width of the
process not running — during logon before the task fires, and during every
restart after an edit to the script — and one press in that window latched it
for real. A driver remap would hold whether or not AutoHotkey is up. It needs
elevation (one UAC prompt, only on the run that changes something) and a reboot
to load, so `caps.ahk` hooks `CapsLock` alongside `F13` as a bridge.

> **Known bug on the current laptop: the remap is not taking effect.** The
> value is byte-correct (`3A 00 64 00`), was written at 09:38 and the machine
> booted at 09:59, `kbdclass` is the only keyboard filter driver — and an
> AutoHotkey `InputHook` still logs the physical key as `CapsLock`, never as
> `F13`. So the lock can still latch, and the bridge hooks are load-bearing
> rather than transitional. Under diagnosis; the keyboard is a USB device
> (`VID_29EA`) rather than the laptop's built-in one, which is the next thing
> to rule out.

F13 in the driver, F14 out of the script, and they have to differ: GlazeWM
installs its own low-level keyboard hook, hook order between two
logon-started processes is not pinnable, and a *physical* F14 that reached
GlazeWM before `caps.ahk` suppressed it would fire every binding twice.
Nothing is bound to `f13`, so the physical key is inert to the WM.

### The Windows side

Bootstrap step 15 runs `windows/install.ps1` on the WSL target. It is
idempotent — bootstrap re-runs it every time, and it only acts on what differs.

| component | state |
|-----------|-------|
| Caps Lock | working, via AutoHotkey — `windows/autohotkey/caps.ahk`, on a driver-level Caps→F13 remap |
| WezTerm   | working — `windows/wezterm/wezterm.lua` is the source of truth |
| GlazeWM   | configured — `windows/glazewm/config.yaml`, mapped from Omarchy's Hyprland bindings |
| Navigation | `herdr-navd` — nvim splits → herdr panes → GlazeWM windows |
| sioyek    | Windows build via winget, configs in `windows/sioyek/` — see below |

#### GUI programs are the Windows build

**Rule for this target: anything with a window is installed as the Windows
program, and the Linux side routes to it.** WSL entry points keep their Linux
names — `sioyek foo.pdf` in a shell, yazi's openers, `xdg-open` — and
`wsl/.local/bin/winapp` finds the `.exe` and re-runs it with every path
argument translated through `wslpath -w`.

The alternative is WSLg, and it does not work with a tiling window manager.
WSLg publishes Linux GUI apps to Windows over RDP RemoteApp, so each one
arrives at the Windows compositor as a `RAIL_WINDOW` owned by `msrdc.exe`, the
Remote Desktop client. Measured on GlazeWM 3.10.1:

- `glazewm query windows` reports `processName: msrdc` for all of them, so a
  window rule cannot tell a PDF viewer from an image viewer.
- They arrive `fullscreen` regardless of `initial_state: tiling`, because
  GlazeWM reads the initial state off the geometry RDP hands over.
- **Nothing can close them.** Neither `glazewm command close` nor a direct
  `WM_CLOSE` does anything, so a stale RAIL window can outlive the Linux
  process that owned it. (`close` turned out to be broken for *every* window
  on this machine — see below — but RAIL windows survive `WM_CLOSE` too, which
  ordinary windows do not.)

The Windows build of the same program has none of that. Native sioyek is
`processName: sioyek`, class `Qt5152QWindowIcon`, arrives tiling, and closes.
`config.yaml` keeps a `set-tiling` rule matching `msrdc` + `RAIL_WINDOW` as a
fallback for anything still coming through WSLg.

Adding a program to this scheme is three steps: a winget install plus a
`Copy-IfChanged` for its config in `install.ps1`, a `winapp <name>.exe` branch
in whatever `~/.local/bin` wrapper already exists for it, and — if its config
format differs between targets — a file under `windows/<name>/`. sioyek is the
worked example. Note that `ahrm.sioyek` is a *portable* package: it reads its
config from the directory holding the exe, which is version-stamped, so a
sioyek upgrade starts with empty configs until the next bootstrap run.

#### Caps+Q does not go through GlazeWM

`close` is broken in GlazeWM 3.10.1 on this machine, for every window rather
than for any particular kind. `glazewm command --id <id> close` returns
`success: true` and the window is still there — Notepad, a native Qt window, a
WSLg RAIL window, all the same. It is not the keybinding channel: `f14+t` on
the same Notepad flips it to floating, so the chord arrives and only this one
command is dead.

So `caps.ahk` handles Caps+Q itself with `WinClose`, which posts the `WM_CLOSE`
that closes all of them on the first try, and `config.yaml` has no `f14+q`
binding at all. Only a *bare* Caps+Q closes; Caps+Shift+Q and friends fall
through to the f14 channel and stay inert, so there is no second, undocumented
way to close the focused window by accident.

Configs are **copied** to the Windows side, not symlinked across
`\\wsl.localhost`: the logon tasks run when the distro may not be up, and a UNC
path there would either fail or force the distro to boot just to read a config.
So editing `windows/*` takes a bootstrap re-run to reach Windows. An unmanaged
file already at the destination is backed up once to `<name>.zfiles-bak`.

Both the Caps Lock remap (`zfiles-caps`) and GlazeWM (`zfiles-glazewm`) run as
logon tasks at highest privileges, so they also apply over elevated windows and
raise no UAC prompt at logon. `caps.ahk` is syntax-checked with `/validate`
before any running instance is restarted, and only restarted when it actually
changed; a GlazeWM config change triggers `wm-reload-config` rather than a
restart, so windows stay where they are.

#### Seamless navigation

On Omarchy, `SUPER+hjkl` runs `hypr/.config/hypr/scripts/herdr-nav`, which walks
outward — nvim splits, then herdr panes, then Hyprland windows — and stops at
the first layer that can take the move. Reproducing that on WSL takes two
pieces, because the keyboard is on the Windows side and the panes and splits are
on the Linux side:

- **`hjkl` is deliberately not bound in GlazeWM.** If it were, GlazeWM's
  system-wide hook would swallow `f14+h` before WezTerm ever saw it. Instead
  `caps.ahk` arbitrates: outside the terminal it forwards to the WM as usual,
  and inside the terminal it asks the daemon first.
- **`herdr-navd`** (`herdr/.local/bin/herdr-navd`) is a small Python 3 stdlib
  daemon on `127.0.0.1:6224`, run from a stowed systemd user unit. `GET
  /nav/{left,down,up,right}` does the arbitration and replies with the layer
  that consumed the move (`nvim` / `herdr` / `wm` / `none`), which is the whole
  debugging story when a keypress does nothing. It also serves `GET /launch` —
  see [Launching onto the focused
  workspace](#launching-onto-the-focused-workspace).

It has to be resident rather than a script: reaching into WSL through interop
(`wsl.exe -- …`) measures ~290ms per invocation, unusable for focus movement.
An HTTP round trip into an already-running process measures **~6ms end to end
from Windows**, arbitration included.

Its outermost hop talks to GlazeWM's IPC server — a WebSocket on
`ws://127.0.0.1:6123` — which is why `install.ps1` sets `networkingMode=mirrored`
in `%USERPROFILE%\.wslconfig`: in WSL2's default NAT mode, `127.0.0.1` inside
the distro is not the Windows host. (The Windows → WSL direction works in either
mode, so `caps.ahk` can always reach the daemon.) That change needs a
`wsl --shutdown` to take effect. If it hasn't been applied, or the daemon is
down, `caps.ahk` falls back to sending `f14+hjkl` to GlazeWM — so Caps+hjkl
always moves *something*, it just stops seeing inside the terminal.

Python rather than a bash port of `herdr-nav` for one concrete reason: that
script leans on `jq`, which isn't installed on WSL and isn't in
`pkglist-ubuntu.txt`. The stdlib `json` module makes the gap moot instead of
adding a dependency.

#### Launching onto the focused workspace

`Caps+Space` opens PowerToys Run, Omarchy's `SUPER+SPACE`. On a multi-monitor
setup that used to put the app on the *previous* workspace whenever you launched
from an empty one — focus workspace 3 on the second screen, launch Outlook, and
it opens on workspace 1.

An empty workspace has no OS-level focus anchor. GlazeWM's focused container is
the workspace, but Windows' foreground window is still whatever was up last;
`sync_focus` can only "focus the desktop". PT Run is a tool window GlazeWM can
never manage, so it doesn't react to PT Run taking foreground — but when PT Run
closes, Windows hands foreground to the top *managed* window in the global
Z-order, which is on the other screen, and GlazeWM follows it as a manual focus
change. `should_override_focus` only covers the 100ms after a managed window
goes away, so nothing catches this. Seconds later the app appears and is
inserted next to the wrong container.

Racing that is hopeless — the race is against app start-up time, which is
unbounded. So the window is claimed instead. `caps.ahk` calls `GET /launch`
*before* sending the launcher chord, while the intended workspace is still
focused; the daemon records it and a watcher thread on GlazeWM's
`window_managed` event stream moves the next newly managed window there and
follows it. An already-running app emits no `window_managed` event, so
activating an existing window is untouched, and a claim expires after 15s so an
abandoned launcher can't capture something unrelated a minute later. Daemon
down, and `Caps+Space` is exactly the plain launcher chord it always was.

**Why AutoHotkey and not kanata.** kanata is the closer analogue to keyd, and
`windows/kanata/kanata.kbd` is kept as the reference the `.ahk` was ported from,
but nothing installs it: its only winget source is the GitHub release, and
Zscaler 403s that download (the direct URL and the `api.github.com` asset
endpoint both redirect to the same CDN; msstore doesn't carry it). Unrelated
GitHub release downloads — AutoHotkey, PowerToys — come through fine, so the
block reads as aimed at keyboard-interception tools rather than incidental.
PowerToys was the other candidate and can't do this at all: Keyboard Manager
does one-to-one remaps only, with no notion of tap versus hold.

### Theme Integration

When you change Omarchy's theme, the `theme-set` hook automatically generates configs for:
- Sioyek — appends a `# zfiles-theme` block to `~/.config/sioyek/prefs_user.config`
- Yazi — `yazi/theme.toml` always selects a flavor named `zfiles`; each target
  decides what fills `~/.config/yazi/flavors/zfiles.yazi/`. On Omarchy it's a
  symlink to the rendered theme, so yazi follows theme switches. On WSL and
  remote it's static Catppuccin Mocha (`ya pkg add yazi-rs/flavors:catppuccin-mocha`).

Sioyek's prefs_user.config is overwritten between `# zfiles-theme` markers — keep
non-color customizations above that marker.

### Neovim

The bootstrap script clones [my neovim config](https://github.com/zstreeter/nvim) and symlinks Omarchy's theme, so colorschemes stay in sync.

## Omarchy Resources

- [Omarchy GitHub](https://github.com/basecamp/omarchy)
- [Omarchy Wiki](https://github.com/basecamp/omarchy/wiki)
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [Keyd Documentation](https://github.com/rvaiya/keyd)

## What Bootstrap Does

1. Installs packages from `pkglist.txt` (or mise-only on remote)
2. Configures keyd and enables the service
3. Sets up zsh with XDG directories
4. Appends the guarded zfiles block to `~/.bashrc` and fixes the login chain
5. Clones neovim config and symlinks Omarchy theme
6. Backs up any file `stow` would collide with, then stows all packages
7. Adds `zfilesbindings.conf` source to Hyprland config
8. Installs the theme-set hook for sioyek/yazi
9. Enables `herdr-navd` on WSL (§14b)
10. Runs `windows/install.ps1` on WSL (§15) — AutoHotkey, GlazeWM, WezTerm,
    `.wslconfig`

## Adding More Packages

To stow additional configs, add a directory with the proper structure:

```
newpkg/
└── .config/
    └── newpkg/
        └── config.toml
```

Then add `newpkg` to `STOW_PACKAGES` in `bootstrap.sh`.
