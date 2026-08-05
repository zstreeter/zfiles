# ZFiles - Omarchy Overlay

Personal dotfiles overlay for [Omarchy](https://github.com/basecamp/omarchy), adding zsh, custom keybindings, and additional tools.

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

`bootstrap.sh` detects three orthogonal facts and gates every step on them:

- **Omarchy** (`~/.config/omarchy/` or `~/.local/share/omarchy/` exists) —
  full overlay: core + Hyprland bindings, keyd, theme hooks, himalaya/mirador,
  cura/sioyek/xdg/wireplumber, docker.
- **WSL** (`/proc/version` mentions Microsoft) — core packages via apt + mise
  (`pkglist-ubuntu.txt`; neovim/yazi/go/rust/bun/opencode via mise since noble
  is stale or missing them), pinentry-curses, and — once present — a
  `windows/install.ps1` hook that wires up the Windows side (kanata caps-lock
  remap, GlazeWM, WezTerm).
- **Package manager** (pacman vs apt) — picks the install branch in step 1.

Core packages on every target:

| Package    | Purpose                            |
|------------|------------------------------------|
| `zsh`      | Shell config                       |
| `yazi`     | File manager                       |
| `herdr`    | Terminal workspace manager         |
| `opencode` | opencode agent config              |
| `pi`       | pi agent config                    |
| `scripts`  | `new-research-project`, `publish-post` helpers + vault template |

Skipped without Omarchy: Hyprland source, keyd, theme-set hook,
mirador/himalaya email tools, docker, and the desktop/hardware packages
(cura, sioyek, xdg, wireplumber).

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
├── bootstrap.sh          # Main installer
├── pkglist.txt           # Packages to install
├── hooks/
│   └── theme-set         # Generates theme configs when Omarchy theme changes
├── root_etc/
│   └── keyd/
│       └── default.conf  # Caps Lock remapping
├── hypr/                 # Hyprland custom bindings
├── yazi/                 # File manager config
├── sioyek/               # PDF viewer config
├── zsh/                  # Shell config
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

### Theme Integration

When you change Omarchy's theme, the `theme-set` hook automatically generates configs for:
- Sioyek — appends a `# zfiles-theme` block to `~/.config/sioyek/prefs_user.config`
- Yazi — the rendered theme is exposed as the `omarchy` flavor
  (`~/.config/yazi/flavors/omarchy.yazi/flavor.toml`), which `yazi/theme.toml`
  selects via `[flavor] dark = "omarchy"`.

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

1. Installs packages from `pkglist.txt`
2. Configures keyd and enables the service
3. Sets up zsh with XDG directories
4. Clones neovim config and symlinks Omarchy theme
5. Stows all dotfile packages
6. Adds `zfilesbindings.conf` source to Hyprland config
7. Installs the theme-set hook for sioyek/yazi

## Adding More Packages

To stow additional configs, add a directory with the proper structure:

```
newpkg/
└── .config/
    └── newpkg/
        └── config.toml
```

Then add `newpkg` to `STOW_PACKAGES` in `bootstrap.sh`.
