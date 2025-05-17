#!/usr/bin/env bash
# Package manager detection and installation utilities for zfiles

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Detect the package manager
detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew"
  elif command -v xbps-install >/dev/null 2>&1; then
    echo "xbps"
  elif command -v emerge >/dev/null 2>&1; then
    echo "emerge"
  else
    echo "unknown"
  fi
}

# Check if a package is installed
is_package_installed() {
  local package="$1"
  local package_manager=$(detect_package_manager)

  case "$package_manager" in
  apt)
    dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q "install ok installed"
    ;;
  dnf | yum)
    rpm -q "$package" &>/dev/null
    ;;
  pacman)
    pacman -Q "$package" &>/dev/null
    ;;
  zypper)
    rpm -q "$package" &>/dev/null
    ;;
  brew)
    brew list "$package" &>/dev/null
    ;;
  xbps)
    xbps-query "$package" &>/dev/null
    ;;
  emerge)
    equery list -i "$package" &>/dev/null
    ;;
  *)
    # Unknown package manager, assume not installed
    return 1
    ;;
  esac
}

# Install a package using the appropriate package manager
install_package() {
  local package_manager="$1"
  local package="$2"

  # Skip if already installed
  if is_package_installed "$package"; then
    echo -e "${GREEN}Package $package is already installed${NC}"
    return 0
  fi

  echo -e "${YELLOW}Installing package: $package${NC}"

  case "$package_manager" in
  apt)
    sudo apt-get update -qq
    sudo apt-get install -y "$package"
    ;;
  dnf)
    sudo dnf install -y "$package"
    ;;
  yum)
    sudo yum install -y "$package"
    ;;
  pacman)
    sudo pacman -S --noconfirm "$package"
    ;;
  zypper)
    sudo zypper install -y "$package"
    ;;
  brew)
    brew install "$package"
    ;;
  xbps)
    sudo xbps-install -y "$package"
    ;;
  emerge)
    sudo emerge --ask=n "$package"
    ;;
  *)
    echo -e "${RED}Unknown package manager. Cannot install $package${NC}"
    return 1
    ;;
  esac

  # Verify installation
  if is_package_installed "$package"; then
    echo -e "${GREEN}Package $package installed successfully${NC}"
    return 0
  else
    echo -e "${RED}Failed to install package $package${NC}"
    return 1
  fi
}

# Install AUR packages (for Arch Linux)
install_aur_package() {
  local package="$1"

  # Check if we're on Arch Linux
  if ! command -v pacman >/dev/null 2>&1; then
    echo -e "${RED}Not an Arch-based system, cannot install AUR package: $package${NC}"
    return 1
  fi

  # Skip if already installed
  if is_package_installed "$package"; then
    echo -e "${GREEN}AUR package $package is already installed${NC}"
    return 0
  fi

  echo -e "${YELLOW}Installing AUR package: $package${NC}"

  # Find an AUR helper
  local aur_helper=""
  for helper in yay paru trizen pamac; do
    if command -v "$helper" >/dev/null 2>&1; then
      aur_helper="$helper"
      break
    fi
  done

  # Install AUR helper if needed
  if [[ -z "$aur_helper" ]]; then
    echo -e "${YELLOW}No AUR helper found. Installing yay...${NC}"

    # Install dependencies
    sudo pacman -S --needed --noconfirm git base-devel

    # Create temporary directory
    local temp_dir=$(mktemp -d)

    # Clone yay
    git clone https://aur.archlinux.org/yay.git "$temp_dir" || {
      echo -e "${RED}Failed to clone yay repository${NC}"
      rm -rf "$temp_dir"
      return 1
    }

    # Build and install yay
    (cd "$temp_dir" && makepkg -si --noconfirm) || {
      echo -e "${RED}Failed to build and install yay${NC}"
      rm -rf "$temp_dir"
      return 1
    }

    # Clean up
    rm -rf "$temp_dir"

    if command -v yay >/dev/null 2>&1; then
      aur_helper="yay"
    else
      echo -e "${RED}Failed to install AUR helper${NC}"
      return 1
    fi
  fi

  # Install package using AUR helper
  case "$aur_helper" in
  yay)
    yay -S --needed --noconfirm "$package"
    ;;
  paru)
    paru -S --needed --noconfirm "$package"
    ;;
  trizen)
    trizen -S --needed --noconfirm "$package"
    ;;
  pamac)
    pamac build --no-confirm "$package"
    ;;
  esac

  # Verify installation
  if is_package_installed "$package"; then
    echo -e "${GREEN}AUR package $package installed successfully${NC}"
    return 0
  else
    echo -e "${RED}Failed to install AUR package $package${NC}"
    return 1
  fi
}

# Install packages from a file
install_packages_from_file() {
  local file="$1"
  local package_manager=$(detect_package_manager)

  if [[ ! -f "$file" ]]; then
    echo -e "${RED}File not found: $file${NC}"
    return 1
  fi

  echo -e "${GREEN}Installing packages from $file${NC}"

  while IFS= read -r package; do
    # Skip empty lines and comments
    if [[ -n "$package" && ! "$package" =~ ^# ]]; then
      install_package "$package_manager" "$package"
    fi
  done <"$file"

  echo -e "${GREEN}Finished installing packages from $file${NC}"
  return 0
}

# Update all packages
update_system() {
  local package_manager=$(detect_package_manager)

  echo -e "${GREEN}Updating system using $package_manager${NC}"

  case "$package_manager" in
  apt)
    sudo apt-get update
    sudo apt-get upgrade -y
    ;;
  dnf)
    sudo dnf upgrade -y
    ;;
  yum)
    sudo yum update -y
    ;;
  pacman)
    sudo pacman -Syu --noconfirm
    ;;
  zypper)
    sudo zypper update -y
    ;;
  brew)
    brew update
    brew upgrade
    ;;
  xbps)
    sudo xbps-install -Su
    ;;
  emerge)
    sudo emerge --update --deep --newuse @world
    ;;
  *)
    echo -e "${RED}Unknown package manager. Cannot update system${NC}"
    return 1
    ;;
  esac

  echo -e "${GREEN}System update completed${NC}"
  return 0
}

# Get PPA support (for Ubuntu/Debian)
has_ppa_support() {
  local package_manager=$(detect_package_manager)

  if [[ "$package_manager" == "apt" ]]; then
    if command -v add-apt-repository >/dev/null 2>&1; then
      return 0
    else
      return 1
    fi
  else
    return 1
  fi
}

# Add a PPA repository (Ubuntu/Debian)
add_ppa() {
  local ppa="$1"

  if ! has_ppa_support; then
    echo -e "${RED}PPA not supported on this system${NC}"
    return 1
  fi

  echo -e "${YELLOW}Adding PPA: $ppa${NC}"

  # Ensure add-apt-repository is installed
  if ! command -v add-apt-repository >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y software-properties-common
  fi

  # Add the PPA
  sudo add-apt-repository -y "ppa:$ppa"
  sudo apt-get update -qq

  echo -e "${GREEN}PPA added successfully: $ppa${NC}"
  return 0
}

# Add repository key (Debian/Ubuntu)
add_apt_key() {
  local key_url="$1"

  if [[ "$(detect_package_manager)" != "apt" ]]; then
    echo -e "${RED}APT keys not supported on this system${NC}"
    return 1
  fi

  echo -e "${YELLOW}Adding APT key from: $key_url${NC}"

  # Ensure curl is installed
  if ! command -v curl >/dev/null 2>&1; then
    sudo apt-get update -qq
    sudo apt-get install -y curl
  fi

  # Add the key
  curl -fsSL "$key_url" | sudo apt-key add -

  echo -e "${GREEN}APT key added successfully${NC}"
  return 0
}

# Add apt repository (Debian/Ubuntu)
add_apt_repository() {
  local repo="$1"

  if [[ "$(detect_package_manager)" != "apt" ]]; then
    echo -e "${RED}APT repositories not supported on this system${NC}"
    return 1
  fi

  echo -e "${YELLOW}Adding APT repository: $repo${NC}"

  # Add the repository
  echo "$repo" | sudo tee -a /etc/apt/sources.list.d/custom.list
  sudo apt-get update -qq

  echo -e "${GREEN}APT repository added successfully${NC}"
  return 0
}
