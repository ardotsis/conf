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

declare -A DF_REPO
DF_REPO["_dir"]="$HOME/.dotfiles"
DF_REPO["linux_dir"]="${DF_REPO["_dir"]}/linux"
DF_REPO["package_list"]="${DF_REPO["linux_dir"]}/packages.txt"
DF_REPO["template_dir"]="${DF_REPO["linux_dir"]}/template"
DF_REPO["hosts_dir"]="${DF_REPO["linux_dir"]}/hosts"
DF_REPO["default_host"]="${DF_REPO["hosts_dir"]}/_default"
DF_REPO["current_host"]="${DF_REPO["hosts_dir"]}/$HOSTNAME"
declare -r DF_REPO

declare -A DF_DATA
DF_DATA["_dir"]="$HOME/dotfiles-data"
DF_DATA["secret"]="${DF_DATA["_dir"]}/secret"
DF_DATA["backups_dir"]="${DF_DATA["_dir"]}/backups"
declare -A DF_DATA

# TODO: Deprecated
declare -Ar URL=(
	["dotfiles_repo"]="https://github.com/ardotsis/dotfiles.git"
	["dotfiles_install_script"]="https://raw.githubusercontent.com/ardotsis/dotfiles/refs/heads/main/install.sh"
)

declare -Ar C=(
	["0"]="\033[0m"
	["k"]="\033[0;30m"
	["r"]="\033[0;31m"
	["g"]="\033[0;32m"
	["y"]="\033[0;33m"
	["b"]="\033[0;34m"
	["p"]="\033[0;35m"
	["c"]="\033[0;36m"
	["w"]="\033[0;37m"
)

declare -Ar LC=(
	["debug"]="${C["w"]}"
	["info"]="${C["g"]}"
	["warn"]="${C["y"]}"
	["error"]="${C["r"]}"
	["var"]="${C["p"]}"
	["value"]="${C["c"]}"
	["path"]="${C["y"]}"
	["highlight"]="${C["r"]}"
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
	local -r ignore="_log _debug _info _warn _error _vars main"
	for funcname in "${FUNCNAME[@]}"; do
		i=$((i + 1))
		[[ $ignore =~ (^|[[:space:]])$funcname($|[[:space:]]) ]] && continue
		lineno="${BASH_LINENO[$((i - 2))]}"
		caller="$funcname"
		break
	done

	local timestamp
	timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
	printf "[%s] [%b%s%b] [%s:%s] (%s) %b\n" "$timestamp" "${LC["${level}"]}" "${level^^}" "${C["0"]}" "$caller" "$lineno" "$CURRENT_USER" "$msg" >&2
}
_debug() { _log "debug" "$1"; }
_info() { _log "info" "$1"; }
_warn() { _log "warn" "$1"; }
_error() { _log "error" "$1"; }
_vars() {
	local var_names=("$@")

	local msg=""
	for var_name in "${var_names[@]}"; do
		fmt="${LC["var"]}\$$var_name${C["0"]}=\"${LC["value"]}${!var_name}${C["0"]}\""
		if [[ -z "$msg" ]]; then
			msg="$fmt"
		else
			msg="$msg $fmt"
		fi
	done

	_log "debug" "$msg"
}

draw_line() {
	# TODO: Refactor
	local txt="$1"

	local a_bar_min=1
	local len=80
	local margin=4
	local label="="

	local bar_len=$((len - ${#txt} - margin * 2))

	if ((bar_len < (2 * a_bar_min))); then
		echo "need more len"
		return 1
	fi

	local right=$((bar_len / 2))
	local left=$((bar_len - right))

	printf '%*s' "$right" | tr ' ' "$label"
	printf '%*s' "$margin"
	printf "%s" "$txt"
	printf '%*s' "$margin"
	printf '%*s' "$left" | tr ' ' "$label"
	printf "\n"
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

	printf "%b" "${q}${clr}${msg}${C["0"]}${q}"
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

	_vars "arr_ref[@]"
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

	_info "Installing $pkg..."
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
	$SUDO mv "$tmp_dir/zoxide" "$home_dir/.local/bin"
	$SUDO rm -rf "$tmp_dir" "$tgz_path"
}

install_starship() {
	local username="$1"

	local home_dir="/home/$username"
	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/starship/starship/releases/download/v1.24.2/starship-x86_64-unknown-linux-musl.tar.gz")
	$SUDO tar -C "$TMP_DIR" -xzf "$tgz_path"
	$SUDO mv "$TMP_DIR/starship" "$home_dir/.local/bin"
	$SUDO rm -rf "$tgz_path"
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
	$SUDO mkdir -p "$home_dir"/{.cache,.config,.local,.ssh}
	$SUDO mkdir "$home_dir/.local"/{bin,share,state}

	$SUDO mkdir "$home_dir/.local/share/"{zsh,man}
	$SUDO mkdir "$home_dir/.local/share/zsh/plugins"

	$SUDO mkdir "$home_dir/.cache/zsh"

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
	dst="${DF_DATA["backups_dir"]}/${basename}.${timestamp}.tgz"

	_info "Create backup: $(clr "$dst" "${LC["path"]}" "true")"
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

	_info "Create item: \"${LC["path"]}$dst_path${C["0"]}\" (template=\"${LC["path"]}$template_uri${C["0"]}\" owner=$user, group=$group, mode=$num)"
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
	local host_dir="${2:-}" # Preferer
	local default_dir="${3:-}"
	local is_init="${4:-}"
	_vars "target_dir" "host_dir" "default_dir"

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
	# _vars "union_items[@]" "host_items[@]" "default_items[@]" # TODO Ubuntu:jammy -> line 237: !var_name: unbound variable

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
				_debug "Backup: $as_target_item"
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
				_debug "Create directory: \"${LC["path"]}$as_target_item${C["0"]}\""
				$SUDO install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "$as_target_item" -d

				if [[ "$item_type" == "union" ]]; then
					link "$as_target_item" "$as_host_item" "$as_default_item"
				elif [[ "$item_type" == "host" ]]; then
					link "$as_target_item" "$as_host_item"
				elif [[ "$item_type" == "default" ]]; then
					link "$as_target_item" "" "$as_default_item"
				fi
			elif [[ -f "$actual_path" ]]; then
				[[ -n "$fixed_target_path" ]] && as_target_item="$fixed_target_path"
				_info "New symlink: \"${LC["path"]}$as_target_item${C["0"]}\" -> (${item_type^^}) \"${LC["path"]}$actual_path${C["0"]}\""
				ln -sf "$actual_path" "$as_target_item"
			fi
		done
	done
}

##################################################
#                   Installers                   #
##################################################
setup_system() {
	local template_dir="$1"

	_info "Installing neovim..."
	install_nvim

	# Generate random SSH port
	local ssh_port
	ssh_port="$((1024 + RANDOM % (65535 - 1024 + 1)))"
	$SUDO install -m 0755 -o "root" -g "root" "/dev/null" "$CUSTOM_SSH_PORT_FILE"
	printf "%s" "$ssh_port" | $SUDO tee "$CUSTOM_SSH_PORT_FILE"

	# openssh-server
	[[ -e "/etc/ssh" ]] && $SUDO rm -rf "/etc/ssh"
	$SUDO install -m 0755 -o "root" -g "root" "/etc/ssh" -d
	$SUDO install -m 0600 -o "root" -g "root" "${DF_REPO["template_dir"]}/openssh-server/sshd_config" "/etc/ssh/sshd_config"
	$SUDO sed -i "s/^Port [0-9]\+/Port $ssh_port/" "/etc/ssh/sshd_config"

	# iptables
	[[ -e "/etc/iptables" ]] && $SUDO rm -rf "/etc/iptables"
	$SUDO install -m 0755 -o "root" -g "root" "/etc/iptables" -d
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables/rules.v4" "/etc/iptables/rules.v4"
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables/rules.v6" "/etc/iptables/rules.v6"
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables-restore.service" "/etc/systemd/system/iptables-restore.service"
	$SUDO sed -i "s|^-A INPUT -p tcp --dport [0-9]\+ -j ACCEPT$|-A INPUT -p tcp --dport $ssh_port -j ACCEPT|" "/etc/iptables/rules.v4"

	if [[ "$IS_DOCKER" == "false" ]]; then
		# Reload sshd config
		_info "Restart sshd service"
		$SUDO systemctl restart sshd
		# Enable iptables-restore.service
		_info "Reload systemctl daemon"
		$SUDO systemctl daemon-reload
		_info "Enable iptables-restore service"
		$SUDO systemctl enable iptables-restore.service
	fi
}

_setup_vultr() {
	if [[ "$IS_DEBUG" == "true" ]]; then
		_debug "New debug symlink: \"${LC["path"]}${DF_REPO["_dir"]}${C["0"]}\" -> \"${LC["path"]}$DOCKER_VOLUME_DIR${C["0"]}\""
		ln -s "$DOCKER_VOLUME_DIR" "${DF_REPO["_dir"]}"
	else
		git clone -b "$GIT_REMOTE_BRANCH" "${URL["dotfiles_repo"]}" "${DF_REPO["_dir"]}"
	fi

	local ssh_port
	if [[ ! -e "$CUSTOM_SSH_PORT_FILE" ]]; then
		_info "New system installation. Setup network config..."
		ssh_port=$(setup_system "${DF_REPO["template_dir"]}")
	else
		ssh_port="$(<"$CUSTOM_SSH_PORT_FILE")"
	fi

	_info "Start linking dotfiles"
	link "$HOME" "${DF_REPO["current_host"]}" "${DF_REPO["default_host"]}"

	_info "Start package installation"
	while read -r pkg; do
		if ! is_cmd_exist "$pkg"; then
			install_package "$pkg"
		fi
	done <"${DF_REPO["package_list"]}"

	if is_cmd_exist ufw; then
		_info "Uninstall UFW"
		$SUDO ufw disable
		remove_package "ufw"
	fi

	_info "Start SSH setup"
	local ssh_dir="$HOME/.ssh"
	$SUDO install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "$ssh_dir/authorized_keys"
	$SUDO install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "$ssh_dir/config"

	# Zsh plugins
	local z_plugin_dir="$HOME/.local/share/zsh/plugins"
	git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$z_plugin_dir/zsh-autosuggestions"
	git clone "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$z_plugin_dir/zsh-syntax-highlighting"
	git clone "https://github.com/sindresorhus/pure.git" "$z_plugin_dir/pure"
	install_zoxide "$INSTALL_USER"
	install_starship "$INSTALL_USER"

	if [[ "$IS_DOCKER" == "false" ]]; then
		_info "Executing Docker installation script.."
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
	} >>"${DF_DATA["secret"]}"

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
	} >>"${DF_DATA["secret"]}"

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
	_warn "dotfiles for arch - Not implemented yet"
}

run() {
	local session_id
	session_id="$(get_safe_random_str 4)"
	# tODO: draw line
	draw_line "Begin $(clr "$CURRENT_USER ($session_id)" "${LC["highlight"]}")"
	_vars "HOSTNAME" "INSTALL_USER" "CURRENT_USER" "IS_DOCKER" "IS_DEBUG"

	_debug "Bash version: $BASH_VERSION"

	# Download script
	if [[ -z "$SCRIPT_NAME" ]]; then
		[[ -e "$TMP_INSTALL_SCRIPT_FILE" ]] && $SUDO rm -f "$TMP_INSTALL_SCRIPT_FILE"

		if [[ "$IS_DEBUG" == "true" ]]; then
			_debug "Copy script from \"${C["y"]}${DOCKER_VOLUME_DIR}/install.sh${C["0"]}\""
			$SUDO install -m 0755 -o root -g root "${DOCKER_VOLUME_DIR}/install.sh" "$TMP_INSTALL_SCRIPT_FILE"
		else
			_debug "Download script from ${C["y"]}${URL["dotfiles_install_script"]}${C["0"]}"
			curl-fsSL "${URL["dotfiles_install_script"]}" -o "$TMP_INSTALL_SCRIPT_FILE"
			chmod 755 "$TMP_INSTALL_SCRIPT_FILE" && chown root:root "$TMP_INSTALL_SCRIPT_FILE"
		fi

		get_script_run_cmd "$TMP_INSTALL_SCRIPT_FILE" "run_cmd"
		_info "Exit and restarting..."
		"${run_cmd[@]}"
		exit 0
	fi

	############### Main Process ###############
	if is_usr_exist "$INSTALL_USER"; then
		cd "$HOME"
		"_setup_$HOSTNAME"
	else
		if [[ -n "$SUDO" ]]; then
			sudo -v
		fi

		_info "Create user: ${LC["highlight"]}${INSTALL_USER}${C["0"]}"

		# Create user
		local passwd
		passwd="$(get_random_str $PASSWD_LENGTH)"
		add_user "$INSTALL_USER" "$passwd"

		# Create "~/dotfiles-data"
		$SUDO install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "${DF_DATA["_dir"]}" -d
		$SUDO install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "${DF_DATA["backups_dir"]}" -d
		$SUDO install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "${DF_DATA["secret"]}"
		printf "# DELETE this file, once you complete the process.\n\n" >>"${DF_DATA["secret"]}"
		printf "# Password (%s)\n%s\n\n" "$INSTALL_USER" "$passwd" >>"${DF_DATA["secret"]}"

		local run_cmd
		get_script_run_cmd "$(get_script_path)" "run_cmd"
		_info "Done user creation. Exit and starting install script as ${LC["highlight"]}$INSTALL_USER${C["0"]}..."
		sudo -u "$INSTALL_USER" -- "${run_cmd[@]}"
		exit 0
	fi

	[[ -e "$HOME/.sudo_as_admin_successful" ]] && rm -f "$HOME/.sudo_as_admin_successful"

	if [[ "$IS_DOCKER" == "true" ]]; then
		_info "Docker mode is enabled. Keeping docker container running..."
		tail -f /dev/null
	fi

	draw_line "End $(clr "$CURRENT_USER ($session_id)" "${LC["highlight"]}") session"
}

run
