#!/usr/bin/env bash
# System detection utilities for zfiles

# Detect the operating system
detect_os() {
	local os=""

	if [[ -f /etc/os-release ]]; then
		# freedesktop.org and systemd
		. /etc/os-release
		os="${ID}"
	elif type lsb_release >/dev/null 2>&1; then
		# linuxbase.org
		os=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
	elif [[ -f /etc/lsb-release ]]; then
		# For some versions of Debian/Ubuntu without lsb_release command
		. /etc/lsb-release
		os="${DISTRIB_ID}"
	elif [[ -f /etc/debian_version ]]; then
		# Older Debian/Ubuntu/etc.
		os="debian"
	elif [[ -f /etc/SuSe-release ]]; then
		# Older SuSE/etc.
		os="suse"
	elif [[ -f /etc/redhat-release ]]; then
		# Older Red Hat, CentOS, etc.
		os="redhat"
	elif command -v sw_vers >/dev/null 2>&1; then
		# macOS
		os="macos"
	else
		# Fall back to uname
		os=$(uname -s | tr '[:upper:]' '[:lower:]')
	fi

	echo "${os}"
}

# Detect the operating system version
detect_os_version() {
	local version=""

	if [[ -f /etc/os-release ]]; then
		# freedesktop.org and systemd
		. /etc/os-release
		version="${VERSION_ID}"
	elif type lsb_release >/dev/null 2>&1; then
		# linuxbase.org
		version=$(lsb_release -sr)
	elif [[ -f /etc/lsb-release ]]; then
		# For some versions of Debian/Ubuntu without lsb_release command
		. /etc/lsb-release
		version="${DISTRIB_RELEASE}"
	elif command -v sw_vers >/dev/null 2>&1; then
		# macOS
		version=$(sw_vers -productVersion)
	else
		# Fall back to uname
		version=$(uname -r)
	fi

	echo "${version}"
}

# Detect desktop environment
detect_desktop_env() {
	local desktop=""

	if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
		desktop="${XDG_CURRENT_DESKTOP,,}" # Convert to lowercase
	elif [[ -n "${DESKTOP_SESSION:-}" ]]; then
		desktop="${DESKTOP_SESSION,,}"
	elif pgrep -x "gnome-shell" >/dev/null; then
		desktop="gnome"
	elif pgrep -x "plasmashell" >/dev/null; then
		desktop="kde"
	elif pgrep -x "xfce4-session" >/dev/null; then
		desktop="xfce"
	elif pgrep -x "sway" >/dev/null; then
		desktop="sway"
	elif pgrep -x "Hyprland" >/dev/null; then
		desktop="hyprland"
	elif pgrep -x "i3" >/dev/null; then
		desktop="i3"
	elif pgrep -x "bspwm" >/dev/null; then
		desktop="bspwm"
	else
		desktop="unknown"
	fi

	echo "${desktop}"
}

# Check if running on Wayland
is_wayland() {
	if [[ "${XDG_SESSION_TYPE:-}" == "wayland" ]]; then
		return 0
	elif [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
		return 0
	else
		return 1
	fi
}

# Check if running on X11
is_x11() {
	if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]]; then
		return 0
	elif [[ -n "${DISPLAY:-}" && -z "${WAYLAND_DISPLAY:-}" ]]; then
		return 0
	else
		return 1
	fi
}

# Check if NVIDIA GPU is present
has_nvidia_gpu() {
	if [[ -d /sys/module/nvidia ]]; then
		return 0
	elif lspci | grep -i nvidia >/dev/null; then
		return 0
	else
		return 1
	fi
}

# Check if AMD GPU is present
has_amd_gpu() {
	if lspci | grep -i amd >/dev/null && lspci | grep -i vga >/dev/null; then
		return 0
	else
		return 1
	fi
}

# Check if Intel GPU is present
has_intel_gpu() {
	if lspci | grep -i intel >/dev/null && lspci | grep -i vga >/dev/null; then
		return 0
	else
		return 1
	fi
}

# Get GPU vendor
get_gpu_vendor() {
	if has_nvidia_gpu; then
		echo "nvidia"
	elif has_amd_gpu; then
		echo "amd"
	elif has_intel_gpu; then
		echo "intel"
	else
		echo "unknown"
	fi
}

# Check if a command exists
command_exists() {
	command -v "$1" >/dev/null 2>&1
}

# Check if running as root
is_root() {
	[[ $EUID -eq 0 ]]
}

# Get system memory in MB
get_system_memory() {
	if command_exists free; then
		free -m | awk '/^Mem:/ {print $2}'
	elif [[ -f /proc/meminfo ]]; then
		awk '/MemTotal/ {print $2 / 1024}' /proc/meminfo
	else
		echo "unknown"
	fi
}

# Get number of CPU cores
get_cpu_cores() {
	if command_exists nproc; then
		nproc
	elif [[ -f /proc/cpuinfo ]]; then
		grep -c ^processor /proc/cpuinfo
	else
		echo "unknown"
	fi
}

# Get CPU model
get_cpu_model() {
	if [[ -f /proc/cpuinfo ]]; then
		grep -m 1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^[ \t]*//'
	else
		echo "unknown"
	fi
}

# Print system information
print_system_info() {
	echo "System Information:"
	echo "  OS: $(detect_os) $(detect_os_version)"
	echo "  Desktop: $(detect_desktop_env)"
	echo "  CPU: $(get_cpu_model) ($(get_cpu_cores) cores)"
	echo "  Memory: $(get_system_memory) MB"
	echo "  GPU: $(get_gpu_vendor)"
	echo "  Wayland: $(is_wayland && echo "Yes" || echo "No")"
	echo "  X11: $(is_x11 && echo "Yes" || echo "No")"
}

# If script is run directly, print system info
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
	print_system_info
fi
