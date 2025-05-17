#!/usr/bin/env bash
# GNU Stow utilities for zfiles dotfiles

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Script directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BACKUP_DIR="${HOME}/.zfiles_backup"

# Logging functions
log_info() {
	echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
	echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
	echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_debug() {
	echo -e "${BLUE}[DEBUG]${NC} $1"
}

# Check if stow is installed
check_stow() {
	if ! command -v stow &>/dev/null; then
		log_error "GNU Stow is not installed. Please install it first."
		return 1
	fi
	return 0
}

# Validate a package name
validate_package() {
	local package="$1"

	if [[ -z "$package" ]]; then
		log_error "Package name cannot be empty"
		return 1
	fi

	if [[ ! -d "${PARENT_DIR}/${package}" ]]; then
		log_error "Package not found: ${package}"
		return 1
	fi

	return 0
}

# Get all available packages
get_all_packages() {
	local exclude_dirs=(".git" ".github" "install" "programs" "sources" "themes")
	local packages=()

	while IFS= read -r -d '' dir; do
		local pkg_name=$(basename "$dir")

		# Skip excluded directories
		if [[ " ${exclude_dirs[*]} " == *" $pkg_name "* ]]; then
			continue
		fi

		packages+=("$pkg_name")
	done < <(find "$PARENT_DIR" -maxdepth 1 -mindepth 1 -type d -print0)

	# Sort alphabetically
	IFS=$'\n' sorted_packages=($(sort <<<"${packages[*]}"))
	unset IFS

	echo "${sorted_packages[@]}"
}

# Backup a file or directory
backup_file() {
	local target="$1"
	local timestamp=$(date +%Y%m%d%H%M%S)
	local backup_path="${BACKUP_DIR}/${timestamp}"

	# Skip if target doesn't exist
	if [[ ! -e "$target" ]]; then
		return 0
	fi

	# Create backup directory
	mkdir -p "$backup_path"

	# Get relative path from HOME
	local rel_path="${target#$HOME/}"
	local backup_target="${backup_path}/${rel_path}"

	# Create parent directories
	mkdir -p "$(dirname "$backup_target")"

	# Copy the file/directory
	cp -a "$target" "$backup_target"

	log_info "Backed up: $target -> $backup_target"
	return 0
}

# Check for conflicts when stowing a package
check_conflicts() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"

	if ! validate_package "$package"; then
		return 1
	fi

	log_debug "Checking for conflicts in package: $package"

	# Use stow --no to simulate stow operation
	local conflicts=$(stow --no --verbose=2 -d "$stow_dir" -t "$target" "$package" 2>&1 | grep -E "existing target is|not owned by any package")

	if [[ -n "$conflicts" ]]; then
		log_warn "Conflicts detected for package $package:"
		echo "$conflicts"
		return 1
	fi

	return 0
}

# Get a list of conflicting files for a package
get_conflict_files() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"

	if ! validate_package "$package"; then
		return 1
	fi

	# Use stow --no to simulate stow operation
	local conflicts=$(stow --no --verbose=2 -d "$stow_dir" -t "$target" "$package" 2>&1 | grep -E "existing target is|not owned by any package")

	# Extract file paths
	local files=()
	while IFS= read -r line; do
		if [[ "$line" =~ existing[[:space:]]+target[[:space:]]+is[[:space:]]+([^:]+):[[:space:]]+(.*) ]]; then
			files+=("${BASH_REMATCH[2]}")
		elif [[ "$line" =~ existing[[:space:]]+target[[:space:]]+is[[:space:]]+not[[:space:]]+owned[[:space:]]+by[[:space:]]+any[[:space:]]+package:[[:space:]]+(.*) ]]; then
			files+=("${BASH_REMATCH[1]}")
		fi
	done <<<"$conflicts"

	# Return the list of files
	echo "${files[@]}"
}

# Backup and remove conflicting files
handle_conflicts() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"

	# Get conflicting files
	local conflict_files=($(get_conflict_files "$package" "$target" "$stow_dir"))

	if [[ ${#conflict_files[@]} -eq 0 ]]; then
		return 0
	fi

	log_warn "Found ${#conflict_files[@]} conflicting files for package $package"

	# Backup and remove each conflicting file
	for file in "${conflict_files[@]}"; do
		if [[ -e "$file" ]]; then
			backup_file "$file"

			if [[ -d "$file" && ! -L "$file" ]]; then
				# For directories, we don't remove them completely because
				# they might contain other files not managed by stow
				log_debug "Conflicting directory: $file (not removing)"
			else
				# For regular files or symlinks, remove them
				log_debug "Removing conflicting file: $file"
				rm -f "$file"
			fi
		fi
	done

	return 0
}

# Stow a package
stow_package() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"
	local force="${4:-false}"

	if ! check_stow; then
		return 1
	fi

	if ! validate_package "$package"; then
		return 1
	fi

	log_info "Stowing package: $package"

	# Check for conflicts
	if [[ "$force" != "true" ]] && ! check_conflicts "$package" "$target" "$stow_dir"; then
		if [[ -t 0 ]]; then # Check if script is running interactively
			read -p "Conflicts detected. Would you like to backup and resolve them? [y/N] " -n 1 -r
			echo
			if [[ $REPLY =~ ^[Yy]$ ]]; then
				handle_conflicts "$package" "$target" "$stow_dir"
			else
				log_error "Aborting stow operation for package: $package"
				return 1
			fi
		else
			log_error "Non-interactive mode - aborting stow operation for package: $package"
			return 1
		fi
	fi

	# Run pre-install script if it exists
	local pre_install="${stow_dir}/${package}/.pre-install.sh"
	if [[ -f "$pre_install" ]]; then
		log_info "Running pre-install script for $package"
		bash "$pre_install"
	fi

	# Perform the stow operation
	log_debug "Running: stow -d \"$stow_dir\" -t \"$target\" \"$package\""
	if stow -d "$stow_dir" -t "$target" "$package"; then
		log_info "Successfully stowed package: $package"

		# Run post-install script if it exists
		local post_install="${stow_dir}/${package}/.post-install.sh"
		if [[ -f "$post_install" ]]; then
			log_info "Running post-install script for $package"
			bash "$post_install"
		fi

		return 0
	else
		log_error "Failed to stow package: $package"
		return 1
	fi
}

# Unstow a package
unstow_package() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"

	if ! check_stow; then
		return 1
	fi

	if ! validate_package "$package"; then
		return 1
	fi

	log_info "Unstowing package: $package"

	# Perform the unstow operation
	if stow -D -d "$stow_dir" -t "$target" "$package"; then
		log_info "Successfully unstowed package: $package"
		return 0
	else
		log_error "Failed to unstow package: $package"
		return 1
	fi
}

# Restow a package (unstow and then stow again)
restow_package() {
	local package="$1"
	local target="${2:-$HOME}"
	local stow_dir="${3:-$PARENT_DIR}"
	local force="${4:-false}"

	if ! check_stow; then
		return 1
	fi

	if ! validate_package "$package"; then
		return 1
	fi

	log_info "Restowing package: $package"

	# Unstow first
	if ! unstow_package "$package" "$target" "$stow_dir"; then
		log_warn "Failed to unstow package: $package. Continuing with stow..."
	fi

	# Then stow again
	if stow_package "$package" "$target" "$stow_dir" "$force"; then
		log_info "Successfully restowed package: $package"
		return 0
	else
		log_error "Failed to restow package: $package"
		return 1
	fi
}

# Stow multiple packages
stow_packages() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"
	local force="${3:-false}"
	shift 3

	local packages=("$@")
	local success=true

	for package in "${packages[@]}"; do
		if ! stow_package "$package" "$target" "$stow_dir" "$force"; then
			success=false
		fi
	done

	if [ "$success" = true ]; then
		log_info "Successfully stowed all packages"
		return 0
	else
		log_error "Failed to stow some packages"
		return 1
	fi
}

# Unstow multiple packages
unstow_packages() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"
	shift 2

	local packages=("$@")
	local success=true

	for package in "${packages[@]}"; do
		if ! unstow_package "$package" "$target" "$stow_dir"; then
			success=false
		fi
	done

	if [ "$success" = true ]; then
		log_info "Successfully unstowed all packages"
		return 0
	else
		log_error "Failed to unstow some packages"
		return 1
	fi
}

# Restow multiple packages
restow_packages() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"
	local force="${3:-false}"
	shift 3

	local packages=("$@")
	local success=true

	for package in "${packages[@]}"; do
		if ! restow_package "$package" "$target" "$stow_dir" "$force"; then
			success=false
		fi
	done

	if [ "$success" = true ]; then
		log_info "Successfully restowed all packages"
		return 0
	else
		log_error "Failed to restow some packages"
		return 1
	fi
}

# Stow all packages
stow_all() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"
	local force="${3:-false}"

	log_info "Stowing all packages..."

	# Get all packages
	local packages=($(get_all_packages))

	if [ ${#packages[@]} -eq 0 ]; then
		log_error "No packages found"
		return 1
	fi

	log_info "Found ${#packages[@]} packages: ${packages[*]}"

	# Stow all packages
	stow_packages "$target" "$stow_dir" "$force" "${packages[@]}"
}

# Unstow all packages
unstow_all() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"

	log_info "Unstowing all packages..."

	# Get all packages
	local packages=($(get_all_packages))

	if [ ${#packages[@]} -eq 0 ]; then
		log_error "No packages found"
		return 1
	fi

	log_info "Found ${#packages[@]} packages: ${packages[*]}"

	# Unstow all packages
	unstow_packages "$target" "$stow_dir" "${packages[@]}"
}

# Restow all packages
restow_all() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"
	local force="${3:-false}"

	log_info "Restowing all packages..."

	# Get all packages
	local packages=($(get_all_packages))

	if [ ${#packages[@]} -eq 0 ]; then
		log_error "No packages found"
		return 1
	fi

	log_info "Found ${#packages[@]} packages: ${packages[*]}"

	# Restow all packages
	restow_packages "$target" "$stow_dir" "$force" "${packages[@]}"
}

# Create a new package
create_package() {
	local package="$1"
	local description="${2:-Configuration files for $package}"

	if [[ -z "$package" ]]; then
		log_error "Package name cannot be empty"
		return 1
	fi

	if [[ -d "${PARENT_DIR}/${package}" ]]; then
		log_error "Package already exists: ${package}"
		return 1
	fi

	log_info "Creating new package: $package"

	# Create package directory
	mkdir -p "${PARENT_DIR}/${package}"

	# Create description file
	echo "$description" >"${PARENT_DIR}/${package}/.description"

	# Create README file
	cat >"${PARENT_DIR}/${package}/README.md" <<EOF
# $package

$description

## Installation

$()$(
		bash
		cd /path/to/zfiles
		stow $package
	)$()

## Files

This package contains:

- (List files here)

## Configuration

(Add configuration instructions here)
EOF

	log_info "Package created: ${package}"
	log_info "Add your configuration files to: ${PARENT_DIR}/${package}"
	log_info "Remember to maintain the appropriate directory structure for your home directory."

	return 0
}

# Display stowed packages
list_stowed() {
	local target="${1:-$HOME}"
	local stow_dir="${2:-$PARENT_DIR}"

	if ! check_stow; then
		return 1
	fi

	log_info "Listing stowed packages..."

	# Get all packages
	local all_packages=($(get_all_packages))
	local stowed_packages=()

	# Check each package
	for package in "${all_packages[@]}"; do
		# Stow has no built-in way to check if a package is stowed
		# We'll check if any of the top-level files/dirs in the package are symlinked in target
		local package_dir="${stow_dir}/${package}"
		local is_stowed=false

		while IFS= read -r -d '' item; do
			local item_basename=$(basename "$item")
			local target_item="${target}/${item_basename}"

			if [[ -L "$target_item" ]]; then
				local link_target=$(readlink "$target_item")
				if [[ "$link_target" == "$item" || "$link_target" == *"${package}/${item_basename}" ]]; then
					is_stowed=true
					break
				fi
			fi
		done < <(find "$package_dir" -maxdepth 1 -mindepth 1 -print0)

		if [[ "$is_stowed" == "true" ]]; then
			stowed_packages+=("$package")
		fi
	done

	if [ ${#stowed_packages[@]} -eq 0 ]; then
		log_info "No packages are currently stowed."
	else
		log_info "Currently stowed packages (${#stowed_packages[@]}):"
		for package in "${stowed_packages[@]}"; do
			echo " - $package"
		done
	fi

	return 0
}

# Display available packages
list_packages() {
	local stow_dir="${1:-$PARENT_DIR}"

	log_info "Available packages:"

	# Get all packages
	local packages=($(get_all_packages))

	if [ ${#packages[@]} -eq 0 ]; then
		log_error "No packages found"
		return 1
	fi

	for package in "${packages[@]}"; do
		local desc_file="${stow_dir}/${package}/.description"
		local description=""

		if [[ -f "$desc_file" ]]; then
			description=$(cat "$desc_file")
		else
			description="Configuration files for ${package}"
		fi

		printf " - %-20s - %s\n" "$package" "$description"
	done

	return 0
}

# Main function when script is run directly
main() {
	if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
		local action="${1:-list}"
		shift 1 || true

		case "$action" in
		stow | install)
			if [[ $# -eq 0 ]]; then
				stow_all
			else
				stow_packages "$HOME" "$PARENT_DIR" "false" "$@"
			fi
			;;
		unstow | remove)
			if [[ $# -eq 0 ]]; then
				unstow_all
			else
				unstow_packages "$HOME" "$PARENT_DIR" "$@"
			fi
			;;
		restow | reinstall)
			if [[ $# -eq 0 ]]; then
				restow_all
			else
				restow_packages "$HOME" "$PARENT_DIR" "false" "$@"
			fi
			;;
		force-stow)
			if [[ $# -eq 0 ]]; then
				stow_all "$HOME" "$PARENT_DIR" "true"
			else
				stow_packages "$HOME" "$PARENT_DIR" "true" "$@"
			fi
			;;
		force-restow)
			if [[ $# -eq 0 ]]; then
				restow_all "$HOME" "$PARENT_DIR" "true"
			else
				restow_packages "$HOME" "$PARENT_DIR" "true" "$@"
			fi
			;;
		create)
			if [[ $# -eq 0 ]]; then
				log_error "Package name required"
				echo "Usage: $0 create <package-name> [description]"
				return 1
			else
				local package="$1"
				local description="${2:-Configuration files for $package}"
				create_package "$package" "$description"
			fi
			;;
		list)
			list_packages
			;;
		list-stowed)
			list_stowed
			;;
		help | --help | -h)
			echo "Usage: $0 <action> [arguments]"
			echo ""
			echo "Actions:"
			echo "  stow|install [packages...]     Stow packages (all if none specified)"
			echo "  unstow|remove [packages...]    Unstow packages (all if none specified)"
			echo "  restow|reinstall [packages...] Restow packages (all if none specified)"
			echo "  force-stow [packages...]       Stow packages, resolving conflicts"
			echo "  force-restow [packages...]     Restow packages, resolving conflicts"
			echo "  create <package> [description] Create a new package"
			echo "  list                           List available packages"
			echo "  list-stowed                    List currently stowed packages"
			echo "  help                           Show this help message"
			;;
		*)
			log_error "Unknown action: $action"
			echo "Use '$0 help' for usage information"
			return 1
			;;
		esac
	fi
}

# Run main function when script is executed directly
main "$@"
