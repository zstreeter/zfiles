#!/usr/bin/env bash
# Main installation script for zfiles dotfiles
# Designed to be robust, modular, and flexible

# Exit on error, undefined variables, and propagate pipe errors
set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/install.log"

# Source utility functions
source "${SCRIPT_DIR}/install/core/system_detection.sh"
source "${SCRIPT_DIR}/install/core/package_manager.sh"
source "${SCRIPT_DIR}/install/core/stow.sh"

# Configuration
CONFIGS_DIR="${SCRIPT_DIR}"
INSTALL_DIR="${SCRIPT_DIR}/install"
SOURCES_DIR="${SCRIPT_DIR}/sources"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Defaults
MINIMAL=false
FULL=false
DESKTOP_ENV=""
INTERACTIVE=true
SELECTED_PACKAGES=()
INSTALL_FROM_SOURCE=false
INSTALL_PROGRAMS=false
INSTALL_THEMES=false

# Print header
print_header() {
  echo -e "${BOLD}${CYAN}"
  echo "═════════════════════════════════════════════════"
  echo "                  ZFILES SETUP                   "
  echo "═════════════════════════════════════════════════"
  echo -e "${NC}"
  echo "A robust, modular dotfiles management system"
  echo ""
}

# Print help
print_help() {
  echo "Usage: ./install.sh [options]"
  echo ""
  echo "Options:"
  echo "  -h, --help               Show this help message"
  echo "  -m, --minimal            Install minimal set of dotfiles (bash, vim, tmux)"
  echo "  -f, --full               Install all dotfiles"
  echo "  -d, --desktop ENV        Set desktop environment (sway, hyprland)"
  echo "  -n, --non-interactive    Run in non-interactive mode"
  echo "  -s, --source             Build and install programs from source"
  echo "  -p, --programs           Install programs from package manager"
  echo "  -t, --themes             Install themes and icons"
  echo "  -M, --module NAME        Install specific module (can be used multiple times)"
  echo ""
  echo "Examples:"
  echo "  ./install.sh --minimal              # Install minimal setup"
  echo "  ./install.sh --desktop sway         # Install sway desktop environment"
  echo "  ./install.sh --module zsh --module tmux  # Install only zsh and tmux"
  echo ""
  echo "Available modules:"
  list_packages
}

# Parse command line arguments
parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case $1 in
    -h | --help)
      print_help
      exit 0
      ;;
    -m | --minimal)
      MINIMAL=true
      INTERACTIVE=false
      ;;
    -f | --full)
      FULL=true
      INTERACTIVE=false
      ;;
    -d | --desktop)
      if [ -n "${2:-}" ]; then
        DESKTOP_ENV="$2"
        shift
      else
        echo "Error: --desktop requires an environment name"
        exit 1
      fi
      ;;
    -n | --non-interactive)
      INTERACTIVE=false
      ;;
    -s | --source)
      INSTALL_FROM_SOURCE=true
      ;;
    -p | --programs)
      INSTALL_PROGRAMS=true
      ;;
    -t | --themes)
      INSTALL_THEMES=true
      ;;
    -M | --module)
      if [ -n "${2:-}" ]; then
        SELECTED_PACKAGES+=("$2")
        INTERACTIVE=false
        shift
      else
        echo "Error: --module requires a module name"
        exit 1
      fi
      ;;
    *)
      echo "Unknown parameter: $1"
      print_help
      exit 1
      ;;
    esac
    shift
  done

  # If no specific options are provided, default to interactive mode
  if [[ "$MINIMAL" == "false" && "$FULL" == "false" && "${#SELECTED_PACKAGES[@]}" -eq 0 && -z "$DESKTOP_ENV" ]]; then
    INTERACTIVE=true
  fi
}

# Interactive installation
run_interactive_install() {
  # Installation type
  echo "Select installation type:"
  echo "1) Minimal - Basic configuration (bash, vim, tmux)"
  echo "2) Full - Complete configuration (all modules)"
  echo "3) Desktop - Configure a desktop environment"
  echo "4) Custom - Select individual packages"

  local choice
  read -p "Enter choice [1-4]: " choice

  case $choice in
  1)
    MINIMAL=true
    ;;
  2)
    FULL=true
    ;;
  3)
    select_desktop_env
    ;;
  4)
    select_packages
    ;;
  *)
    echo "Invalid choice. Defaulting to minimal installation."
    MINIMAL=true
    ;;
  esac

  # Additional options
  echo ""
  echo "Additional options:"

  read -p "Install programs from package manager? (y/N): " choice
  if [[ "${choice,,}" == "y" ]]; then
    INSTALL_PROGRAMS=true
  fi

  read -p "Build programs from source? (y/N): " choice
  if [[ "${choice,,}" == "y" ]]; then
    INSTALL_FROM_SOURCE=true
  fi

  read -p "Install themes and icons? (y/N): " choice
  if [[ "${choice,,}" == "y" ]]; then
    INSTALL_THEMES=true
  fi
}

# Select desktop environment
select_desktop_env() {
  echo ""
  echo "Select desktop environment:"
  echo "1) Sway"
  echo "2) Hyprland"

  local choice
  read -p "Enter choice [1-2]: " choice

  case $choice in
  1)
    DESKTOP_ENV="sway"
    ;;
  2)
    DESKTOP_ENV="hyprland"
    ;;
  *)
    echo "Invalid choice. Defaulting to Sway."
    DESKTOP_ENV="sway"
    ;;
  esac
}

# Select modules interactively
select_packages() {
  local packages=($(get_all_packages))

  # Sort packages alphabetically
  IFS=$'\n' sorted_packages=($(sort <<<"${packages[*]}"))
  unset IFS

  echo ""
  echo "Select packages to install (space-separated numbers, then Enter):"

  for i in "${!sorted_packages[@]}"; do
    local description=""
    local desc_file="${CONFIGS_DIR}/${sorted_packages[$i]}/.description"

    if [ -f "$desc_file" ]; then
      description=$(cat "$desc_file")
    else
      description="Configuration files for ${sorted_packages[$i]}"
    fi

    printf "%3d) %-20s - %s\n" "$((i + 1))" "${sorted_packages[$i]}" "$description"
  done

  local selections
  read -p "Packages (e.g., 1 3 5): " -a selections

  for selection in "${selections[@]}"; do
    if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#sorted_packages[@]}" ]; then
      SELECTED_PACKAGES+=("${sorted_packages[$((selection - 1))]}")
    fi
  done

  if [ ${#SELECTED_PACKAGES[@]} -eq 0 ]; then
    echo "No valid packages selected. Defaulting to minimal installation."
    MINIMAL=true
  fi
}

# Install system dependencies
install_dependencies() {
  echo "┌─ Installing system dependencies ─────────────────────┐"

  # Determine package list based on installation type
  local pkg_list="${INSTALL_DIR}/packages/base.txt"

  if [[ "$FULL" == "true" || -n "$DESKTOP_ENV" ]]; then
    pkg_list="${INSTALL_DIR}/packages/desktop.txt"
  fi

  if [ -f "$pkg_list" ]; then
    # Get package manager
    local pkg_manager=$(detect_package_manager)

    if [[ "$pkg_manager" != "unknown" ]]; then
      echo "Using package manager: $pkg_manager"

      # Read package list and install packages
      while IFS= read -r pkg; do
        # Skip empty lines and comments
        if [[ -n "$pkg" && ! "$pkg" =~ ^# ]]; then
          echo "Installing $pkg..."
          install_package "$pkg_manager" "$pkg" || true
        fi
      done <"$pkg_list"
    else
      echo "Unsupported package manager. Please install dependencies manually."
      echo "See ${INSTALL_DIR}/packages/ for required packages."
    fi
  else
    echo "Package list not found: $pkg_list"
  fi

  echo "└─────────────────────────────────────────────────────┘"
}

# Determine which packages to install
get_packages_to_install() {
  local packages=()

  if [[ "$MINIMAL" == "true" ]]; then
    # Minimal set of packages
    packages=("bash" "vim" "tmux")
  elif [[ "$FULL" == "true" ]]; then
    # All packages
    packages=($(get_all_packages))
  elif [[ -n "$DESKTOP_ENV" ]]; then
    # Desktop environment specific packages
    if [[ "$DESKTOP_ENV" == "sway" ]]; then
      packages=("sway" "waybar" "mako" "swaylock" "swayr")
    elif [[ "$DESKTOP_ENV" == "hyprland" ]]; then
      packages=("hyprland" "waybar" "mako")
    fi

    # Add basic packages
    packages+=("zsh" "tmux" "bat")
  else
    # Selected packages
    packages=("${SELECTED_PACKAGES[@]}")
  fi

  echo "${packages[@]}"
}

# Install configurations using stow
install_configs() {
  echo "┌─ Installing configuration packages ───────────────────┐"

  # Get packages to install
  local packages=$(get_packages_to_install)

  if [[ -z "$packages" ]]; then
    echo "No packages to install."
    return 0
  fi

  # Install each package
  for package in $packages; do
    stow_package "$package" "$HOME" "$SCRIPT_DIR" "false"
  done

  echo "└─────────────────────────────────────────────────────┘"
}

# Install programs from package manager
run_install_programs() {
  if [[ "$INSTALL_PROGRAMS" != "true" ]]; then
    return 0
  fi

  echo "┌─ Installing programs from package manager ────────────┐"

  local program_script="${SCRIPT_DIR}/programs/install_programs.sh"

  if [ -f "$program_script" ]; then
    bash "$program_script"
  else
    echo "Program installation script not found: $program_script"
  fi

  echo "└─────────────────────────────────────────────────────┘"
}

# Install programs from source
run_install_from_source() {
  if [[ "$INSTALL_FROM_SOURCE" != "true" ]]; then
    return 0
  fi

  echo "┌─ Building programs from source ─────────────────────┐"

  local build_script="${SCRIPT_DIR}/sources/build_from_source.sh"

  if [ -f "$build_script" ]; then
    bash "$build_script"
  else
    echo "Build script not found: $build_script"
  fi

  echo "└─────────────────────────────────────────────────────┘"
}

# Install themes and icons
install_themes() {
  if [[ "$INSTALL_THEMES" != "true" ]]; then
    return 0
  fi

  echo "┌─ Installing themes and icons ─────────────────────┐"

  # Ensure directories exist
  mkdir -p "${HOME}/.local/share/themes"
  mkdir -p "${HOME}/.local/share/icons"

  # Install themes from directory if it exists
  if [ -d "${SCRIPT_DIR}/themes" ]; then
    # Install GTK themes
    if [ -d "${SCRIPT_DIR}/themes/gtk" ]; then
      for theme in "${SCRIPT_DIR}/themes/gtk"/*; do
        if [ -f "$theme" ]; then
          local theme_name=$(basename "$theme")
          echo "Installing GTK theme: $theme_name"

          if [[ "$theme" == *.zip ]]; then
            unzip -qo "$theme" -d "${HOME}/.local/share/themes"
          elif [[ "$theme" == *.tar.xz ]]; then
            tar -xJf "$theme" -C "${HOME}/.local/share/themes"
          fi
        fi
      done
    fi

    # Install icon themes
    if [ -d "${SCRIPT_DIR}/themes/icons" ]; then
      for icon in "${SCRIPT_DIR}/themes/icons"/*; do
        if [ -f "$icon" ]; then
          local icon_name=$(basename "$icon")
          echo "Installing icon theme: $icon_name"

          if [[ "$icon" == *.zip ]]; then
            unzip -qo "$icon" -d "${HOME}/.local/share/icons"
          elif [[ "$icon" == *.tar.xz ]]; then
            tar -xJf "$icon" -C "${HOME}/.local/share/icons" --strip-components=1
          fi
        fi
      done
    fi

    # Set themes if gsettings is available
    if command -v gsettings >/dev/null 2>&1; then
      # Try to set Catppuccin theme if available
      if [ -d "${HOME}/.local/share/themes/Catppuccin-Macchiato-Standard-Lavender-Dark" ]; then
        gsettings set org.gnome.desktop.interface gtk-theme "Catppuccin-Macchiato-Standard-Lavender-Dark"
        echo "GTK theme set to Catppuccin-Macchiato-Standard-Lavender-Dark"
      fi

      # Try to set Sweet Rainbow icons if available
      if [ -d "${HOME}/.local/share/icons/Sweet-Rainbow" ]; then
        gsettings set org.gnome.desktop.interface icon-theme "Sweet-Rainbow"
        echo "Icon theme set to Sweet-Rainbow"
      fi
    fi
  else
    echo "Themes directory not found. Skipping theme installation."
  fi

  echo "└─────────────────────────────────────────────────────┘"
}

# Configure Zsh
configure_zsh() {
  # Only run if zsh package is installed or if we're doing a full installation
  if [[ "$FULL" == "true" || " $(get_packages_to_install) " == *" zsh "* ]]; then
    echo "┌─ Configuring Zsh ──────────────────────────────────┐"

    # Set up ZDOTDIR in /etc/zsh/zshenv
    if [ -d "/etc/zsh" ]; then
      echo "Setting ZDOTDIR in /etc/zsh/zshenv..."

      if sudo bash -c "cat > /etc/zsh/zshenv" <<'EOF'; then
# zsh cleanup
ZDOTDIR=$HOME/.config/zsh
EOF

        echo "ZDOTDIR set successfully"
      else
        echo "Failed to set ZDOTDIR, please set it manually"
      fi
    fi

    # Change default shell to Zsh if installed
    if command -v zsh >/dev/null 2>&1; then
      if [[ "$SHELL" != "$(which zsh)" ]]; then
        echo "Changing default shell to Zsh..."

        if chsh -s "$(which zsh)"; then
          echo "Shell changed to Zsh. Changes will take effect after logout"
        else
          echo "Failed to change shell to Zsh"
        fi
      else
        echo "Zsh is already the default shell"
      fi
    else
      echo "Zsh is not installed. Please install it first."
    fi

    echo "└─────────────────────────────────────────────────────┘"
  fi
}

# Configure desktop environment
configure_desktop() {
  if [ -n "$DESKTOP_ENV" ]; then
    echo "┌─ Configuring $DESKTOP_ENV desktop environment ─────┐"

    # Create desktop entry for Sway
    if [[ "$DESKTOP_ENV" == "sway" ]] && [ -d "/usr/share/wayland-sessions" ]; then
      echo "Creating Sway desktop entry"

      if sudo tee /usr/share/wayland-sessions/sway.desktop >/dev/null <<EOF; then
[Desktop Entry]
Comment=An i3-compatible Wayland compositor
Name=Sway
Exec=${HOME}/.local/bin/sway-run
Type=Application
EOF

        echo "Sway desktop entry created successfully"
      else
        echo "Failed to create Sway desktop entry"
      fi

      # Run nwg-launchers installation script if it exists
      if [ -f "${HOME}/.config/nwg-launchers/nwgbar/icons/install.sh" ]; then
        echo "Installing nwg-launchers icons..."
        sudo bash "${HOME}/.config/nwg-launchers/nwgbar/icons/install.sh"
      fi
    fi

    # Create qutebrowser script if qutebrowser directory exists
    if [ -d "${HOME}/.software/qutebrowser" ]; then
      echo "Creating qutebrowser script"

      if sudo tee /usr/local/bin/qutebrowser >/dev/null <<EOF; then
#!/usr/bin/env bash
pushd ${HOME}/.software/qutebrowser/ > /dev/null 2>&1
.venv/bin/python3 -m qutebrowser "\$@"
popd > /dev/null 2>&1
EOF

        sudo chmod +x /usr/local/bin/qutebrowser
        echo "Qutebrowser script created successfully"
      else
        echo "Failed to create qutebrowser script"
      fi
    fi

    echo "└─────────────────────────────────────────────────────┘"
  fi
}

# Print success message
print_success() {
  echo ""
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
  echo -e "${BOLD}${GREEN}        ZFiles installation complete!                        ${NC}"
  echo -e "${BOLD}${GREEN}                                                              ${NC}"

  if [[ -n "$DESKTOP_ENV" ]]; then
    echo -e "${BOLD}${GREEN}    You can log in to your ${DESKTOP_ENV} and enjoy a better    ${NC}"
    echo -e "${BOLD}${GREEN}    desktop environment!                                      ${NC}"
    echo -e "${BOLD}${GREEN}                                                              ${NC}"
  fi

  # Suggest running xdg-ninja
  if [ -d "${HOME}/.software/xdg-ninja" ]; then
    echo -e "${BOLD}${GREEN}    Run xdg-ninja to check how clean \$HOME is after           ${NC}"
    echo -e "${BOLD}${GREEN}    everything is set up                                      ${NC}"
  fi

  echo -e "${BOLD}${GREEN}══════════════════════════════════════════════════════${NC}"
}

# Main function
main() {
  # Initialize log file
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "=== ZFiles Installation Log ($(date)) ===" >"$LOG_FILE"

  print_header
  parse_args "$@"

  if [[ "$INTERACTIVE" == "true" ]]; then
    run_interactive_install
  fi

  # Install packages
  if [[ "$INSTALL_PROGRAMS" == "true" ]]; then
    run_install_programs
  fi

  # Install dependencies
  install_dependencies

  # Install configurations
  install_configs

  # Build programs from source
  if [[ "$INSTALL_FROM_SOURCE" == "true" ]]; then
    run_install_from_source
  fi

  # Install themes
  if [[ "$INSTALL_THEMES" == "true" ]]; then
    install_themes
  fi

  # Configure zsh
  configure_zsh

  # Configure desktop
  if [[ -n "$DESKTOP_ENV" ]]; then
    configure_desktop
  fi

  print_success
}

# Run main function
main "$@"
