# WSL work-laptop install checklist

The user-run document the wayfinder map (issue #3) ends at. This path has
been run end-to-end on the work laptop; this is the reproduction recipe for
a reinstall or a replacement machine. Everything not listed here is done by
`bootstrap.sh` and `wsl/windows/install.ps1`, both idempotent — re-run them
freely.

## 1. Windows prerequisites (manual, once)

- [ ] WSL2 with Ubuntu 24.04: `wsl --install -d Ubuntu-24.04`.
      The distro name must stay `Ubuntu-24.04` — it is hardcoded as
      `default_domain = 'WSL:Ubuntu-24.04'` in `wsl/windows/wezterm/wezterm.lua`.
- [ ] WezTerm — **nightly** build, installed manually (`install.ps1` only
      copies its config). Nightly is what carries the post-2024
      kitty-graphics fixes yazi previews inside herdr need; last stable is
      Feb 2024. If Zscaler blocks the GitHub release, `winget install
      wez.wezterm` (stable) works for everything except graphics.

Everything else Windows-side (AutoHotkey, GlazeWM, PowerToys, sioyek — all
via winget — plus the Caps→F13 scancode map, both logon tasks, Zebar/GlazeWM/
WezTerm/sioyek configs, and `.wslconfig` mirrored networking) is installed by
`install.ps1`, which bootstrap runs for you in step 2.

## 2. Bootstrap (inside WSL)

- [ ] `git clone https://github.com/zstreeter/zfiles.git ~/zfiles && cd ~/zfiles && ./bootstrap.sh`

  What to expect during the run:
  - sudo password for the apt step (the only sudo on this target),
  - **one UAC prompt** from `install.ps1` for the Caps Lock scancode map
    (only on a run that changes it; an existing foreign map is backed up to
    the `Scancode Map.zfiles-bak` registry value),
  - a stale `zfiles-kanata` logon task from the kanata era is removed
    automatically.

## 3. Post-bootstrap (manual, once)

- [ ] **Reboot Windows** — the Caps→F13 driver remap only loads at boot.
      Until then `caps.ahk` bridges CapsLock directly, so Caps chords
      already work, but the lock state can still latch.
- [ ] `wsl --shutdown` (from PowerShell), then reopen WezTerm — applies
      `networkingMode=mirrored`, without which `herdr-navd` cannot reach
      GlazeWM's IPC on `127.0.0.1:6123` and Caps+hjkl stops at the WM layer.
- [ ] Fill in API keys: `~/.config/shell/secrets.env` (created by bootstrap,
      gitignored, chmod 600).
- [ ] If signed commits are needed: import the GPG key
      (`gpg --import`; pinentry-curses is already configured).

## 4. Verify

- [ ] Caps tap = Esc; Caps held + `h/j/k/l` walks nvim splits → herdr panes
      → GlazeWM windows (the reply layer is in `herdr-navd`'s response if a
      move ever does nothing).
- [ ] `systemctl --user status herdr-navd` — running on `127.0.0.1:6224`.
- [ ] Caps+Space opens PowerToys Run and the launched app lands on the
      *focused* workspace (the `/launch` claim).
- [ ] Caps+Return opens WezTerm straight into WSL; Caps+1..0, Caps+Shift+hjkl
      behave per `wsl/windows/PARITY.md`.
- [ ] Graphics, cheapest test first: `wezterm imgcat <some.png>` in WSL, then
      yazi previews inside herdr. If previews mis-scale over the default
      wsl.exe route, set up sshd in WSL and use `wezterm ssh 127.0.0.1`
      (the documented seam in wezterm.lua).
- [ ] `sioyek foo.pdf` from a WSL shell opens the *Windows* sioyek, tiled
      (the `winapp` route).

## Troubleshooting

- GlazeWM stops moving one window while managing the rest → restart
  `glazewm.exe` and wait for port 6123 to free up — see the README's
  "When GlazeWM stops moving one window".
- Caps Lock latches → the scancode map isn't loaded (reboot pending or UAC
  was declined); re-run bootstrap and accept the prompt.
- Keybindings work but Caps+hjkl ignores panes/splits → herdr-navd down or
  mirrored networking not applied (`wsl --shutdown`).
- A config edit not reaching Windows → configs are *copied*, not symlinked;
  re-run `./bootstrap.sh` (use `ZFILES_SKIP_PKG=1` to skip the package step).
