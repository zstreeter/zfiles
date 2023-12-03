#!/bin/sh

sudo apt update

# alacritty
sudo add-apt-repository ppa:mmstick76/alacritty
sudo apt install alacritty

bash ./programs/install_programs.sh

# eza
sudo mkdir -p /etc/apt/keyrings
wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
sudo apt update
sudo apt install -y eza

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
stow nwg-drawer

stow nwg-launchers
sudo $HOME/.config/nwg-launchers/nwgbar/icons/install.sh

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

# create sudo qutebrowser script
QUTEBROWSER_SCRIPT=/usr/bin/local/qutebrowser
cat <<EOL >"$QUTEBROWSER_SCRIPT"
#!/usr/bin/env bash
pushd $HOME/.software/qutebrowser/
.venv/bin/python3 -m qutebrowser "$@"
EOL
chmod +x "$QUTEBROWSER_SCRIPT"

# Theme
mkdir $HOME/.local/share/themes
curl -O https://github.com/catppuccin/gtk/releases/Catppuccin-Frappe-Standard-Blue-Dark.zip $HOME/.local/share/themes/catppuccin.zip
pushd $HOME/.local/share/themes/catppuccin.zip && unzip catppuccin.zip
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Frappe-Standard-Blue-Dark"

# Icons
mkdir $HOME/.local/share/icons
tar -xvf ./icons/candy-icons.tar.xz && mv candy-icons $HOME/.local/share/icons
tar -xvf ./icons/Sweet-Rainbow.tar.xz && mv Sweet-Rainbow $HOME/.local/share/icons
gsettings set org.gnome.desktop.interface icon theme "Sweet-Rainbow"

