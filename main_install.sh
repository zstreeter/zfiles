#!/bin/sh

export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"

sudo apt update

# Install programs
bash ./programs/install_programs.sh

# Check if zsh is installed
if command -v zsh >/dev/null 2>&1; then
    echo "Switching to zsh..."
    exec zsh
else
    echo "zsh is not installed."
fi

stow wezterm bat btop cava kmonad yazi mako neofetch newsboat npm nwg-drawer nwg-launchers qutebrowser sway swaylock swayr tmux waybar wget zathura zsh

# Stow installs
stow scripts
bash $HOME/.local/bin/install.sh

# Run the nwg-launchers installation script
sudo bash "$HOME/.config/nwg-launchers/nwgbar/icons/install.sh"

# Create qutebrowser script with sudo permissions
QUTEBROWSER_SCRIPT="/usr/local/bin/qutebrowser"
sudo tee "$QUTEBROWSER_SCRIPT" > /dev/null <<EOL
#!/usr/bin/env bash
pushd $HOME/.software/qutebrowser/ > /dev/null 2>&1
.venv/bin/python3 -m qutebrowser "\$@"
popd > /dev/null 2>&1
EOL
sudo chmod +x "$QUTEBROWSER_SCRIPT"

# Theme setup
mkdir -p $HOME/.local/share/themes
unzip -d $HOME/.local/share/themes ./icons_themes/Catppuccin-Macchiato-Standard-Lavender-Dark.zip
gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Macchiato-Standard-Lavender-Dark"

# Icons setup
mkdir -p $HOME/.local/share/icons
tar -xvf ./icons_themes/candy-icons.tar.xz -C $HOME/.local/share/icons --strip-components=1
tar -xvf ./icons_themes/Sweet-Rainbow.tar.xz -C $HOME/.local/share/icons --strip-components=1
gsettings set org.gnome.desktop.interface icon-theme "Sweet-Rainbow"

# Zsh environment cleanup
sudo tee -a /etc/zsh/zshenv > /dev/null <<EOF
# zsh cleanup
ZDOTDIR=$HOME/.config/zsh
EOF

# Final message
echo "=============================================================="
echo "                                                              "
echo "       ******** ******** ** **       ********  ********       "
echo "      //////** /**///// /**/**      /**/////  **//////        "
echo "           **  /**      /**/**      /**      /**              "
echo "          **   /******* /**/**      /******* /*********       "
echo "         **    /**////  /**/**      /**////  ////////**       "
echo "        **     /**      /**/**      /**             /**       "
echo "       ********/**      /**/********/******** ********        "
echo "      //////// //       // //////// //////// ////////         "
echo "                                                              "
echo "        ZFiles installed successfully!                        "
echo "                                                              "
echo "    You can log in to your sway account and enjoy a better    "
echo "    desktop environment!                                      "
echo "                                                              "
echo "    Run xdg-ninja to check how clean $HOME is after           "
echo "    everything is set up                                      "
echo "=============================================================="
