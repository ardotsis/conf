#!/usr/bin/env bash
set -e

declare -r _DOCKER_APP_DIR="$1"
source "$_DOCKER_APP_DIR/conf.sh"

main_() {
	# ZSH plugins
	install_zsh_plugins "$ZSH_PLUGINS_DIR"

	# Neovim
	install_nvim

	# Zoxide
	local man1_dir="$LOCAL_DIR/share/man/man1"
	[[ ! -e "$man1_dir" ]] && mkdir -p "$man1_dir"
	install_zoxide "$LOCAL_DIR/bin" "$man1_dir"

	# Starship
	install_starship "$LOCAL_DIR/bin"
}

main_
