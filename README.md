# ZFiles - Modular Dotfiles Manager

I finally have a dotfiles repo like a real chad 👨

A robust, modular dotfiles management system optimized for Sway, Hyprland, and other Linux environments.

![ZFiles Banner](https://raw.githubusercontent.com/zstreeter/zfiles/assets/banner.png)

## Overview

ZFiles is a comprehensive dotfiles management system that uses GNU Stow to handle symlinks, providing a clean, modular approach to managing your configuration files. It includes:

- **Configuration Management**: Easily manage and deploy your dotfiles
- **Package Management**: Install required system packages automatically
- **Source Building**: Build and install programs from source
- **Desktop Environment Setup**: Quickly configure Sway or Hyprland
- **KMonad Integration**: Custom keyboard remapping including Caps Lock as Escape/Super

## Quick Start

### First-time Installation

Clone the repository and run the bootstrap script:

```bash
git clone https://github.com/zstreeter/zfiles.git ~/.zfiles
cd ~/.zfiles
./bootstrap.sh
```

For a more customized installation, use the main installer:

```bash
./install.sh
```

### Using Make Commands

The Makefile provides easy access to common operations:

```bash
# Show help
make help

# Install everything
make install

# Install specific packages
make stow PACKAGES="zsh tmux"

# Set up desktop environment
make desktop ENV=sway

# Build programs from source
make build

# List available packages
make packages

# Show status
make status
```

## Directory Structure

```
zfiles/
├── bash/            # Bash configuration files (stowable)
├── zsh/             # Zsh configuration files (stowable)
├── sway/            # Sway configuration files (stowable)
├── ... (other stowable packages)
├── install/         # Installation framework
├── sources/         # Source building scripts
├── programs/        # Program installation scripts
├── install.sh       # Main installation script
├── bootstrap.sh     # Quick start script
└── Makefile         # Simple command interface
```

## Configuration Packages

Each directory at the root level (except for special directories like `install`, `sources`, etc.) is a configuration package that can be stowed independently.

### Available Packages

- **bash**: Bash shell configuration
- **zsh**: Z shell configuration
- **sway**: Sway window manager configuration
- **waybar**: Waybar status bar configuration
- **tmux**: Terminal multiplexer configuration
- **kmonad**: Keyboard configuration with KMonad (Caps as Esc/Super)
- _...and more_

### Installing Packages

```bash
# Using make
make stow PACKAGES="zsh sway waybar"

# Using stow directly
stow zsh sway waybar
```

## Building Programs from Source

ZFiles can build and install various programs from source:

```bash
# Build all programs
make build

# Build specific programs
./sources/build_from_source.sh neovim tmux
```

Available programs include:

- neovim
- qutebrowser
- waybar
- cava
- mako
- kmonad (for custom keyboard mapping)
- ...and many more

## Special Features

### KMonad Configuration

The KMonad configuration is set up to make Caps Lock act as Escape when tapped and Super/Meta when held, using the `tap-next-release` functionality:

```
# Located in kmonad/.config/kmonad/config.kbd
(defalias
  cesc (tap-next-release esc lmet)
)
```

### Desktop Environment Integration

ZFiles includes special setup for Sway and Hyprland:

```bash
# Set up Sway
make desktop ENV=sway

# Set up Hyprland
make desktop ENV=hyprland
```

## Customization

### Modifying Existing Configurations

Simply edit the files in the corresponding package directory. For example, to modify your zsh configuration:

1. Edit files in the `zsh/` directory
2. Run `make restow PACKAGES="zsh"` to update the symlinks

### Adding New Programs

To add a new program to build from source:

1. Add a build function to `sources/build_from_source.sh`
2. Call your function from the main function

To add a new program to install from package manager:

1. Add the package name to `programs/program_list.txt`

## Troubleshooting

### Common Issues

- **Stow Conflicts**: Use `./install/core/stow.sh force-stow PACKAGE` to resolve conflicts automatically
- **Missing Dependencies**: Run `make install` to install core dependencies
- **KMonad Issues**: Ensure your user is in the `input` group, usually requires a logout/login

### Logs

Installation logs can be found in:

- Main installation: `install.log`
- Source builds: `logs/build_*.log`

## Icons

After running the `getnf` program and selecting the Nerd Font you'd like, you have many icons to choose from. Say you want to add an icon for something, you can go [here](https://www.nerdfonts.com/cheat-sheet) and type in the font you'd like. Then click the "icon" button, this will copy to your system clipboard and then you can copy to your terminal. For example all the cool icons in waybar are done this way.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- [GNU Stow](https://www.gnu.org/software/stow/) for symlink management
- [KMonad](https://github.com/kmonad/kmonad) for keyboard configuration
- Various dotfiles communities for inspiration
