# ZFiles Makefile
# Provides simple commands for managing your dotfiles

.PHONY: help install update uninstall reinstall build programs themes desktop packages list status stow unstow restow create-package clean

# Colors
YELLOW = \033[1;33m
GREEN = \033[1;32m
RED = \033[1;31m
BLUE = \033[1;34m
NC = \033[0m

# Variables
SHELL := /bin/bash
PWD := $(shell pwd)
PACKAGES ?= 

# Default target
help:
	@echo -e "$(GREEN)ZFiles Dotfiles Management$(NC)"
	@echo -e "$(BLUE)Usage:$(NC) make [target] [PACKAGES=\"pkg1 pkg2...\"]"
	@echo ""
	@echo -e "$(YELLOW)Main Targets:$(NC)"
	@echo "  help              Show this help message"
	@echo "  install           Run the complete installation"
	@echo "  update            Update dotfiles from git and reinstall"
	@echo "  uninstall         Remove all symlinks created by stow"
	@echo "  reinstall         Reinstall all packages"
	@echo ""
	@echo -e "$(YELLOW)Component Targets:$(NC)"
	@echo "  build             Build programs from source"
	@echo "  programs          Install programs from package manager"
	@echo "  themes            Install themes and icons"
	@echo "  desktop ENV=sway  Set up desktop environment (sway or hyprland)"
	@echo ""
	@echo -e "$(YELLOW)Package Management:$(NC)"
	@echo "  packages          List all available packages"
	@echo "  status            Show status of stowed packages"
	@echo "  stow              Stow specified packages (or prompt if none specified)"
	@echo "  unstow            Unstow specified packages (or prompt if none specified)"
	@echo "  restow            Restow specified packages (or prompt if none specified)"
	@echo "  create-package    Create a new package (prompts for name)"
	@echo ""
	@echo -e "$(YELLOW)Examples:$(NC)"
	@echo "  make stow PACKAGES=\"zsh tmux\""
	@echo "  make desktop ENV=sway"
	@echo "  make build"
	@echo ""

# Main Targets
install:
	@echo -e "$(GREEN)Running full installation...$(NC)"
	@./install.sh

update:
	@echo -e "$(GREEN)Updating dotfiles...$(NC)"
	@git pull
	@./install.sh

uninstall:
	@echo -e "$(GREEN)Uninstalling all packages...$(NC)"
	@./install/core/stow.sh unstow

reinstall:
	@echo -e "$(GREEN)Reinstalling all packages...$(NC)"
	@./install/core/stow.sh restow

# Component Targets
build:
	@echo -e "$(GREEN)Building programs from source...$(NC)"
	@./sources/build_from_source.sh

programs:
	@echo -e "$(GREEN)Installing programs from package manager...$(NC)"
	@./install.sh --programs

themes:
	@echo -e "$(GREEN)Installing themes and icons...$(NC)"
	@./install.sh --themes

desktop:
	@if [ -z "$(ENV)" ]; then \
		echo -e "$(RED)Error: ENV variable not set. Use 'make desktop ENV=sway' or 'make desktop ENV=hyprland'$(NC)"; \
		exit 1; \
	fi
	@echo -e "$(GREEN)Setting up $(ENV) desktop environment...$(NC)"
	@./install.sh --desktop $(ENV)

# Package Management
packages:
	@echo -e "$(GREEN)Available packages:$(NC)"
	@./install/core/stow.sh list

status:
	@echo -e "$(GREEN)Stowed packages:$(NC)"
	@./install/core/stow.sh list-stowed

stow:
	@if [ -z "$(PACKAGES)" ]; then \
		echo -e "$(YELLOW)No packages specified, showing interactive menu:$(NC)"; \
		./install.sh; \
	else \
		echo -e "$(GREEN)Stowing packages: $(PACKAGES)$(NC)"; \
		./install/core/stow.sh stow $(PACKAGES); \
	fi

unstow:
	@if [ -z "$(PACKAGES)" ]; then \
		echo -e "$(YELLOW)No packages specified, showing interactive menu:$(NC)"; \
		./install.sh; \
	else \
		echo -e "$(GREEN)Unstowing packages: $(PACKAGES)$(NC)"; \
		./install/core/stow.sh unstow $(PACKAGES); \
	fi

restow:
	@if [ -z "$(PACKAGES)" ]; then \
		echo -e "$(YELLOW)No packages specified, showing interactive menu:$(NC)"; \
		./install.sh; \
	else \
		echo -e "$(GREEN)Restowing packages: $(PACKAGES)$(NC)"; \
		./install/core/stow.sh restow $(PACKAGES); \
	fi

create-package:
	@read -p "Enter package name: " pkg_name; \
	read -p "Enter package description (optional): " pkg_desc; \
	if [ -z "$$pkg_desc" ]; then \
		./install/core/stow.sh create "$$pkg_name"; \
	else \
		./install/core/stow.sh create "$$pkg_name" "$$pkg_desc"; \
	fi

# Utility Targets
clean:
	@echo -e "$(GREEN)Cleaning up temporary files...$(NC)"
	@find . -name "*.log" -type f -delete
	@find . -name "*.tmp" -type f -delete
	@find . -name "*~" -type f -delete
	@echo -e "$(GREEN)Done.$(NC)"
