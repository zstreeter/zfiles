# WSL + GlazeWM stack: review and redesign research

Status: decided. Implemented: workspace unpinning, `{Blind}` fix, per-process claim,
deploy hash record, PowerToys reduced to Command Palette, nvim `--embed` socket lookup.
Rejected: launcher swap, chord test, AHK-side placement, smart-splits.nvim.

## The stack today

```
Caps (driver: scancode -> F13)
  └─ caps.ahk ── tap: Esc
       ├─ WM keys ─────── synthesize F14+<key> ──> GlazeWM keybindings
       ├─ Caps+hjkl ───── HTTP ──> herdr-navd (WSL) ── nvim RPC / herdr CLI / GlazeWM IPC
       └─ Caps+Space ──── HTTP /launch ──> herdr-navd arms "next window" claim
                          then Win+Alt+Space ──> Command Palette
install.ps1 copies configs to %USERPROFILE% (WSL ext4 is not reachable at logon)
```

## Bugs hit, by root cause

| Symptom | Root cause | Class |
|---|---|---|
| SUPER+N jumps monitors; "No workspace config available" ×12 in errors.log | `bind_to_monitor` pinning; a third monitor has no workspace | config choice |
| Caps+Shift+N only focuses | `{Blind}` mid-`Send` string is ignored, Shift released | implementation bug in synthetic-key channel |
| Slack opens on workspace 1 | claim consumed by splash window | **design: placement keyed on "next window", not on the launch** |
| Fixes reverted by next install | install overwrites live copy | deployment design (fixed: hash record) |

Two of four are design problems, not typos. The rest of this doc is about those.

## 1. Launch placement — the main redesign

### Precedent

- **i3**: placement is tied to the *launch*, via startup-notification IDs. Launching
  through the WM (`exec`, or rofi with `-run-command "i3-msg exec '{cmd}'"`) lets i3 put
  every window of that launch on the workspace it was launched from, even if you switch
  away meanwhile. ([i3 discussion #4782](https://github.com/i3/i3/discussions/4782))
- **Hyprland**: `exec [workspace N] cmd` exec-rules, matched by the **PID** of the
  spawned process (re-added in [PR #13374](https://github.com/hyprwm/Hyprland/pull/13374)
  because env-based matching failed for Chrome). A global "window goes where its process
  was launched" was tried and removed as unintuitive
  ([discussion #10085](https://github.com/hyprwm/Hyprland/discussions/10085)): it must be
  opt-in per launch.
- **GlazeWM**: the underlying bug is upstream and open —
  [#1336](https://github.com/glzr-io/glazewm/issues/1336) (Raycast, YASB, *and Command
  Palette*: the picker takes focus away from an empty workspace, so the new window falls
  back to another workspace) and [#997](https://github.com/glzr-io/glazewm/issues/997)
  (Flow/PowerToys, multi-monitor). Win+S / Win+R / the taskbar are reported unaffected.

Common rule: **identify the launch, then match windows to it by process.** Our claim
does neither — it is "the next window from anyone within 15 s", which is why it both
missed Slack's real window and can steal unrelated ones.

### Options

| | Design | Pros | Cons |
|---|---|---|---|
| A | Keep CmdPal; claim keyed on time (today) | no work | wrong by construction |
| B | Launch through our own code (AHK `Run` → PID, or GlazeWM `shell-exec`), match new windows by PID / process tree via GlazeWM `handle` → `GetWindowThreadProcessId` | the i3/Hyprland design; exact | needs a launcher we control; packaged (UWP) apps and single-instance apps (Slack already in tray) reuse an existing PID |
| C | Remove the cause: a launcher that does not steal workspace focus (Win+S path is reported unaffected), drop the claim entirely | deletes code; no daemon involvement | depends on upstream behaviour; can't verify without testing CmdPal vs Win+S here |
| D | B + move placement out of WSL into caps.ahk | Windows-only concern stops depending on the WSL VM being up | AHK has no WebSocket; must subscribe via `glazewm sub` child process |

Recommendation: **test C first** (cheapest; if Win+S/Start places correctly here, the
claim is deleted, not fixed). If CmdPal must stay, do **B+D**: placement is a Windows
concern and belongs on the Windows side, keyed on the launched process.

## 2. Keyboard channel (AHK → GlazeWM)

### Precedent

- [GlazeWM_AHK](https://github.com/clownroyal420/glazewm_ahk) and komorebi+AHK setups bind
  everything in AHK and call the WM CLI (`RunWait glazewm.exe command …`).
- Measured here: `glazewm.exe query focused` from Windows = **89–164 ms** per call. Too slow
  for focus movement; fine for rare commands.

### Assessment

The F13-in / F14-out synthetic channel is a sound trade (≈0 ms, no IPC from AHK), and its
reasons are documented in caps.ahk. Its weakness is that modifier handling is implicit in
`Send` semantics — the `{Blind}` bug. Not a redesign; a **regression test**: a script that
synthesizes each chord class (bare, +shift, +alt, +shift+alt, +ctrl) and checks GlazeWM saw
the right binding (`glazewm sub -e focus_changed` / query state). That is what would have
caught the bug.

## 3. Directional navigation (nvim → herdr → WM)

### Precedent

[smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) now ships herdr
support: nvim moves within its splits and **itself** crosses into herdr at an edge; a herdr
plugin asks `herdr pane process-info` whether the pane runs nvim and forwards the key. Each
layer handles its own edge and hands off outward — no outer process RPCing into nvim.

### Assessment

herdr-navd re-implements layers 1–2 (nvim socket discovery by PID, a Lua eval string).
That is the most fragile part of the daemon and is now maintained upstream. Rejected: AHK
intercepts Caps+hjkl before the terminal, so smart-splits would add a plugin, a herdr
plugin and `jq` while herdr-navd still has to own the herdr->GlazeWM hop. The review did
find herdr-navd looking for nvim's socket on the TUI pid; since nvim 0.10 it belongs to
the `nvim --embed` child (fixed, matching omarchy's herdr-nav).

## 4. Deployment

Precedent: chezmoi records what it last wrote and, on apply, refuses to clobber a target
that "has changed since chezmoi last wrote it", offering diff/merge
([chezmoi FAQ](https://www.chezmoi.io/user-guide/frequently-asked-questions/usage/)).
**Implemented** in `Copy-IfChanged` (`<dest>.zfiles-sha256`); same model, warn instead of
prompt because install.ps1 is non-interactive.

## 5. Cross-cutting: the WSL dependency

Launch placement and terminal-external navigation run in a Linux VM that is not up at
Windows logon. Anything that is purely a Windows concern (placement) should not depend on
it. herdr-navd should keep only what genuinely needs Linux (nvim/herdr state).
Not acted on: moving the claim to AHK is option D, dropped as more code than the
problem warrants while the claim is a stopgap for glazewm#1336.

## Proposed order

Guiding rule: minimal code. Prefer deleting a mechanism over hardening it.

1. Decided: keep Command Palette (user preference), so the claim stays. It works with the
   per-process fix. Known limit: a palette cancelled with Esc can claim the next window
   within 15 s. Delete the claim when glazewm#1336 is fixed upstream. B+D dropped.
2. Chord test: dropped. Disproportionate for one commented line.
3. smart-splits: rejected (adds more than it removes). nvim socket lookup fixed instead.
4. Deploy hash record: done. PowerToys: only Command Palette enabled (done).
