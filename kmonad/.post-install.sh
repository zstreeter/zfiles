#!/usr/bin/env bash
# Post-installation script for KMonad module

# Enable and start KMonad service
if command -v systemctl &>/dev/null && [ -f "${HOME}/.config/systemd/user/kmonad.service" ]; then
	echo "Enabling and starting KMonad service..."
	systemctl --user daemon-reload
	systemctl --user enable kmonad.service
	systemctl --user start kmonad.service
	echo "KMonad service enabled and started."
fi

# Check KMonad status
if command -v kmonad &>/dev/null; then
	echo "KMonad is installed and ready to use."
	kmonad --version
else
	echo "KMonad is not installed. Please install it first."
	echo "You can run: cd ~/.zfiles && ./sources/build_from_source.sh kmonad"
fi

echo "Post-installation for KMonad completed successfully."
echo "Remember to restart your computer for changes to take full effect."
