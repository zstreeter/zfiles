#!/usr/bin/env bash
# Bootstrap script for zfiles dotfiles
# Sets up the bare minimum needed to get started with zfiles

# Exit on error, undefined variables, and propagate pipe errors
set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Script location
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Print header
print_header() {
	echo -e "${BOLD}${CYAN}"
	echo "═════════════════════════════════════════════════"
	echo "           ZFILES BOOTSTRAP SCRIPT               "
	echo "═════════════════════════════════════════════════"
	echo -e "${NC}"
	echo "This script will set up the minimum requirements"
	echo "needed to use zfiles dotfiles."
	echo ""
}

# Detect OS
detect_os() {
	if [ -f /etc/os-release ]; then
		# freedesktop.org and systemd
		. /etc/os-release
		OS=$ID
	elif type lsb_release >/dev/null 2>&1; then
		# linuxbase.org
		OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
	elif [ -f /etc/lsb-release ]; then
		# For some versions of Debian/Ubuntu without lsb_release command
		. /etc/lsb-release
		OS=$DISTRIB_ID
	elif [ -f /etc/debian_version ]; then
		# Older Debian/Ubuntu/etc.
		OS="debian"
	elif [ -f /etc/SuSe-release ]; then
		# Older SuSE/etc.
		OS="suse"
	elif [ -f /etc/redhat-release ]; then
		# Older Red Hat, CentOS, etc.
		OS="redhat"
	else
		# Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
		OS=$(uname -s | tr '[:upper:]' '[:lower:]')
	fi
	echo "${OS,,}" # Convert to lowercase
}

# Check if command exists
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Install basic dependencies based on detected OS
install_dependencies() {
	echo -e "${BLUE}Installing basic dependencies...${NC}"

	local os=$(detect_os)

	case "$os" in
	ubuntu | debian | linuxmint | pop | elementary)
		sudo apt-get update
		sudo apt-get install -y git make stow curl wget
		;;
	fedora)
		sudo dnf install -y git make stow curl wget
		;;
	arch | manjaro | endeavouros)
		sudo pacman -Sy --noconfirm git make stow curl wget
		;;
	opensuse | suse)
		sudo zypper install -y git make stow curl wget
		;;
	*)
		echo -e "${YELLOW}Unsupported OS: $os${NC}"
		echo "Please install git, make, stow, curl, and wget manually."
		;;
	esac

	echo -e "${GREEN}Dependencies installed successfully.${NC}"
}

# Check requirements
check_requirements() {
	local missing_deps=()

	for cmd in git make stow curl; do
		if ! command_exists "$cmd"; then
			missing_deps+=("$cmd")
		fi
	done

	if [ ${#missing_deps[@]} -gt 0 ]; then
		echo -e "${YELLOW}Missing required dependencies: ${missing_deps[*]}${NC}"

		read -p "Do you want to install the missing dependencies? [Y/n] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
			install_dependencies
		else
			echo -e "${RED}Please install the missing dependencies manually and run this script again.${NC}"
			exit 1
		fi
	fi
}

# Check for existing installation
check_existing() {
	if [ -d "$HOME/.zfiles" ] && [ "$HOME/.zfiles" != "$SCRIPT_DIR" ]; then
		echo -e "${YELLOW}Existing zfiles installation found at $HOME/.zfiles${NC}"
		echo "This bootstrap script is being run from: $SCRIPT_DIR"

		read -p "Do you want to overwrite the existing installation? [y/N] " -n 1 -r
		echo
		if [[ $REPLY =~ ^[Yy]$ ]]; then
			echo -e "${BLUE}Backing up existing installation...${NC}"
			mv "$HOME/.zfiles" "$HOME/.zfiles.bak.$(date +%Y%m%d%H%M%S)"
		else
			echo -e "${RED}Bootstrap aborted.${NC}"
			exit 1
		fi
	fi
}

# Clone or update repository
setup_repository() {
	# If running from a cloned repo already, just make sure it's up to date
	if [ -d "$SCRIPT_DIR/.git" ]; then
		echo -e "${BLUE}Updating repository...${NC}"
		git -C "$SCRIPT_DIR" pull

		# Create symlink if not running from ~/.zfiles
		if [ "$SCRIPT_DIR" != "$HOME/.zfiles" ]; then
			echo -e "${BLUE}Creating symlink to $HOME/.zfiles...${NC}"
			ln -sf "$SCRIPT_DIR" "$HOME/.zfiles"
		fi
	else
		# Clone the repository
		echo -e "${BLUE}Cloning zfiles repository...${NC}"
		git clone https://github.com/zstreeter/zfiles.git "$HOME/.zfiles"

		# If running from a different location, create a message
		if [ "$SCRIPT_DIR" != "$HOME/.zfiles" ]; then
			echo -e "${YELLOW}Repository cloned to $HOME/.zfiles${NC}"
			echo -e "${YELLOW}This bootstrap script is running from $SCRIPT_DIR${NC}"
			echo -e "${YELLOW}Further operations will use the cloned repository.${NC}"

			# Use the cloned repository for the rest of the script
			SCRIPT_DIR="$HOME/.zfiles"
		fi
	fi

	echo -e "${GREEN}Repository setup complete.${NC}"
}

# Run minimal installation
run_minimal_install() {
	echo -e "${BLUE}Running minimal installation...${NC}"

	# Change to the repository directory
	cd "$SCRIPT_DIR"

	# Run the installer with minimal flag
	./install.sh --minimal

	echo -e "${GREEN}Minimal installation complete.${NC}"
}

# Ask for full installation
ask_full_install() {
	echo
	echo -e "${BOLD}Would you like to continue with the full installation?${NC}"
	echo "This will install:"
	echo "  - Programs from your package manager"
	echo "  - Additional configurations"
	echo "  - Setup your preferred desktop environment"
	echo

	read -p "Continue with full installation? [y/N] " -n 1 -r
	echo
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		echo -e "${BLUE}Running full installation...${NC}"

		# Change to the repository directory
		cd "$SCRIPT_DIR"

		# Run the interactive installer
		./install.sh

		echo -e "${GREEN}Full installation complete.${NC}"
	else
		echo -e "${YELLOW}Skipping full installation.${NC}"
		echo "You can run the full installation later with:"
		echo "  cd ~/.zfiles && ./install.sh"
	fi
}

# Print post-installation message
print_success() {
	echo
	echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
	echo -e "${BOLD}${GREEN}       ******** ******** ** **      ********  ********       ${NC}"
	echo -e "${BOLD}${GREEN}      //////** /**///// /**/**      /**/////  **//////        ${NC}"
	echo -e "${BOLD}${GREEN}           **  /**      /**/**      /**      /**              ${NC}"
	echo -e "${BOLD}${GREEN}          **   /******* /**/**      /******* /*********       ${NC}"
	echo -e "${BOLD}${GREEN}         **    /**////  /**/**      /**////  ////////**       ${NC}"
	echo -e "${BOLD}${GREEN}        **     /**      /**/**      /**             /**       ${NC}"
	echo -e "${BOLD}${GREEN}       ********/**      /**/********/******** ********        ${NC}"
	echo -e "${BOLD}${GREEN}      //////// //       // //////// //////// ////////         ${NC}"
	echo -e "${BOLD}${GREEN}                                                              ${NC}"
	echo -e "${BOLD}${GREEN}        ZFiles bootstrap complete!                            ${NC}"
	echo -e "${BOLD}${GREEN}                                                              ${NC}"
	echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
	echo
	echo -e "${BOLD}What's next?${NC}"
	echo
	echo "  1. Explore available packages:"
	echo "     cd ~/.zfiles && make packages"
	echo
	echo "  2. Install specific configurations:"
	echo "     cd ~/.zfiles && make stow PACKAGES=\"zsh tmux\""
	echo
	echo "  3. Set up your desktop environment:"
	echo "     cd ~/.zfiles && make desktop ENV=sway"
	echo
	echo "  4. Build programs from source:"
	echo "     cd ~/.zfiles && make build"
	echo
	echo "For more options, run: cd ~/.zfiles && make help"
	echo
}

# Main function
main() {
	print_header
	check_requirements
	check_existing
	setup_repository
	run_minimal_install
	ask_full_install
	print_success
}

# Run main function
main
