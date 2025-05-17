#!/usr/bin/env bash
# Pre-installation script for KMonad module

# Check if user belongs to the input group
if ! groups "$(whoami)" | grep -q "input"; then
  echo "Adding user $(whoami) to the input group..."
  sudo usermod -aG input "$(whoami)"
  echo "You may need to log out and log back in for this change to take effect."
fi

# Create udev rule for KMonad
if [ ! -f /etc/udev/rules.d/99-kmonad.rules ]; then
  echo "Creating KMonad udev rule..."
  echo 'KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/99-kmonad.rules >/dev/null
  sudo udevadm control --reload-rules
  sudo udevadm trigger
fi

# Create systemd service directory if it doesn't exist
mkdir -p "${HOME}/.config/systemd/user"

echo "Pre-installation for KMonad completed successfully."
