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
  is stale or missing them) and pinentry-curses. The Windows side runs from
  `windows/install.ps1` (bootstrap step 15) — see [The Windows
  side](#the-windows-side).
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
(cura, sioyek, xdg, wireplumber).

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

### The Windows side

Bootstrap step 15 runs `windows/install.ps1` on the WSL target. It is
idempotent — bootstrap re-runs it every time, and it only acts on what differs.

| component | state |
|-----------|-------|
| Caps Lock | working, via AutoHotkey — `windows/autohotkey/caps.ahk` |
| WezTerm   | working — `windows/wezterm/wezterm.lua` is the source of truth |
| GlazeWM   | configured — `windows/glazewm/config.yaml`, mapped from Omarchy's Hyprland bindings |
| Navigation | `herdr-navd` — nvim splits → herdr panes → GlazeWM windows |

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
  debugging story when a keypress does nothing.

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
