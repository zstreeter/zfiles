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

## Layout

One directory per OS target, each owning its stow packages, its package list,
and its setup steps; `common/` is shared by all of them.

```
zfiles/
├── bootstrap.sh          # thin dispatcher: facts → packages → stow → setup
├── common/               # every machine
│   ├── setup.sh          # gpg, zsh/zap, bash hook, ble.sh, nvim, herdr, pi…
│   └── stow/             # shell zsh bash yazi herdr opencode pi scripts sioyek xdg
├── omarchy/              # Arch + Omarchy desktop (Hyprland)
│   ├── setup.sh          # pacman/AUR, keyd, email tools, theme hooks, docker
│   ├── pkglist.txt
│   ├── hooks/            # Omarchy theme-set / post-update hooks
│   ├── root_etc/         # /etc/keyd/default.conf (Caps → Esc/Super)
│   └── stow/             # hypr himalaya mirador omarchy cura wireplumber
├── wsl/                  # WSL Ubuntu work laptop
│   ├── setup.sh          # apt + mise, herdr-navd, Windows-side dispatch
│   ├── pkglist.txt
│   ├── stow/             # wsl (the Linux→Windows routing layer: winapp)
│   └── windows/          # Windows host configs + install.ps1 — see below
└── remote/               # root-less work servers reached over ssh
    ├── setup.sh
    └── install.sh        # curl-able entry point
```

Any other Linux box falls back to a plain `linux` target: common packages
only, core CLI tools backfilled via mise.

## Installation

```bash
git clone https://github.com/zstreeter/zfiles.git ~/zfiles
cd ~/zfiles
./bootstrap.sh
```

Reboot after installation for keyd to take effect.

### Targets

`bootstrap.sh` detects four orthogonal facts, picks ONE target directory from
them, and sources that directory's `setup.sh` (which defines
`target_packages()` and `target_setup()` around the shared steps):

- **Remote** (`--remote` flag or `ZFILES_TARGET=remote`) — the only one that
  can't be sniffed, so it's explicit. A work server you `ssh` into from a herdr
  pane. Installs **only** the bash prompt, yazi, and neovim, entirely under
  `$HOME`: **never sudo, never a package manager, never `chsh`**. See
  [Remote servers](#remote-servers) below.
- **Omarchy** (`~/.config/omarchy/` or `~/.local/share/omarchy/` exists) —
  full overlay: common + Hyprland bindings, keyd, theme hooks, himalaya/mirador,
  cura/wireplumber, docker.
- **WSL** (`/proc/version` mentions Microsoft) — common packages via apt + mise
  (`wsl/pkglist.txt`; neovim/yazi/go/rust/bun/opencode via mise since noble
  is stale or missing them) and pinentry-curses. The Windows side runs from
  `wsl/windows/install.ps1` — see [The Windows side](#the-windows-side).
- **Package manager** (pacman vs apt) — forced to `none` on remote, or with
  `ZFILES_SKIP_PKG=1` (cheap re-runs: re-stow and reconfigure without the
  minutes-long package step).

Packages are auto-discovered: everything under `common/stow/` plus the
target's `stow/` gets stowed — `ls <dir>/stow` IS the package list. Common
packages on every target:

| Package    | Purpose                            |
|------------|------------------------------------|
| `shell`    | Shell-agnostic config sourced by **both** zsh and bash: `env.sh`, `aliases.sh`, `commands.sh`, `git-prompt.sh` |
| `zsh`      | zsh-only bits (`.zshrc`, prompt, zap plugins) |
| `bash`     | bash-only bits (`rc.sh`, prompt) — see [The bash hook](#the-bash-hook) |
| `yazi`     | File manager (plugins vendored in-repo) |
| `herdr`    | Terminal workspace manager + `herdr-navd` (WSL only; see [Seamless navigation](#seamless-navigation)) |
| `opencode` | opencode agent config              |
| `pi`       | pi agent config                    |
| `scripts`  | `new-research-project`, `publish-post` helpers + vault template |
| `sioyek`   | PDF viewer config — theme-rendered on Omarchy, static Catppuccin fallback elsewhere, Windows build on WSL |
| `xdg`      | mimeapps defaults; entries naming absent `.desktop` files just no-op |

Remote stows `shell`, `bash`, and `yazi` only (`STOW_ONLY` in
`remote/setup.sh`) — no zsh, no herdr, no pi, no desktop anything.

### Remote servers

The workflow is: herdr runs on the local machine, one pane holds an `ssh`
session to a work server. Those are bash terminals with no root. One line gets
zfiles' bash prompt, yazi, and neovim onto that server:

```bash
curl -fsSL https://raw.githubusercontent.com/zstreeter/zfiles/main/remote/install.sh | sh
```

What it does:

1. Blobless **sparse** clone of only the `shell`/`bash`/`yazi` packages plus
   `remote/` into `~/.zfiles` (falls back to a shallow full clone on
   git < 2.25 — still small).
2. `exec ~/.zfiles/bootstrap.sh --remote`, which:
   - appends a guarded hook to `~/.bashrc` (never replaces it),
   - installs `neovim yazi fd ripgrep fzf zoxide bat eza` via **mise** into
     `~/.local` — no root, nothing touched outside `$HOME`,
   - stows `shell bash yazi`, clones the neovim config, installs yazi plugins
     and the Catppuccin Mocha flavor.

Nothing herdr-related ships to the server; herdr stays local and the server is
just what's running inside one of its panes.

To re-run later, `zfiles-update` (defined in the `shell` package's
`commands.sh`) pulls and re-bootstraps whichever checkout it finds.

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
stow -d common/stow  --no-folding --target=$HOME sioyek
stow -d omarchy/stow --no-folding --target=$HOME hypr
```

Bootstrap is just the orchestrator — `stow` itself is per-package.

## Customization

### Hyprland Keybindings

Omarchy 4 configures Hyprland in Lua: `~/.config/hypr/hyprland.lua` loads
Omarchy's defaults, then `require`s your `hypr.monitors`, `hypr.bindings` and
`hypr.autostart` modules. The stowed `omarchy/stow/hypr/.config/hypr/*.lua`
files *are* those modules — no `source =` line to wire up.

Edit `omarchy/stow/hypr/.config/hypr/bindings.lua` to add your own bindings.
Unbind a default before rebinding its key:

```lua
hl.unbind("SUPER + J")                       -- was: toggle window split
o.bind("SUPER + J", "Focus down", nav .. "d") -- string = exec, or hl.dsp.* for a dispatcher
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai" })
```

`omarchy menu keybindings --print` lists what's currently bound. The
old `.conf` files are not loaded at all on Omarchy 4.

> **After an Omarchy update**, `omarchy/hooks/post-update` checks that every
> stowed `hypr/*.lua` is still a symlink into the repo and that the overlay's
> binds are actually loaded. If a migration dropped a real file in its place
> (the 4.0 `.conf` → `.lua` move did exactly that), you get a critical
> notification — re-run `bootstrap.sh` to restow.

### Caps Lock Behavior

The keyd config (`omarchy/root_etc/keyd/default.conf`) maps Caps Lock to:
- **Tap** → Escape
- **Hold** → Super (for Hyprland bindings)

On WSL the same remap has to happen on the Windows host — WSL2 has no
`/dev/input`, so keyd can never see the keyboard. `wsl/windows/autohotkey/caps.ahk`
reproduces it, with one difference: **hold → `F14`, not Super**. Windows itself
owns a large slice of Super (Win+E, Win+R, Win+number, the Start menu on bare
press), so Caps-as-Super collides constantly. `F14` is a private channel — no
physical key emits it, nothing binds it, and it carries no modifier semantics
that could leak into an app. GlazeWM can still match on it because its
keybinding matcher tests whether *any* listed key is held, not just real
modifiers. So `f14+h` in `wsl/windows/glazewm/config.yaml` is what `SUPER+H` is on
Omarchy. See [The Windows side](#the-windows-side).

**There is no Caps Lock key.** `install.ps1` writes a `Scancode Map` to
`HKLM\SYSTEM\CurrentControlSet\Control\Keyboard Layout` turning scancode `0x3A`
into `0x64` (F13) in the keyboard driver, so Windows never sees a Caps Lock key
and the lock state cannot latch. This is not tidiness: `caps.ahk` used to hold
the lock off from userspace with `SetCapsLockState "AlwaysOff"`, which leaves a
hole exactly the width of the process not running — during logon before the
task fires, and during every restart after an edit to the script — and one
press in that window latched it for real. The driver remap holds whether or not
AutoHotkey is up. It needs elevation (one UAC prompt, only on the run that
changes something) and a reboot to load, so `caps.ahk` hooks `CapsLock`
alongside `F13` as a bridge until then.

> **The mapping DWORD puts the SOURCE scancode in the high word**, so a
> Caps→F13 map is the bytes `64 00 3A 00`, target first. zfiles wrote them the
> other way round (`3A 00 64 00`) until Aug 2026, which is a map of F13 →
> Caps Lock: `kbdclass` accepted it, remapped a key no keyboard on this machine
> emits, and left Caps Lock alone. The failure is silent — the only symptom is
> Caps Lock going on latching, which is indistinguishable from the value never
> having been applied. It took an AutoHotkey `InputHook` still logging
> `sc=0x3A` after a reboot with the value in place to tell the two apart.
> Check any new mapping against Microsoft's worked example, which documents
> `0x003A001D` as "CAPS LOCK → Left CTRL (0x3A → 0x1D)".

F13 in the driver, F14 out of the script, and they have to differ: GlazeWM
installs its own low-level keyboard hook, hook order between two
logon-started processes is not pinnable, and a *physical* F14 that reached
GlazeWM before `caps.ahk` suppressed it would fire every binding twice.
Nothing is bound to `f13`, so the physical key is inert to the WM.

### The Windows side

Bootstrap step 15 runs `wsl/windows/install.ps1` on the WSL target. It is
idempotent — bootstrap re-runs it every time, and it only acts on what differs.

| component | state |
|-----------|-------|
| Caps Lock | working, via AutoHotkey — `wsl/windows/autohotkey/caps.ahk`, on a driver-level Caps→F13 remap |
| WezTerm   | working — `wsl/windows/wezterm/wezterm.lua` is the source of truth |
| GlazeWM   | configured — `wsl/windows/glazewm/config.yaml`, mapped from Omarchy's Hyprland bindings |
| Navigation | `herdr-navd` — nvim splits → herdr panes → GlazeWM windows |
| sioyek    | Windows build via winget, configs in `wsl/windows/sioyek/` — see below |

The full Omarchy→Windows binding map — every chord mapped, substituted, or
explicitly dropped, with reasons — is `wsl/windows/PARITY.md`. The from-scratch
setup recipe for the laptop (or its replacement) is `wsl/INSTALL.md`.

#### GUI programs are the Windows build

**Rule for this target: anything with a window is installed as the Windows
program, and the Linux side routes to it.** WSL entry points keep their Linux
names — `sioyek foo.pdf` in a shell, yazi's openers, `xdg-open` — and
`wsl/stow/wsl/.local/bin/winapp` finds the `.exe` and re-runs it with every path
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
  process that owned it. (The `glazewm command close` half of this was measured
  against the sick instance described below and has not been re-tested. The
  `WM_CLOSE` half is the load-bearing one anyway: ordinary windows do not
  survive it and RAIL windows do.)

The Windows build of the same program has none of that. Native sioyek is
`processName: sioyek`, class `Qt5152QWindowIcon`, arrives tiling, and closes.
`config.yaml` keeps a `set-tiling` rule matching `msrdc` + `RAIL_WINDOW` as a
fallback for anything still coming through WSLg.

Adding a program to this scheme is three steps: a winget install plus a
`Copy-IfChanged` for its config in `install.ps1`, a `winapp <name>.exe` branch
in whatever `~/.local/bin` wrapper already exists for it, and — if its config
format differs between targets — a file under `wsl/windows/<name>/`. sioyek is the
worked example. Note that `ahrm.sioyek` is a *portable* package: it reads its
config from the directory holding the exe, which is version-stamped, so a
sioyek upgrade starts with empty configs until the next bootstrap run.

#### When GlazeWM stops moving one window

A long-running `glazewm.exe` can stop applying geometry to a *single* window
while going on managing everything else perfectly. Measured Aug 2026 with
sioyek, WezTerm and a throwaway Explorer window sharing one workspace:

| window   | GlazeWM computed    | actually was        |
|----------|---------------------|---------------------|
| WezTerm  | 1908x1544 @ 8,48    | 1922x1551 @ 1,48    |
| Explorer | 1269x1544 @ 1285,48 | 1283x1551 @ 1278,48 |
| sioyek   | 1908x1544 @ 1924,48 | 700x539 @ 300,300   |

Nothing in GlazeWM's own view of the world looked wrong. `query windows`
reported sioyek as an ordinary `tiling`, `shown` window on the focused
workspace throughout, no rule matched it, `query paused` was false, and every
command aimed at it came back `success: true`. Three separate recomputes of its
slot — another window appearing, that window closing, `set-floating` then
`set-tiling` — moved it by nothing, with no reverted transient visible while
polling its real rect every 20ms. A plain non-elevated `SetWindowPos` on the
same HWND moved it exactly, so the window was never the problem.

**Restarting `glazewm.exe` fixes it.** Why an instance gets into that state is
not known: nothing in `errors.log`, and it has not been reproduced on demand.

Two habits fall out of this. Measure the real rect with `GetWindowRect` instead
of trusting `query windows`, which reports what GlazeWM *computed*, not what it
applied — the two disagreeing is the entire signature, and every command
returning `success: true` means the IPC will not tell you. And restart the WM
before concluding a GlazeWM command is broken: the section below is a whole
feature that got written up as dead on the strength of one sick instance.

Restart is `Stop-Process` on `glazewm`, a pause, then `glazewm.exe start` — and
**wait for port 6123 to be released**. Racing the new instance against the old
one gets `Only one usage of each socket address ... (os error 10048)` in
`errors.log` and leaves a glazewm that manages windows but has no IPC listener,
which breaks `herdr-navd` silently: keybindings still work, navigation stops.

#### Caps+Q does not go through GlazeWM

`caps.ahk` handles Caps+Q itself with `WinClose`, which posts `WM_CLOSE`
straight at the focused window, and `config.yaml` has no `f14+q` binding at
all. Only a *bare* Caps+Q closes; Caps+Shift+Q and friends fall through to the
f14 channel and stay inert, so there is no second, undocumented way to close
the focused window by accident.

This used to be documented here as "`close` is broken in GlazeWM 3.10.1 on this
machine, for every window rather than for any particular kind". **That was
wrong.** Re-measured Aug 2026 against a freshly restarted WM,
`glazewm command --id <id> close` returns `success: true` and the window does
go away. The original measurement was taken against the instance described
above, which had stopped acting on windows.

`WinClose` stays, but on its own merits rather than as a workaround: posting
`WM_CLOSE` directly means Caps+Q keeps working when the window manager does
not, which is exactly the failure the old note misdiagnosed.

Configs are **copied** to the Windows side, not symlinked across
`\\wsl.localhost`: the logon tasks run when the distro may not be up, and a UNC
path there would either fail or force the distro to boot just to read a config.
So editing `wsl/windows/*` takes a bootstrap re-run to reach Windows. An unmanaged
file already at the destination is backed up once to `<name>.zfiles-bak`.

Both the Caps Lock remap (`zfiles-caps`) and GlazeWM (`zfiles-glazewm`) run as
logon tasks at highest privileges, so they also apply over elevated windows and
raise no UAC prompt at logon. `caps.ahk` is syntax-checked with `/validate`
before any running instance is restarted, and only restarted when it actually
changed; a GlazeWM config change triggers `wm-reload-config` rather than a
restart, so windows stay where they are.

#### Seamless navigation

On Omarchy, `SUPER+hjkl` runs `omarchy/stow/hypr/.config/hypr/scripts/herdr-nav`, which walks
outward — nvim splits, then herdr panes, then Hyprland windows — and stops at
the first layer that can take the move. Reproducing that on WSL takes two
pieces, because the keyboard is on the Windows side and the panes and splits are
on the Linux side:

- **`hjkl` is deliberately not bound in GlazeWM.** If it were, GlazeWM's
  system-wide hook would swallow `f14+h` before WezTerm ever saw it. Instead
  `caps.ahk` arbitrates: outside the terminal it forwards to the WM as usual,
  and inside the terminal it asks the daemon first.
- **`herdr-navd`** (`common/stow/herdr/.local/bin/herdr-navd`) is a small Python 3 stdlib
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
`wsl/pkglist.txt`. The stdlib `json` module makes the gap moot instead of
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
`wsl/windows/kanata/kanata.kbd` is kept as the reference the `.ahk` was ported from,
but nothing installs it: its only winget source is the GitHub release, and
Zscaler 403s that download (the direct URL and the `api.github.com` asset
endpoint both redirect to the same CDN; msstore doesn't carry it). Unrelated
GitHub release downloads — AutoHotkey, PowerToys — come through fine, so the
block reads as aimed at keyboard-interception tools rather than incidental.
PowerToys was the other candidate and can't do this at all: Keyboard Manager
does one-to-one remaps only, with no notion of tap versus hold.

### Theme Integration

Omarchy renders the active theme into `~/.local/state/omarchy/current/theme/`
(user templates in `~/.config/omarchy/themed/*.tpl` are rendered there too —
zfiles stows one for yazi). On every theme switch the `theme-set` hook adds:
- Sioyek — writes `sioyek-prefs.config` into the rendered theme dir;
  `~/.config/sioyek/prefs_user.config` is a symlink to it.
- Opencode — maps the Omarchy theme name onto `~/.config/opencode/tui.json`.
- Yazi — the stowed yazi `theme.toml` always selects a flavor named `zfiles`; each target
  decides what fills `~/.config/yazi/flavors/zfiles.yazi/`. On Omarchy it's a
  symlink to the rendered theme, so yazi follows theme switches. On WSL and
  remote it's static Catppuccin Mocha (`ya pkg add yazi-rs/flavors:catppuccin-mocha`).

Notifications are Omarchy's own shell (mako is gone as of 4.0).

### Neovim

The bootstrap script clones [my neovim config](https://github.com/zstreeter/nvim) and symlinks Omarchy's theme, so colorschemes stay in sync.

## Omarchy Resources

- [Omarchy GitHub](https://github.com/basecamp/omarchy)
- [Omarchy Wiki](https://github.com/basecamp/omarchy/wiki)
- [Hyprland Wiki](https://wiki.hyprland.org/)
- [Keyd Documentation](https://github.com/rvaiya/keyd)

## What Bootstrap Does

1. Detects the target (remote / omarchy / wsl / linux) and sources its
   `setup.sh`
2. Runs the target's package step (pacman/AUR, apt + mise, or mise-only on
   remote), then backfills the core CLI tools via mise on every target
3. Backs up any file `stow` would collide with, then stows every package under
   `common/stow/` and the target's `stow/` (`--no-folding`, adopt-and-revert)
4. Runs `common/setup.sh`: GPG agent, zsh + Zap, the bash hook, ble.sh,
   neovim clone, herdr + agent integrations, pi, XDG hygiene, yazi plugins,
   research workspace
5. Runs the target's `target_setup()`: keyd/Hyprland/theme hooks/email/docker
   on Omarchy; `herdr-navd` and `wsl/windows/install.ps1` (AutoHotkey, GlazeWM,
   WezTerm, `.wslconfig`) on WSL

## Adding More Packages

Drop a directory with the proper structure into the right `stow/` dir —
`common/stow/` for every machine, `<target>/stow/` for one target:

```
common/stow/newpkg/
└── .config/
    └── newpkg/
        └── config.toml
```

No arrays to edit — bootstrap auto-discovers it on the next run. (Remote is
the one exception: its whitelist is `STOW_ONLY` in `remote/setup.sh`.)
