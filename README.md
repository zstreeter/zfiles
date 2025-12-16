# ZFiles - Omarchy Overlay

Personal dotfiles overlay for [Omarchy](https://github.com/basecamp/omarchy), adding zsh, custom keybindings, and additional tools.

## What This Does

This overlay extends Omarchy with:

- **Zsh** - Shell configuration (Omarchy uses bash by default)
- **Keyd** - Caps Lock → Escape (tap) / Super (hold)
- **Hyprland bindings** - Custom keybindings layered on top of Omarchy's defaults
- **Theme integration** - Zathura and Yazi follow Omarchy's theme automatically
- **Neovim** - Personal config synced with Omarchy themes
- **Additional tools** - tmux, yazi, zathura, cura

## Installation

```bash
git clone https://github.com/zstreeter/zfiles.git ~/zfiles
cd ~/zfiles
chmod +x bootstrap.sh
./bootstrap.sh
```

Reboot after installation for keyd to take effect.

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
├── tmux/                 # Tmux config
├── yazi/                 # File manager config
├── zathura/              # PDF viewer config
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
- Zathura (`~/.config/zathura/omarchy-theme`)
- Yazi (`~/.config/yazi/omarchy-theme.toml`)

Make sure your configs include these:

**zathura/zathurarc:**
```bash
include omarchy-theme
```

**yazi/theme.toml:**
```toml
"$include" = "./omarchy-theme.toml"
```

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
7. Installs the theme-set hook for zathura/yazi

## Adding More Packages

To stow additional configs, add a directory with the proper structure:

```
newpkg/
└── .config/
    └── newpkg/
        └── config.toml
```

Then add `newpkg` to `STOW_PACKAGES` in `bootstrap.sh`.
