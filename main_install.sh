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
unzip ./icons_themes/Catppuccin-Macchiato-Standard-Lavender-Dark.zip && mv ./icons_themes/Catppuccin-Macchiato-Standard-Lavender-Dark $HOME/.local/share/themes
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Macchiato-Standard-Lavender-Dark"

# Icons
mkdir $HOME/.local/share/icons
tar -xvf ./icons_themes/candy-icons.tar.xz && mv ./icons_themes/candy-icons $HOME/.local/share/icons
tar -xvf ./icons_themes/Sweet-Rainbow.tar.xz && mv ./icons_themes/Sweet-Rainbow $HOME/.local/share/icons
gsettings set org.gnome.desktop.interface icon theme "Sweet-Rainbow"

echo "Run xdg-ninja to check how clean $HOME is after everything is setup"
