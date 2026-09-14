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
- **Theme integration** - Sioyek, Yazi, Neovim and opencode follow Omarchy's theme automatically
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
│   ├── setup.sh          # pacman/AUR, keyd, email tools, Quattro reconciliation
│   ├── pkglist.txt
│   ├── config/hypr/      # source for deployed, Omarchy-managed Lua modules
│   ├── root_etc/         # /etc/keyd/default.conf (Caps → Esc/Super)
│   └── stow/             # hypr himalaya carillon omarchy cura wireplumber
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

After an `omarchy upgrade-to-quattro`, re-run `bootstrap.sh`; the one-time
upgrade does not dispatch the normal `post-update` hooks.

### Targets

`bootstrap.sh` detects three environment facts, picks ONE target directory from
them, and sources that directory's `setup.sh` (which defines
`target_packages()` and `target_setup()` around the shared steps):

- **Remote** (`--remote` flag or `ZFILES_TARGET=remote`) — the only one that
  can't be sniffed, so it's explicit. A work server you `ssh` into from a herdr
  pane. Installs **only** the bash prompt, yazi, and neovim, entirely under
  `$HOME`: **never sudo, never a package manager, never `chsh`**. See
  [Remote servers](#remote-servers) below.
- **Omarchy** (`~/.config/omarchy/` or `~/.local/share/omarchy/` exists) —
  full overlay: common + Hyprland bindings, keyd, theme hooks, himalaya/carillon,
  cura/wireplumber, and Docker socket activation.
- **WSL** (`/proc/version` mentions Microsoft) — common packages via apt + mise
  (`wsl/pkglist.txt`; neovim/yazi/go/rust/bun/opencode via mise since noble
  is stale or missing them) and pinentry-curses. The Windows side runs from
  `wsl/windows/install.ps1` — see [The Windows side](#the-windows-side).

Set `ZFILES_SKIP_PKG=1` for cheap re-runs that re-stow and reconcile the target
without repeating the minutes-long package installation step.

Packages are auto-discovered: everything under `common/stow/` plus the
target's `stow/` gets stowed — `ls <dir>/stow` IS the package list. Common
packages on every target:

| Package    | Purpose                            |
|------------|------------------------------------|
| `shell`    | Shell-agnostic config sourced by **both** zsh and bash: `env.sh`, `aliases.sh`, `commands.sh`, `git-prompt.sh` (git's contrib copy, plus a `__gh_ps1` addition below a marker line) |
| `zsh`      | zsh-only bits (`.zshrc`, prompt, zap plugins) |
| `bash`     | bash-only bits (`rc.sh`, prompt) — see [The bash hook](#the-bash-hook) |
| `yazi`     | File manager (plugins vendored in-repo) |
| `herdr`    | Terminal workspace manager + `herdr-navd` (WSL only; see [Seamless navigation](#seamless-navigation)) |
| `opencode` | opencode agent config              |
| `pi`       | pi agent config                    |
| `scripts`  | `new-research-project`, `publish-post`, `obsidian-{vault,open,render}` + vault template — see [Research pipeline](#research-pipeline) |
| `sioyek`   | PDF viewer config — theme-rendered on Omarchy, static Catppuccin fallback elsewhere, Windows build on WSL |
| `xdg`      | mimeapps defaults; entries naming absent `.desktop` files just no-op |
| `measure`  | `measure` — an empirical ledger, so an agent quotes measurements instead of recalling them — see [Measured, not remembered](#measured-not-remembered) |
| `paperctl` | `paperctl` + skill — a research-paper library: arXiv/Crossref/OpenAlex search, per-target email harvesting, BibTeX for Quarto — see [Papers, from anywhere](#papers-from-anywhere) |
| `obsidian` | skills: `obsidian` (vault + rendering) and `obsidian-note` (capture) |
| `quarto`   | skill: filter phases, temp-dir staging, blog publish path |
| `pandoc`   | skill: what Pandoc 3.x already handles, and the never-preprocess rule |
| `zotero`   | skill: Better BibTeX keys, read-only `references.bib`, missing-citation triage |
| `latex`    | skill: TinyTeX, reading a failed `.tex`, symptom → cause table |
| `reverify` | skill + `reverify-setup`, an install-on-demand binary-analysis CLI |

Those last eight each carry a `SKILL.md` under `~/.agents/skills/`, which is the
root pi reads natively; `agent-skills` symlinks the same tree into
`~/.claude/skills` and `~/.codex/skills` so all four harnesses see one copy. A
skill lives with the program it describes rather than in one central pile, so
removing a package removes its guidance with it.

Remote stows `shell`, `bash`, `yazi`, `measure`, and the skill packages
(`STOW_ONLY` in `remote/setup.sh`) — no zsh, no herdr, no pi, no desktop
anything. The skills go along because they are inert markdown, and an agent on
the work server is as capable of hand-writing a broken regex over a note as one
running locally; `measure` goes because that box is where the benchmarks run.
`scripts` stays out, so no research workspace is created there.

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
Stow can never swallow a pre-existing `~/.bashrc` into the repo. If
the login chain (`.bash_profile` → `.bash_login` → `.profile`) doesn't already
reach `~/.bashrc`, bootstrap wires that up too. Anything it overwrites or
displaces first lands in `~/.local/state/zfiles/backup/`.

### À la carte stowing

Each package directory is independent. To install just one:

```bash
cd ~/zfiles
stow -d common/stow  --no-folding --target=$HOME sioyek
stow -d omarchy/stow --no-folding --target=$HOME carillon
```

Bootstrap is just the orchestrator — `stow` itself is per-package.

## Customization

### Hyprland Keybindings

Omarchy 4 configures Hyprland in Lua: `~/.config/hypr/hyprland.lua` loads
Omarchy's defaults, then `require`s your `hypr.monitors`, `hypr.bindings` and
`hypr.autostart` modules. Bootstrap deploys these from `omarchy/config/hypr/`
as regular files because Omarchy refreshes and migrations manage those paths;
repository symlinks would let those commands overwrite tracked source.

Edit `omarchy/config/hypr/bindings.lua` to add your own bindings, then re-run
`bootstrap.sh`.
Unbind a default before rebinding its key:

```lua
hl.unbind("SUPER + J")                       -- was: toggle window split
o.bind("SUPER + J", "Focus down", nav .. "d") -- string = exec, or hl.dsp.* for a dispatcher
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai" })
```

`omarchy menu keybindings --print` lists what's currently bound. The
old `.conf` files are not loaded at all on Omarchy 4.

> **After an Omarchy update**, the stowed `post-update.d/zfiles` hook compares
> the deployed Lua modules with their repository sources and confirms the
> overlay's bindings are loaded. Drift produces a critical notification;
> re-run `bootstrap.sh` to redeploy.

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
| Obsidian  | Windows build via winget (`--scope user`), detected before install; no config copied — Obsidian keeps its settings per-vault |

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

`Caps+Space` opens PowerToys Command Palette, Omarchy's `SUPER+SPACE`. On a
multi-monitor setup that used to put the app on the *previous* workspace whenever
you launched from an empty one — focus workspace 3 on the second screen, launch
Outlook, and it opens on workspace 1.

An empty workspace has no OS-level focus anchor. GlazeWM's focused container is
the workspace, but Windows' foreground window is still whatever was up last;
`sync_focus` can only "focus the desktop". The palette is a tool window GlazeWM
can never manage, so it doesn't react to the palette taking foreground — but when
the palette closes, Windows hands foreground to the top *managed* window in the global
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
a managed network 403s that download (the direct URL and the `api.github.com` asset
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
- Opencode — maps the Omarchy theme name onto `~/.config/opencode/tui.json`;
  active agent sessions are not re-signalled, so they pick it up on next launch.
- Yazi — the stowed yazi `theme.toml` always selects a flavor named `zfiles`; each target
  decides what fills `~/.config/yazi/flavors/zfiles.yazi/`. On Omarchy it's a
  symlink to the rendered theme, so yazi follows theme switches. On WSL and
  remote it's static Catppuccin Mocha (`ya pkg add yazi-rs/flavors:catppuccin-mocha`).

Notifications are Omarchy's own shell (mako is gone as of 4.0). Carillon watches
the Himalaya accounts and sends new-mail events to it through `notify-send`.

### Neovim

The bootstrap script clones [my neovim config](https://github.com/zstreeter/nvim) and symlinks Omarchy's theme, so colorschemes stay in sync.

## Research pipeline

One source of truth — a note in an Obsidian vault — reaching three
destinations: the blog, a PDF, and a `.tex` for a journal or arXiv.

```
Zotero ──(Better BibTeX)──> references.bib
                                  │
   Obsidian vault ─────────> Quarto ──┬──> .html ──> publish-post ──> blog
   (notes/, drafts/,    (reads .md directly,   ├──> .pdf   (the paper)
    literature/)         via the obsidian      └──> .tex   (arXiv / journal)
                         filter at pre-ast)
```

**A vault is a Quarto project.** There is no conversion step and no intermediate
file — `quarto render notes/x.md --to typst` works on the note where it sits,
while Obsidian still has it open. Two settings in the vault's `_quarto.yml` are
what make that true:

```yaml
from: markdown+wikilinks_title_after_pipe+mark
filters:
  - at: pre-ast
    path: _extensions/obsidian/obsidian.lua
```

| Command | Does |
|---------|------|
| `new-research-project <name>` | scaffolds `~/research/<name>/` from the vault template |
| `obsidian-vault path\|name\|list\|config` | resolves vault locations on any target |
| `obsidian-open [-v <vault>] [<file>]` | opens Obsidian **at a note**, via an `obsidian://` URI |
| `quarto render <note.md> --to typst\|pdf\|latex\|html` | note → paper, inside a vault; `typst` needs no TeX |
| `obsidian-render <note.md> [--to …]` | the same, for notes *outside* a vault — supplies the reader extensions and filter by hand |
| `publish-post drafts/<f>.qmd [slug]` | copies a draft into the blog repo |

### Why the filter is a filter and not a preprocessor

Obsidian Flavored Markdown is not Pandoc Markdown, and Pandoc does not error on
the difference — it silently emits the wrong thing. Most of the gap Pandoc 3.x
closes on its own once the reader is asked for it:

| written in Obsidian | handled by |
|---|---|
| `[[Some Note\|alias]]`, `![[figure.png]]` | Pandoc — `+wikilinks_title_after_pipe` |
| `==highlight==` | Pandoc — `+mark` |
| `[[@smith2024]]` | the filter — rewrites the link to a real `Cite` |
| `![[Other Note#Methods]]` | the filter — Pandoc has no transclusion |
| `> [!warning] Careful` | the filter — becomes a Quarto callout |
| `%% draft note %%` | the filter — removed, not printed in the paper |
| `^block-id` | the filter — stripped |

The citation row is the one that costs real work: this repo's vaults file
literature notes as `@<citekey>.md` and link them `[[@citekey]]` (see the vault
`AGENTS.md`), so without the rewrite those references never reach the
bibliography and the paper's reference list is quietly short.

The important word is **filter**. This used to be a ~400-line Python normalizer
doing regex substitution over the note's text, which meant stashing math and
fenced code first and restoring them last — because `^` is a block id *and* a
superscript, `==` is a highlight *and* an alignment, `[[ ]]` is a wikilink *and*
a bracket matrix. That whole class of corruption is designed out by running
after the parse instead of before it: in the AST, math is an opaque `Math` node
the filter cannot reach into, so a formula cannot be damaged by a rule meant for
prose. **Never "fix" Obsidian syntax with a regex over a note.**

Two things about this are load-bearing and were found the hard way, both of
which fail *silently* — the build succeeds and the output is wrong:

- **The `render:` list.** Quarto applies `_quarto.yml` only to files in the
  project's `render:` list; a note outside it renders with no reader
  extensions, no filter and no PDF format, and reports no error. `notes/` is
  in the list for that reason; `literature/` is deliberately not.
- **`at: pre-ast`.** The filter is declared in `_quarto.yml` at the earliest
  phase. Measured: at `post-ast` or `pre-quarto`, callouts render fine in HTML
  but degrade in PDF to a plain quote with the title dropped — Quarto has
  already passed the point where it lowers callout divs into `tcolorbox`.
- **Quarto stages input into a temp dir.** `PANDOC_STATE.input_files[1]` points
  at `/tmp/quarto-session-…`, so walking up from it never finds `.obsidian` and
  transclusion resolves nothing. The filter reads `QUARTO_DOCUMENT_PATH` first,
  then the working directory, then `QUARTO_PROJECT_DIR`.

The blog path is unchanged: `publish-post` still consumes a `.qmd` from
`drafts/`, so nothing new to maintain there.

### Measured, not remembered

An agent's memory of a number is not evidence. Across a context reset it keeps
the conclusion — "peak HBM was 41 GB" — and drops the provenance: which machine,
which commit, which flags, whether the tree was dirty. It then repeats the
number confidently long after the code that produced it changed.

`measure` closes that gap, and the design turns on one constraint: **entries
cannot be asserted.** `measure run` executes the command and captures what came
back, so a record is a byproduct of execution rather than a claim. A notes file
would just be another place to write the same guess.

```bash
measure run --tag hbm-peak --input src/residualMarginals.cc \
  -e 'peak_gb=Peak HBM: ([0-9.]+)' -- ./build/bench --matrix-free --size 4096

measure recall hbm        # what's known, with staleness flags
measure diff hbm-peak     # last two runs: what moved, and by how much
```

Output streams live and the exit code passes through, so it composes inside
scripts and Makefiles — and a *failed* run is recorded too, since a crash at a
given size is evidence.

The second half is staleness. Every entry carries the commit it was taken at and
whether the tree was dirty; `--input` additionally records file hashes, which is
what makes the check exact rather than advisory:

| status | means | quote it? |
|---|---|---|
| `OK` | recorded inputs byte-identical, or current clean commit | yes, with the date |
| `STALE` | a recorded `--input` changed — names which | no, re-run |
| `?` | dirty tree, or a different commit with nothing pinned | unknown, not weak support |
| `UNVERIFIED` | a `measure note` — read, not executed | never as a measurement |

Storage is one append-only JSONL file at `<repo-root>/.measurements/ledger.jsonl`
(`jq`-able; a half-written entry costs one line, not the ledger). Append-only
because the history is often the finding — a number that moved across three
commits says more than its current value. Stdlib Python, no daemon, no server,
and it's in remote's `STOW_ONLY` because the work server is where the benchmarks
actually run.

The accompanying `SKILL.md` is what makes it bind: check `measure recall` before
asserting a performance or hardware fact, record after producing one.

**`reverify`** is the same idea aimed at binaries — a PE parser, disassembler and
CPU emulator returning `VERIFIED` / `REFUTED` / `INCONCLUSIVE` against the actual
bytes. It ships as an install-on-demand CLI (`reverify-setup`) and is
deliberately **not** registered as an MCP server: nine tool schemas would ride in
every request of every session forever, and nothing in this setup's daily work
asks a binary question. The skill costs nothing until one does.

### Papers, from anywhere

The pipeline above assumes the papers are already on disk. `paperctl` is how they
get there. One stdlib-Python CLI on PATH, filing into `~/Library/<Folder>/` — the
PDF, a README index, and BibTeX.

```bash
paperctl doctor                                   # what works on THIS machine
paperctl add 2506.19243                           # arXiv id, DOI, URL or title
paperctl mail thread --subject "..." --dry-run    # every paper in a mail thread
paperctl bib --folder X --out ~/research/p/library.bib
```

It was a Claude Code skill first, which is exactly the problem: a skill is
reachable from one harness. A CLI is reachable from Claude Code, Codex, opencode
and pi — and from a shell. The skill still ships, but it now documents a program
rather than being one.

Two things shape the design. First, **the machines differ and the tool must not
care.** Mail is a backend registry, not an `if/elif`: WSL reads Outlook through
Microsoft Graph, Omarchy reads IMAP through `himalaya` (which already holds the
accounts and their `pass`-backed passwords), and a work server has neither —
`[target.remote.mail] backend = "none"`, and search still works. No command takes
a backend flag. Config layers defaults → `config.toml` → its `[target.<name>]`
section → gitignored `local.toml` → `PAPERCTL_*` → flags, every layer optional,
so a machine with no config at all still runs. `doctor` prints each resolved
value *and where it came from*.

Second, **links live in `href` attributes, not in visible text.** Measured on a
real 22-message thread: a body path that flattens HTML to readable text returned
zero URLs for 4 of them — including the originating mail carrying the two most
important links, because the anchor text was the paper's title. So the mail
interface's `html` field is raw markup, always, and a run that parses HTML and
finds no anchors *warns loudly* rather than reporting a confident zero. Graph's
`uniqueBody` matters for the same reason in reverse: without it, quoted reply
chains inflated one URL to 38 occurrences and attribution became meaningless.

The Quarto bridge is deliberately non-destructive. `paperctl bib` **refuses to
write a file named `references.bib`** and exits 2 — that one is Better BibTeX's
auto-export and hand edits to it vanish on the next sync. It writes `library.bib`
instead, and `_quarto.yml` cites both:

```yaml
bibliography: [references.bib, library.bib]
```

Citekeys approximate BBT's `auth.lower + shorttitle(3,3) + year`, so the two files
stay mergeable if Zotero ever arrives on a box that lacks it.

### Toolchain

Quarto comes from each target's package list: `quarto-cli-bin` on Omarchy, the
official `.deb` on WSL. Papers render through Typst, which ships inside Quarto,
so TeX is only needed for `--to pdf` or `--to latex`: `texlive-meta` on Omarchy,
`texlive-*` on WSL, or `quarto install tinytex` anywhere without sudo.
Obsidian itself is `obsidian` in `omarchy/pkglist.txt` (installed with
`--needed`, so already-present is a no-op) and a detect-then-winget block in
`wsl/windows/install.ps1`.

> **A vault must be opened in Obsidian once, by hand.** `obsidian://` URIs
> address a vault by *name*, and Obsidian only knows names for vaults in its own
> `obsidian.json` registry — which the app writes on first open, not the
> installer. Until then `obsidian-open` lands on the vault switcher rather than
> the note. `obsidian-vault` works regardless: it falls back to `~/research/*`
> and a bounded scan of the Windows profile.

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
3. Moves aside any file `stow` would collide with, removes retired targets from
   the previous manifest, then stows every package under `common/stow/` and the
   target's `stow/` (`--no-folding`, never `--adopt`)
4. Runs `common/setup.sh`: GPG agent, zsh + Zap, the bash hook, ble.sh,
   neovim clone, herdr + agent integrations, pi, XDG hygiene, yazi plugins,
   research workspace
5. Runs the target's `target_setup()`: keyd/Hyprland/theme hooks/email/services
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

No arrays to edit — bootstrap auto-discovers it on the next run and removes
retired target links using its state manifest. (Remote is
the one exception: its whitelist is `STOW_ONLY` in `remote/setup.sh`.)
