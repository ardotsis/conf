#!/bin/bash
set -e -u -o pipefail -C

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
declare -r GIT_REMOTE_BRANCH="main"
declare -r HOST_PREFIX="${HOSTNAME^^}##"
declare -Ar HOST_OS=(
	["vultr"]="debian"
	["arch"]="arch"
	["mc"]="ubuntu"
)
declare -r OS="${HOST_OS["$HOSTNAME"]}"
declare -r PASSWD_LENGTH=72
declare -r SCRIPT_NAME="${BASH_SOURCE[0]+x}"

declare -r HOME="/home/$INSTALL_USER" # Override $HOME
declare -r TMP_DIR="/var/tmp"
declare -r DOCKER_VOLUME_DIR="/app"
declare -r CUSTOM_SSH_PORT_FILE="/etc/CUSTOM_SSH_PORT"
declare -r TMP_INSTALL_SCRIPT_FILE="$TMP_DIR/install_dotfiles.sh"

declare -A DOTFILES_REPO
DOTFILES_REPO["_dir"]="$HOME/.dotfiles"
DOTFILES_REPO["linux_dir"]="${DOTFILES_REPO["_dir"]}/linux"
DOTFILES_REPO["package_list"]="${DOTFILES_REPO["linux_dir"]}/packages.txt"
DOTFILES_REPO["template_dir"]="${DOTFILES_REPO["linux_dir"]}/template"
DOTFILES_REPO["hosts_dir"]="${DOTFILES_REPO["linux_dir"]}/hosts"
DOTFILES_REPO["default_host"]="${DOTFILES_REPO["hosts_dir"]}/_default"
DOTFILES_REPO["current_host"]="${DOTFILES_REPO["hosts_dir"]}/$HOSTNAME"
declare -r DOTFILES_REPO

declare -A DOTFILES_DATA
DOTFILES_DATA["_dir"]="/etc/dotfiles-data"
DOTFILES_DATA["secret"]="${DOTFILES_DATA["_dir"]}/log"
DOTFILES_DATA["secret"]="${DOTFILES_DATA["_dir"]}/secret"
DOTFILES_DATA["backups_dir"]="${DOTFILES_DATA["_dir"]}/backups"
declare -A DOTFILES_DATA

declare -Ar TEMPLATE=(
	# Home
	["$HOME/.ssh/authorized_keys"]="f $INSTALL_USER $INSTALL_USER 0600"
	["$HOME/.ssh/config"]="f $INSTALL_USER $INSTALL_USER 0600"

	# dotfiles-data
	["${DOTFILES_DATA["secret"]}"]="f $INSTALL_USER $INSTALL_USER 0600"

	# openssh-server
	["/etc/ssh"]="d root root 0755"
	["/etc/ssh/sshd_config"]="f root root 0600"

	# iptables
	["/etc/iptables"]="d root root 0755"
	["/etc/iptables/rules.v4"]="f root root 0644"
	["/etc/iptables/rules.v6"]="f root root 0644"
	["/etc/systemd/system/iptables-restore.service"]="f root root 0644"

	# Other
	["$TMP_INSTALL_SCRIPT_FILE"]="f root root 0755"
	["$CUSTOM_SSH_PORT_FILE"]="f root root 0755"
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
#                 Pure Functions                 #
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

get_tmp_curl_file() {
	local url="$1"

	local tmp_path
	tmp_path="${TMP_DIR}/$(get_safe_random_str 16)"

	curl -fsSL "$url" -o "$tmp_path"
	printf "%s" "$tmp_path"
}

install_nvim() {
	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz")
	$SUDO tar -C "/opt" -xzf "$tgz_path"
	$SUDO rm -rf "$tgz_path"
}

install_zoxide() {
	local username="$1"

	local home_dir="/home/$username"

	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/ajeetdsouza/zoxide/releases/latest/download/zoxide-0.9.8-x86_64-unknown-linux-musl.tar.gz")
	local tmp_dir="$TMP_DIR/zoxide"
	$SUDO mkdir $tmp_dir
	$SUDO tar -C "$tmp_dir" -xzf "$tgz_path"
	$SUDO cp -R "$tmp_dir/man/man1" "$home_dir/.local/share/man"
	$SUDO chown -R "$username:$username" "$home_dir/.local/share/man"
	$SUDO mv "$tmp_dir/zoxide" "$home_dir/.local/bin"
	$SUDO rm -rf "$tmp_dir" "$tgz_path"
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

build_home() {
	local username="$1"

	local home_dir="/home/$username"

	# XDG directories
	$SUDO mkdir -p "$home_dir"/{.cache,.config,.local,.ssh}
	$SUDO mkdir "$home_dir/.local"/{bin,share,state}
	$SUDO mkdir "$home_dir/.local/share/"{zsh,man}

	$SUDO chown -R "$username:$username" "$home_dir"
	$SUDO chmod -R 700 "$home_dir"
}

add_user() {
	local username="$1"
	local passwd="$2"

	if [[ "$OS" == "debian" ]]; then
		$SUDO useradd -s "/bin/zsh" -G "sudo" "$username"
		printf "%s:%s" "$username" "$passwd" | $SUDO chpasswd
		# Allow "sudo" command without password
		printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$username" | $SUDO tee "/etc/sudoers.d/$username"
		build_home "$username"
	fi
}

backup_item() {
	local item_path="$1"

	local parent_dir basename dst timestamp
	parent_dir="$(dirname "$item_path")"
	basename="$(basename "$item_path")"
	timestamp="$(date "+%Y-%m-%d_%H-%M-%S")"
	dst="${DOTFILES_DATA["backups_dir"]}/${basename}.${timestamp}.tgz"

	log_info "Create backup: $(clr "$dst" "${LOG_CLR["path"]}" "true")"
	$SUDO tar czvf "$dst" -C "$parent_dir" "$basename"
}

install_template() {
	local template_uri="${1:-/dev/null}"
	local dst_path="$2"

	read -r -a perm <<<"${TEMPLATE[$dst_path]}"
	local type="${perm[0]}"
	local group="${perm[1]}"
	local user="${perm[2]}"
	local num="${perm[3]}"

	local install_cmd=("install" "-m" "$num" "-o" "$user" "-g" "$group")
	if [[ -n "$SUDO" ]]; then
		install_cmd=("$SUDO" "${install_cmd[@]}")
	fi

	if [[ -e "$dst_path" ]]; then
		backup_item "$dst_path"
		$SUDO rm -rf "$dst_path"
	fi

	local tmp_path=""
	if [[ "$template_uri" == "https://"* ]]; then
		tmp_path="$(get_tmp_curl_file "$template_uri")"
		install_cmd=("${install_cmd[@]}" "$tmp_path" "$dst_path")
	else
		if [[ "$type" == "f" ]]; then
			install_cmd=("${install_cmd[@]}" "$template_uri" "$dst_path")
		elif [[ "$type" == "d" ]]; then
			install_cmd=("${install_cmd[@]}" "$dst_path" "-d")
		fi
	fi

	log_info "Create item: \"${LOG_CLR["path"]}$dst_path${CLR["reset"]}\" (template=\"${LOG_CLR["path"]}$template_uri${CLR["reset"]}\" owner=$user, group=$group, mode=$num)"
	"${install_cmd[@]}"

	if [[ -n "$tmp_path" ]]; then
		rm -f "$tmp_path"
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
setup_system() {
	# Install Neovim
	install_nvim

	# Override network configuration
	local ssh_port
	ssh_port="$((1024 + RANDOM % (65535 - 1024 + 1)))"

	$SUDO install -m 0755 -o "root" -g "root" "/dev/null" "$CUSTOM_SSH_PORT_FILE"
	printf "%s" "$ssh_port" | $SUDO tee "$CUSTOM_SSH_PORT_FILE"

	install_template "" "/etc/ssh"
	install_template "${DOTFILES_REPO["template_dir"]}/openssh-server/sshd_config" "/etc/ssh/sshd_config"
	$SUDO sed -i "s/^Port [0-9]\+/Port $ssh_port/" "/etc/ssh/sshd_config" # TODO: warn: depends on template file

	# iptables
	install_template "" "/etc/iptables"
	install_template "${DOTFILES_REPO["template"]}/iptables/rules.v4" "/etc/iptables/rules.v4"
	install_template "${DOTFILES_REPO["template"]}/iptables/rules.v6" "/etc/iptables/rules.v6"
	install_template "${DOTFILES_REPO["template"]}/iptables-restore.service" "/etc/systemd/system/iptables-restore.service"
	$SUDO sed -i "s|^-A INPUT -p tcp --dport [0-9]\+ -j ACCEPT$|-A INPUT -p tcp --dport $ssh_port -j ACCEPT|" "/etc/iptables/rules.v4" # TODO: warn: depends on template file

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

_setup_vultr() {
	log_info "Start package installation"
	while read -r pkg; do
		if ! is_cmd_exist "$pkg"; then
			install_package "$pkg"
		fi
	done <"${DOTFILES_REPO["package_list"]}"

	if is_cmd_exist ufw; then
		log_info "Uninstall UFW"
		$SUDO ufw disable
		remove_package "ufw"
	fi

	log_info "Start SSH setup"
	local ssh_dir="$HOME/.ssh"
	install_template "" "$ssh_dir/authorized_keys"
	install_template "" "$ssh_dir/config"

	if [[ "$IS_DEBUG" == "true" ]]; then
		log_debug "New debug symlink: \"${LOG_CLR["path"]}${DOTFILES_REPO["_dir"]}${CLR["reset"]}\" -> \"${LOG_CLR["path"]}$DOCKER_VOLUME_DIR${CLR["reset"]}\""
		ln -s "$DOCKER_VOLUME_DIR" "${DOTFILES_REPO["_dir"]}"
	else
		git clone -b "$GIT_REMOTE_BRANCH" "${URL["dotfiles_repo"]}" "${DOTFILES_REPO["_dir"]}"
	fi

	# # Install neovim
	# # install_package_manually "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz" "/opt" "nvim-linux-x86_64" "root" "root"
	# # install_package_manually "https://github.com/starship/starship/releases/latest/download/starship-x86_64-unknown-linux-musl.tar.gz" "/usr/local/bin" "starship" "root" "root"
	# # install_package_manually "https://github.com/ajeetdsouza/zoxide/releases/download/v0.9.8/zoxide-0.9.8-x86_64-unknown-linux-musl.tar.gz" "/usr/local/bin" "starship" "root" "root"
	# log_info "Start linking dotfiles"
	# link "$HOME" "${DOTFILES_REPO["current_host"]}" "${DOTFILES_REPO["default_host"]}"

	# Zsh plugins
	git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$Z_SHARE_DIR/zsh-autosuggestions"
	git clone "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$Z_SHARE_DIR/zsh-syntax-highlighting"

	if [[ "$IS_DOCKER" == "false" ]]; then
		log_info "Executing Docker installation script.."
		sh -c "$(curl -fsSL https://get.docker.com)"
	fi

	### Client -> This Host
	local ssh_publickey
	if [[ "$IS_DEBUG" == "true" ]]; then
		ssh_publickey="some_ssh_publickey"
	else
		read -r -p "Paste SSH public key: " ssh_publickey </dev/tty
	fi

	printf "%s" "$ssh_publickey" >>"$ssh_dir/authorized_keys"
	{
		printf "# Client's SSH template"
		printf "Host %s\n" "$HOSTNAME"
		printf "  HostName %s\n" "$(curl -fsSL https://api.ipify.org)"
		printf "  Port %s\n" "$ssh_port"
		printf "  User %s\n" "$INSTALL_USER"
		printf "  IdentityFile ~/.ssh/%s\n" "$HOSTNAME"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"${DOTFILES_DATA["secret"]}"

	### This Host -> Git
	local ssh_git_passphrase
	ssh_git_passphrase="$(get_random_str $PASSWD_LENGTH)"
	local git_filename="git"
	ssh-keygen -t ed25519 -b 4096 -f "$ssh_dir/$git_filename" -N "$ssh_git_passphrase"
	{
		printf "# SSH passphrase for Git\n%s\n\n" "$ssh_git_passphrase"
		printf "# SSH public key for Git\n"
		cat "$ssh_dir/${git_filename}.pub"
		printf "\n"
	} >>"${DOTFILES_DATA["secret"]}"

	{
		printf "Host git\n"
		printf "  HostName github.com\n"
		printf "  User git\n"
		printf "  IdentityFile ~/.ssh/%s\n" "$git_filename"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"$ssh_dir/config"

	rm -f "$ssh_dir/${git_filename}.pub"

}

_setup_arch() {
	log_warn "dotfiles for arch - Not implemented yet"
}

main_() {
	log_debug "Bash version\n: $BASH_VERSION"

	local session_id
	session_id="$(get_safe_random_str 4)"
	log_debug "================ Begin $(clr "$CURRENT_USER ($session_id)" "${LOG_CLR["highlight"]}") session ================"
	log_vars "HOSTNAME" "INSTALL_USER" "CURRENT_USER" "IS_DOCKER" "IS_DEBUG"

	# Download script
	if [[ -z "$SCRIPT_NAME" ]]; then
		[[ -e "$TMP_INSTALL_SCRIPT_FILE" ]] && $SUDO rm -f "$TMP_INSTALL_SCRIPT_FILE"

		if [[ "$IS_DEBUG" == "true" ]]; then
			log_debug "Copy script from \"${CLR["yellow"]}${DOCKER_VOLUME_DIR}/install.sh${CLR["reset"]}\""
			install_template "$DOCKER_VOLUME_DIR/install.sh" "$TMP_INSTALL_SCRIPT_FILE"
		else
			log_debug "Download script from ${CLR["yellow"]}${URL["dotfiles_install_script"]}${CLR["reset"]}"
			install_template "${URL["dotfiles_install_script"]}" "$TMP_INSTALL_SCRIPT_FILE"
		fi

		get_script_run_cmd "$TMP_INSTALL_SCRIPT_FILE" "run_cmd"
		log_info "Exit and restarting..."
		"${run_cmd[@]}"
		exit 0
	fi

	############### Main Process ###############
	if is_usr_exist "$INSTALL_USER"; then
		cd "$HOME"
		"_setup_$HOSTNAME"
		if [[ ! -e "$CUSTOM_SSH_PORT_FILE" ]]; then
			log_info "New system installation. Setup network config..."
		fi
	else
		if [[ -n "$SUDO" ]]; then
			sudo -v
		fi

		log_info "Create user: ${LOG_CLR["highlight"]}${INSTALL_USER}${CLR["reset"]}"

		# Create user
		local passwd
		passwd="$(get_random_str $PASSWD_LENGTH)"
		add_user "$INSTALL_USER" "$passwd"

		# Create dotfiles directory
		install_template "" "${DOTFILES_DATA["secret"]}"
		printf "# DELETE this file, once you complete the process.\n\n" >>"${DOTFILES_DATA["secret"]}"
		printf "# Password for %s\n%s\n\n" "$INSTALL_USER" "$passwd" >>"${DOTFILES_DATA["secret"]}"

		local run_cmd
		get_script_run_cmd "$(get_script_path)" "run_cmd"
		log_info "Done user creation. Exit and starting install script as ${LOG_CLR["highlight"]}$INSTALL_USER${CLR["reset"]}..."
		sudo -u "$INSTALL_USER" -- "${run_cmd[@]}"
		exit 0
	fi

	[[ -e "$HOME/.sudo_as_admin_successful" ]] && rm -f "$HOME/.sudo_as_admin_successful"

	if [[ "$IS_DOCKER" == "true" ]]; then
		log_info "Docker mode is enabled. Keeping docker container running..."
		tail -f /dev/null
	fi

	log_debug "================ End $(clr "$CURRENT_USER ($session_id)" "${LOG_CLR["highlight"]}") session ================"
}

# main_
setup_system
