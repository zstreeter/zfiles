#!/bin/sh

sudo apt update

# alacritty
sudo add-apt-repository ppa:mmstick76/alacritty
sudo apt install alacritty

sudo apt install stow

bash ./programs/install_programs.sh

stow scripts
bash $HOME/.local/bin/install.sh

stow alacritty
stow bat
stow btop
stow cava
stow kmonad
stow lf
stow mako
stow neofetch
stow newsboat
stow npm
stow nwg-bar
stow nwg-drawer
stow nwg-launchers
stow nwg-look
stow nwgbar-icons
stow qutebrowser
stow sway
stow swaylock
stow swayr
stow tmux
stow waybar
stow wget
stow zathura
stow zsh

# rust
sudo curl https://sh.rustup.rs -sSf | sh
