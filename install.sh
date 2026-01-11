#!/bin/bash
set -e -u -o pipefail -C
printf "Bash version: %s\n" "$BASH_VERSION"

declare -ar _PARAM_0=("--host" "-h" "value" "")
declare -ar _PARAM_1=("--username" "-u" "value" "ardotsis")
declare -ar _PARAM_2=("--docker" "-d" "flag" "false")
declare -ar _PARAM_3=("--debug" "-de" "flag" "false")
declare -A _PARAMS=()
declare -a _ARGS=("$@")
declare _IS_ARGS_PARSED="false"

_parse_args() {
	show_missing_param_err() {
		printf "Please provide a value for '%s' (%s) parameter.\n" "$1" "$2"
		exit 1
	}

	local i=0
	while :; do
		local param_var="_PARAM_${i}"
		[[ -z "${!param_var+x}" ]] && break

		declare -n a_param="$param_var"
		local long_name="${a_param[0]}"
		local short_name="${a_param[1]}"
		local type="${a_param[2]}"
		local default_value="${a_param[3]}"
		local key="${long_name#--}" # 1. "--my-name" -> "my-name"
		key="${key//-/_}"           # 2. "my-name" -> "my_name"

		local arg_index=0
		while ((arg_index < ${#_ARGS[@]})); do
			local some_arg="${_ARGS[$arg_index]}"
			if [[ "$some_arg" == "$long_name" || "$some_arg" == "$short_name" ]]; then
				if [[ "$type" == "value" ]]; then
					local value_index=$((arg_index + 1))
					if ((value_index < ${#_ARGS[@]})); then
						value="${_ARGS[$value_index]}"
					else
						show_missing_param_err "$long_name" "$short_name"
					fi
					_PARAMS["$key"]="$value"
					_ARGS=("${_ARGS[@]:0:$arg_index}" "${_ARGS[@]:$arg_index+2}")
				elif [[ "$type" == "flag" ]]; then
					_PARAMS["$key"]="true"
				fi
				break
			fi
			arg_index=$((arg_index + 1))
		done

		if [[ -z "${_PARAMS["$key"]+x}" ]]; then
			if [[ -n "$default_value" ]]; then
				_PARAMS["$key"]="$default_value"
			else
				show_missing_param_err "$long_name" "$short_name"
			fi
		fi
		i=$((i + 1))
	done

	declare -r _IS_ARGS_PARSED="true"
}

get_arg() {
	local name="$1"
	if [[ "$_IS_ARGS_PARSED" == "false" ]]; then
		_parse_args
	fi
	printf %s "${_PARAMS[$name]}"
}

# Parameters
HOSTNAME=$(get_arg "host")
declare -r HOSTNAME
INSTALL_USER=$(get_arg "username")
declare -r INSTALL_USER
IS_DOCKER=$(get_arg "docker")
declare -r IS_DOCKER
IS_DEBUG=$(get_arg "debug")
declare -r IS_DEBUG
CURRENT_USER="$(whoami)"
declare -r CURRENT_USER

# Global variables
declare -r SCRIPT_NAME="${BASH_SOURCE[0]+x}"
declare -r HOME_DIR="/home/$INSTALL_USER"
declare -r TMP_DIR="/var/tmp"
declare -r REPO_DIRNAME=".dotfiles"
declare -r DEV_REPO_DIR="$TMP_DIR/${REPO_DIRNAME}_docker"
declare -r TMP_INSTALL_SCRIPT_FILE="$TMP_DIR/install_dotfiles.sh"
declare -r GIT_REMOTE_BRANCH="main"
declare -r HOST_PREFIX="${HOSTNAME^^}##"
declare -Ar HOST_OS=(
	["vultr"]="debian"
	["arch"]="arch"
	["mc"]="ubuntu"
)
declare -r OS="${HOST_OS["$HOSTNAME"]}"
declare -r PASSWD_LENGTH=72

declare -A DOTFILES_REPO
DOTFILES_REPO["_dir"]="$HOME_DIR/$REPO_DIRNAME"
DOTFILES_REPO["src"]="${DOTFILES_REPO["_dir"]}/linux"
DOTFILES_REPO["hosts"]="${DOTFILES_REPO["src"]}/hosts"
DOTFILES_REPO["default"]="${DOTFILES_REPO["hosts"]}/_default"
DOTFILES_REPO["host"]="${DOTFILES_REPO["hosts"]}/$HOSTNAME"
DOTFILES_REPO["packages"]="${DOTFILES_REPO["src"]}/packages.txt"
DOTFILES_REPO["template"]="${DOTFILES_REPO["src"]}/template"
declare -r DOTFILES_REPO

declare -A APP
APP["_dir"]="$HOME_DIR/dotfiles-data"
APP["log"]="${APP["_dir"]}/log"
APP["secret"]="${APP["_dir"]}/secret"
APP["backups"]="${APP["_dir"]}/backups"
declare -A APP

declare -A HOME_SSH
HOME_SSH["_dir"]="$HOME_DIR/.ssh"
HOME_SSH["authorized_keys"]="${HOME_SSH["_dir"]}/authorized_keys"
HOME_SSH["config"]="${HOME_SSH["_dir"]}/config"
declare -r HOME_SSH

declare -A HOME_LOCAL
HOME_LOCAL["_dir"]="$HOME_DIR/.local"
HOME_LOCAL["share"]="${HOME_LOCAL["_dir"]}/share"
HOME_LOCAL["state"]="${HOME_LOCAL["_dir"]}/state"
declare -r HOME_LOCAL

declare -A OPENSSH_SERVER
OPENSSH_SERVER["etc"]="/etc/ssh"
OPENSSH_SERVER["sshd_config"]="${OPENSSH_SERVER["etc"]}/sshd_config"
declare -r OPENSSH_SERVER

declare -A IPTABLES
IPTABLES["etc"]="/etc/iptables"
IPTABLES["rules_v4"]="${IPTABLES["etc"]}/rules.v4"
IPTABLES["rules_v6"]="${IPTABLES["etc"]}/rules.v6"
IPTABLES["service"]="/etc/systemd/system/iptables-restore.service"
declare -r IPTABLES

declare -Ar PERMISSION=(
	["$HOME_DIR"]="d $INSTALL_USER $INSTALL_USER 0700"
	["$TMP_INSTALL_SCRIPT_FILE"]="f root root 0755"

	["${APP["_dir"]}"]="d $INSTALL_USER $INSTALL_USER 0700"
	["${APP["log"]}"]="f $INSTALL_USER $INSTALL_USER 0600"
	["${APP["secret"]}"]="f $INSTALL_USER $INSTALL_USER 0600"
	["${APP["backups"]}"]="d $INSTALL_USER $INSTALL_USER 0700"

	["${HOME_SSH["_dir"]}"]="d $INSTALL_USER $INSTALL_USER 0700"
	["${HOME_SSH["authorized_keys"]}"]="f $INSTALL_USER $INSTALL_USER 0600"
	["${HOME_SSH["config"]}"]="f $INSTALL_USER $INSTALL_USER 0600"

	["${HOME_LOCAL["_dir"]}"]="d $INSTALL_USER $INSTALL_USER 0700"
	["${HOME_LOCAL["share"]}"]="d $INSTALL_USER $INSTALL_USER 0700"
	["${HOME_LOCAL["state"]}"]="d $INSTALL_USER $INSTALL_USER 0700"

	["${OPENSSH_SERVER["etc"]}"]="d root root 0755"
	["${OPENSSH_SERVER["sshd_config"]}"]="f root root 0600"

	["${IPTABLES["etc"]}"]="d root root 0755"
	["${IPTABLES["rules_v4"]}"]="f root root 0644"
	["${IPTABLES["rules_v6"]}"]="f root root 0644"
	["${IPTABLES["service"]}"]="f root root 0644"
)

declare -Ar URL=(
	["dotfiles_repo"]="https://github.com/ardotsis/dotfiles.git"
	["dotfiles_install_script"]="https://raw.githubusercontent.com/ardotsis/dotfiles/refs/heads/main/install.sh"
)

declare -Ar CLR=(
	["reset"]="\033[0m"
	["black"]="\033[0;30m"
	["red"]="\033[0;31m"
	["green"]="\033[0;32m"
	["yellow"]="\033[0;33m"
	["blue"]="\033[0;34m"
	["purple"]="\033[0;35m"
	["cyan"]="\033[0;36m"
	["white"]="\033[0;37m"
)

declare -Ar LOG_CLR=(
	["debug"]="${CLR["white"]}"
	["info"]="${CLR["green"]}"
	["warn"]="${CLR["yellow"]}"
	["error"]="${CLR["red"]}"
	["var"]="${CLR["purple"]}"
	["value"]="${CLR["cyan"]}"
	["path"]="${CLR["yellow"]}"
	["highlight"]="${CLR["red"]}"
)

if [[ "$(id -u)" == "0" ]]; then
	declare -r SUDO=""
else
	declare -r SUDO="sudo"
fi

##################################################
#                Common Functions                #
##################################################
_log() {
	local level="$1"
	local msg="$2"

	local i=0
	local lineno="${BASH_LINENO[1]}"
	local caller=" <GLOBAL> "
	for funcname in "${FUNCNAME[@]}"; do
		i=$((i + 1))
		[[ "$funcname" == "_log" ]] && continue
		[[ "$funcname" == "log_"* ]] && continue
		[[ "$funcname" == "main" ]] && continue
		lineno="${BASH_LINENO[$((i - 2))]}"
		caller="$funcname"
		break
	done

	local timestamp
	timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
	printf "[%s] [%b%s%b] [%s:%s] (%s) %b\n" "$timestamp" "${LOG_CLR["${level}"]}" "${level^^}" "${CLR["reset"]}" "$caller" "$lineno" "$CURRENT_USER" "$msg" >&2
}
log_debug() { _log "debug" "$1"; }
log_info() { _log "info" "$1"; }
log_warn() { _log "warn" "$1"; }
log_error() { _log "error" "$1"; }
log_vars() {
	local var_names=("$@")

	local msg=""
	for var_name in "${var_names[@]}"; do
		fmt="${LOG_CLR["var"]}\$$var_name${CLR["reset"]}=\"${LOG_CLR["value"]}${!var_name}${CLR["reset"]}\""
		if [[ -z "$msg" ]]; then
			msg="$fmt"
		else
			msg="$msg $fmt"
		fi
	done

	_log "debug" "$msg"
}

clr() {
	local msg="$1"
	local clr="$2"
	local with_quote="${3-:}"

	if [[ "$with_quote" == "true" ]]; then
		local q='"'
	else
		local q=''
	fi

	printf "%b" "${q}${clr}${msg}${CLR["reset"]}${q}"
}

get_script_path() {
	printf "%s" "$(readlink -f "$0")"
}

get_script_run_cmd() {
	local script_path="$1"
	local -n arr_ref="$2"

	arr_ref=(
		"$script_path"
		"--host"
		"$HOSTNAME"
		"--username"
		"$INSTALL_USER"
	)
	# TODO: Detect flag(s) automatically
	[[ "$IS_DOCKER" == "true" ]] && arr_ref+=("--docker") || true
	[[ "$IS_DEBUG" == "true" ]] && arr_ref+=("--debug") || true

	log_vars "arr_ref[@]"
}

is_cmd_exist() {
	local cmd="$1"

	if command -v "$cmd" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

is_usr_exist() {
	local username="$1"

	if id "$username" >/dev/null 2>&1; then
		return 0
	else
		return 1
	fi
}

_get_random_str() {
	local length="$1"
	local chars="$2"

	# Use printf to flush buffer forcefully
	printf "%s" "$(tr -dc "$chars" </dev/urandom | head -c "$length")"
}

get_random_str() {
	local length="$1"
	_get_random_str "$length" "A-Za-z0-9!?%="
}

get_safe_random_str() {
	local length="$1"
	_get_random_str "$length" "A-Za-z0-9"
}

install_package() {
	local pkg="$1"

	log_info "Installing $pkg..."
	if [[ "$OS" == "debian" ]]; then
		$SUDO apt-get install -y --no-install-recommends "$pkg"
	fi
}

remove_package() {
	local pkg="$1"

	if [[ "$OS" == "debian" ]]; then
		$SUDO apt-get remove -y "$pkg"
		$SUDO apt-get purge -y "$pkg"
		$SUDO apt-get autoremove -y
		$SUDO apt-get clean
	fi
}

# TODO: install manual package (function: nvim starship etc..)
install_nvim() {
	# TODO: Install globally (/etc/zshenv)
	$SUDO rm -rf "/opt/nvim-linux-x86_64" # Clean up old items

	local gz_path="${TMP_DIR}/vim-linux-x86_64.tar.gz"
	curl -L "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" -o "$gz_path"
	$SUDO tar -C "/opt" -xzf "$gz_path"
	$SUDO rm -f "$gz_path"
}

install_starship() {
	local gz_path="${TMP_DIR}/starship-x86_64-unknown-linux-musl.tar.gz"
	curl -L "https://github.com/starship/starship/releases/download/v1.24.2/starship-x86_64-unknown-linux-musl.tar.gz" -o "$gz_path"
	$SUDO tar -C "/usr/local/bin" -xzf "$gz_path"
	$SUDO rm -f "$gz_path"
}

add_user() {
	local username="$1"
	local passwd="$2"

	if [[ "$OS" == "debian" ]]; then
		$SUDO useradd -s "/bin/zsh" -G "sudo" "$username"
		# Set password
		printf "%s:%s" "$username" "$passwd" | $SUDO chpasswd
		# Allow "sudo" command without password
		printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$username" | sudo tee "/etc/sudoers.d/$username"
		# Build home directory
		set_perm_item "" "$HOME_DIR"
		set_perm_item "" "${HOME_LOCAL["_dir"]}"
		set_perm_item "" "${HOME_LOCAL["share"]}"
		set_perm_item "" "${HOME_LOCAL["state"]}"
	fi
}

backup_item() {
	local item_path="$1"

	local parent_dir basename dst timestamp
	parent_dir="$(dirname "$item_path")"
	basename="$(basename "$item_path")"
	timestamp="$(date "+%Y-%m-%d_%H-%M-%S")"
	dst="${APP["backups"]}/${basename}.${timestamp}.tgz"

	log_info "Create backup: $(clr "$dst" "${LOG_CLR["path"]}" "true")"
	$SUDO tar czvf "$dst" -C "$parent_dir" "$basename"
}

set_perm_item() {
	local template_uri="$1"
	local item_path="$2"

	read -r -a perm <<<"${PERMISSION[$item_path]}" # TODO: Don't use 'read'
	local type="${perm[0]}"
	local group="${perm[1]}"
	local user="${perm[2]}"
	local num="${perm[3]}"

	local is_curled="false"
	local install_cmd=("install" "-m" "$num" "-o" "$user" "-g" "$group")

	if [[ -n "$SUDO" ]]; then
		install_cmd=("$SUDO" "${install_cmd[@]}")
	fi

	if [[ -e "$item_path" ]]; then
		backup_item "$item_path"
		$SUDO rm -rf "$item_path"
	fi

	# Source: Internet file
	if [[ "$template_uri" == "https://"* ]]; then
		curl_file_path="$TMP_DIR/$(get_random_str 16)"
		curl -fsSL "$template_uri" >"$curl_file_path"
		install_cmd=("${install_cmd[@]}" "$curl_file_path" "$item_path")
		is_curled="true"
	# Source: Local file
	else
		if [[ "$type" == "f" ]]; then
			if [[ -n "$template_uri" ]]; then
				install_cmd=("${install_cmd[@]}" "$template_uri" "$item_path")
			else
				install_cmd=("${install_cmd[@]}" "/dev/null" "$item_path")
			fi
		elif [[ "$type" == "d" ]]; then
			install_cmd=("${install_cmd[@]}" "$item_path" "-d")
		fi
	fi

	# Execute "install" command
	log_info "Create item: \"${LOG_CLR["path"]}$item_path${CLR["reset"]}\" (template=\"${LOG_CLR["path"]}$template_uri${CLR["reset"]}\" owner=$user, group=$group, mode=$num)"
	"${install_cmd[@]}"

	if [[ $is_curled == "true" ]]; then
		rm -rf "$curl_file_path"
	fi
}

get_items() {
	local dir_path="$1"
	# shellcheck disable=SC2178
	local -n result_arr_name="$2"

	# shellcheck disable=SC2034
	mapfile -d $'\0' result_arr_name < \
		<(find "$dir_path" -mindepth 1 -maxdepth 1 -printf "%f\0")
}

get_mixed_items() {
	# todo: arr1 arr2
	local -n arr_name_1="$1"
	local -n arr_name_2="$2"
	local mode="$3"
	# shellcheck disable=SC2178
	local -n result_arr_name="$4"

	# shellcheck disable=SC2034
	mapfile -d $'\0' result_arr_name < <(comm "$mode" -z \
		<(printf "%s\0" "${arr_name_1[@]}" | sort -z) \
		<(printf "%s\0" "${arr_name_2[@]}" | sort -z))
}

link() {
	local target_dir="$1"
	local host_dir="${2:-}" # Preferred
	local default_dir="${3:-}"
	log_vars "target_dir" "host_dir" "default_dir"

	local all_host_items=() all_default_items=()
	[[ -z "$host_dir" ]] || get_items "$host_dir" "all_host_items"
	[[ -z "$default_dir" ]] || get_items "$default_dir" "all_default_items"

	# shellcheck disable=SC2034
	local union_items=() host_items=() default_items=()
	if [[ -n "$host_dir" && -n "$default_dir" ]]; then
		get_mixed_items "all_host_items" "all_default_items" "-12" "union_items"
		get_mixed_items "all_host_items" "all_default_items" "-23" "host_items"
		get_mixed_items "all_host_items" "all_default_items" "-13" "default_items"
	elif [[ -n "$host_dir" ]]; then
		# shellcheck disable=SC2034
		local host_items=("${all_host_items[@]}")
	elif [[ -n "$default_dir" ]]; then
		# shellcheck disable=SC2034
		local default_items=("${all_default_items[@]}")
	fi
	# log_vars "union_items[@]" "host_items[@]" "default_items[@]" # TODO Ubuntu:jammy -> line 237: !var_name: unbound variable

	local item_type prefixed_items=()
	for item_type in "host" "union" "default"; do
		local -n items="${item_type}_items"
		if [[ "$item_type" == "union" ]]; then
			local as_var="as_host_item"
		else
			local as_var="as_${item_type}_item"
		fi

		local item
		for item in "${items[@]}"; do
			[[ -z "$item" ]] && continue
			# Skip host prefixed item
			local renamed_item="${item#"${HOST_PREFIX}"}"
			if [[ "$item_type" == "default" && " ${prefixed_items[*]} " =~ [[:space:]]${renamed_item}[[:space:]] ]]; then
				continue
			fi

			local as_target_item="${target_dir}/${item}"
			local as_host_item="${host_dir}/${item}"
			local as_default_item="${default_dir}/${item}"
			local actual_path="${!as_var}"

			# Backup home exists item
			if [[ -e "$as_target_item" ]]; then
				log_debug "Backup: $as_target_item"
				backup_item "$as_target_item"
				rm -rf "$as_target_item"
			fi

			local fixed_target_path=""
			if [[ "$item_type" == "host" && "$item" == "$HOST_PREFIX"* ]]; then
				fixed_target_path="${target_dir}/${renamed_item}"
				prefixed_items+=("${renamed_item}")
			fi

			if [[ -d "$actual_path" ]]; then
				[[ -n "$fixed_target_path" ]] && as_target_item="$fixed_target_path"
				log_debug "Create directory: \"${LOG_CLR["path"]}$as_target_item${CLR["reset"]}\""
				mkdir "$as_target_item"
				if [[ "$item_type" == "union" ]]; then
					link "$as_target_item" "$as_host_item" "$as_default_item"
				elif [[ "$item_type" == "host" ]]; then
					link "$as_target_item" "$as_host_item"
				elif [[ "$item_type" == "default" ]]; then
					link "$as_target_item" "" "$as_default_item"
				fi
			elif [[ -f "$actual_path" ]]; then
				[[ -n "$fixed_target_path" ]] && as_target_item="$fixed_target_path"
				log_info "New symlink: \"${LOG_CLR["path"]}$as_target_item${CLR["reset"]}\" -> (${item_type^^}) \"${LOG_CLR["path"]}$actual_path${CLR["reset"]}\""
				ln -sf "$actual_path" "$as_target_item"
			fi
		done
	done
}

##################################################
#                   Installers                   #
##################################################
do_setup_vultr() {
	if ! is_cmd_exist git; then
		install_package "git"
	fi

	if [[ "$IS_DEBUG" == "true" ]]; then
		log_debug "New debug symlink: \"${LOG_CLR["path"]}${DOTFILES_REPO["_dir"]}${CLR["reset"]}\" -> \"${LOG_CLR["path"]}$DEV_REPO_DIR${CLR["reset"]}\""
		ln -s "$DEV_REPO_DIR" "${DOTFILES_REPO["_dir"]}"
	else

		git clone -b "$GIT_REMOTE_BRANCH" "${URL["dotfiles_repo"]}" "${DOTFILES_REPO["_dir"]}"
	fi

	install_nvim

	log_info "Start linking dotfiles"
	link "$HOME_DIR" "${DOTFILES_REPO["host"]}" "${DOTFILES_REPO["default"]}"

	log_info "Install packages"
	while read -r pkg; do
		if ! is_cmd_exist "$pkg"; then
			install_package "$pkg"
		fi
	done <"${DOTFILES_REPO["packages"]}"

	# Uninstall UFW
	if is_cmd_exist ufw; then
		log_info "Uninstall UFW"
		$SUDO ufw disable
		remove_package "ufw"
	fi

	set_perm_item "" "${HOME_SSH["_dir"]}"

	# Install files / directories
	# SSH
	set_perm_item "" "${HOME_SSH["_dir"]}"
	set_perm_item "" "${HOME_SSH["authorized_keys"]}"
	set_perm_item "" "${HOME_SSH["config"]}"
	# openssh-server
	set_perm_item "${DOTFILES_REPO["template"]}/openssh-server/sshd_config" "${OPENSSH_SERVER["sshd_config"]}"
	# iptables
	local tmpl_iptables="${DOTFILES_REPO["template"]}/iptables"
	set_perm_item "" "${IPTABLES["etc"]}"
	set_perm_item "$tmpl_iptables/rules.v4" "${IPTABLES["rules_v4"]}"
	set_perm_item "$tmpl_iptables/rules.v6" "${IPTABLES["rules_v6"]}"
	set_perm_item "$tmpl_iptables/iptables-restore.service" "${IPTABLES["service"]}"

	# Change SSH port
	local ssh_port="$((1024 + RANDOM % (65535 - 1024 + 1)))"
	$SUDO sed -i "s/^Port [0-9]\+/Port $ssh_port/" "${OPENSSH_SERVER["sshd_config"]}"
	$SUDO sed -i "s|^-A INPUT -p tcp --dport [0-9]\+ -j ACCEPT$|-A INPUT -p tcp --dport $ssh_port -j ACCEPT|" "${IPTABLES["rules_v4"]}"

	local zsh_plugins_dir="${HOME_LOCAL["share"]}/zsh/plugins"
	mkdir -p "$zsh_plugins_dir"

	# Zsh plugins
	git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "${zsh_plugins_dir}/zsh-autosuggestions"
	git clone "https://github.com/zsh-users/zsh-syntax-highlighting.git" "${zsh_plugins_dir}/zsh-syntax-highlighting"

	install_starship

	if [[ "$IS_DOCKER" == "false" ]]; then
		log_info "Executing Docker installation script.."
		sh -c "$(curl -fsSL https://get.docker.com)"
	fi

	# Prepare SSH config for "client" and "Git"
	# [ Client ] --> [ This Host ]
	local ssh_publickey
	if [[ "$IS_DEBUG" == "true" ]]; then
		ssh_publickey="some_ssh_publickey"
	else
		read -r -p "Paste SSH public key: " ssh_publickey </dev/tty
	fi
	printf "%s" "$ssh_publickey" >>"${HOME_SSH["authorized_keys"]}"

	{
		printf "# Client's SSH template"
		printf "Host %s\n" "$HOSTNAME"
		printf "  HostName %s\n" "$(curl -fsSL https://api.ipify.org)"
		printf "  Port %s\n" "$ssh_port"
		printf "  User %s\n" "$INSTALL_USER"
		printf "  IdentityFile ~/.ssh/%s\n" "$HOSTNAME"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"${APP["secret"]}"

	# [ This Host ] --> [ Git ]
	local ssh_git_passphrase
	ssh_git_passphrase="$(get_random_str $PASSWD_LENGTH)"
	local git_filename="git"
	ssh-keygen -t ed25519 -b 4096 -f "${HOME_SSH["_dir"]}/$git_filename" -N "$ssh_git_passphrase"

	{
		printf "# SSH passphrase for Git\n%s\n\n" "$ssh_git_passphrase"
		printf "# SSH public key for Git\n"
		cat "${HOME_SSH["_dir"]}/${git_filename}.pub"
		printf "\n"
	} >>"${APP["secret"]}"

	{
		printf "Host git\n"
		printf "  HostName github.com\n"
		printf "  User git\n"
		printf "  IdentityFile ~/.ssh/%s\n" "$git_filename"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"${HOME_SSH["config"]}"

	rm -f "${HOME_SSH["_dir"]}/${git_filename}.pub"

	# Reload services
	if [[ "$IS_DOCKER" == "false" ]]; then
		log_info "Restart sshd service"
		$SUDO systemctl restart sshd
		log_info "Reload systemctl daemon"
		$SUDO systemctl daemon-reload
		log_info "Enable iptables-restore service"
		$SUDO systemctl enable iptables-restore.service
	fi
}

do_setup_arch() {
	log_warn "dotfiles for arch - Not implemented yet"
}

# "main_": Prevent the log function from logging it as "_GLOBAL_"
main_() {
	local session_id
	session_id="$(get_safe_random_str 4)"
	log_debug "================ Begin $(clr "$CURRENT_USER ($session_id)" "${LOG_CLR["highlight"]}") session ================"
	log_vars "HOSTNAME" "INSTALL_USER" "CURRENT_USER" "IS_DOCKER" "IS_DEBUG"

	# Download script
	if [[ -z "$SCRIPT_NAME" ]]; then
		if [[ "$IS_DEBUG" == "true" ]]; then
			log_debug "Copy script from \"${CLR["yellow"]}${DEV_REPO_DIR}/install.sh${CLR["reset"]}\""
			set_perm_item $DEV_REPO_DIR/install.sh "$TMP_INSTALL_SCRIPT_FILE"
		else
			log_debug "Download script from ${CLR["yellow"]}${URL["dotfiles_install_script"]}${CLR["reset"]}"
			set_perm_item "${URL["dotfiles_install_script"]}" "$TMP_INSTALL_SCRIPT_FILE"
		fi

		get_script_run_cmd "$TMP_INSTALL_SCRIPT_FILE" "run_cmd"
		log_info "Exit and restarting..."
		"${run_cmd[@]}"
		exit 0
	fi

	if is_usr_exist "$INSTALL_USER"; then
		cd "$HOME_DIR"
		"do_setup_${HOSTNAME}"
	else
		log_info "Create user: ${LOG_CLR["highlight"]}${INSTALL_USER}${CLR["reset"]}"
		# Update sudo credentials for non-root user
		if [[ -n "$SUDO" ]]; then
			sudo -v
		fi

		# Create user
		local passwd
		passwd="$(get_random_str $PASSWD_LENGTH)"
		add_user "$INSTALL_USER" "$passwd"

		# Create dotfiles directory
		set_perm_item "" "${APP["_dir"]}"
		set_perm_item "" "${APP["backups"]}"
		set_perm_item "" "${APP["secret"]}"
		printf "# DELETE this file, once you complete the process.\n\n" >>"${APP["secret"]}"
		printf "# Password for %s\n%s\n\n" "$INSTALL_USER" "$passwd" >>"${APP["secret"]}"

		local run_cmd
		get_script_run_cmd "$(get_script_path)" "run_cmd"
		log_info "Done user creation. Exit and starting install script as ${LOG_CLR["highlight"]}$INSTALL_USER${CLR["reset"]}..."
		sudo -u "$INSTALL_USER" -- "${run_cmd[@]}"
		exit 0
	fi

	[[ -e "${HOME_DIR}/.sudo_as_admin_successful" ]] && rm -f "${HOME_DIR}/.sudo_as_admin_successful"

	if [[ "$IS_DOCKER" == "true" ]]; then
		log_info "Docker mode is enabled. Keeping docker container running..."
		tail -f /dev/null
	fi

	log_debug "================ End $(clr "$CURRENT_USER ($session_id)" "${LOG_CLR["highlight"]}") session ================"
}

main_
