#!/bin/bash
set -e -u -o pipefail -C

is_root() {
	if [[ "$(id -u)" == "0" ]]; then
		return 0
	else
		return 1
	fi
}

is_contain() {
	local value="$1"
	local -n arr_ref="$2"

	if [[ " ${arr_ref[*]} " =~ [[:space:]]$value[[:space:]] ]]; then
		return 0
	else
		return 1
	fi
}

get_os_name() {
	if [[ -f "/etc/os-release" ]]; then
		source "/etc/os-release"
		if [[ "$NAME" == "Debian"* ]]; then
			printf "%s" "debian"
		fi
	fi
}

### Parse Mode
declare -ar _MODES=("init" "adduser" "apply" "update")
if [[ -z "${1+x}" ]] || ! is_contain "$1" "_MODES"; then
	printf "Please specify the option: %s\n" "${_MODES[*]}" >&2
	exit 1
fi

declare -r MODE="$1"
shift

### Parse Optional Arguments
declare -a _ARGS=("$@")
declare -ar _PARAM_0=("--user" "-u" "value" "")
declare -ar _PARAM_1=("--host" "-h" "value" "")
declare -ar _PARAM_2=("--docker" "-d" "flag" "false")
declare -ar _PARAM_3=("--debug" "-de" "flag" "false")
declare -A _PARAMS=()
declare _IS_OPTIONAL_ARGS_PARSED="false"
_show_missing_param_err() {
	printf "Please provide a value for '%s' (%s) parameter.\n" "$1" "$2" >&2
	exit 1
}

_parse_optional_args() {
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
						_show_missing_param_err "$long_name" "$short_name"
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
			_PARAMS["$key"]="$default_value"
		fi
		i=$((i + 1))
	done

	declare -r _IS_OPTIONAL_ARGS_PARSED="true"
}

get_optional_arg() {
	local name="$1"
	if [[ "$_IS_OPTIONAL_ARGS_PARSED" == "false" ]]; then
		_parse_optional_args
	fi
	printf "%s" "${_PARAMS[$name]}"
}

HOSTNAME=$(get_optional_arg "host")
declare -r HOSTNAME
IS_DOCKER=$(get_optional_arg "docker")
declare -r IS_DOCKER
IS_DEBUG=$(get_optional_arg "debug")
declare -r IS_DEBUG
CURRENT_USER=$(whoami)
declare -r CURRENT_USER
INSTALL_USER=$(get_optional_arg "user")
# declare -r INSTALL_USER

declare -r GIT_REMOTE_BRANCH="main"
declare -r HOST_PREFIX="${HOSTNAME^^}##"
OS="$(get_os_name)"
declare -r OS
declare -r PASSWD_LENGTH=72
declare -r INSTALL_USER_HOME="/home/$INSTALL_USER"
declare -r TMP_DIR="/var/tmp"
declare -r DOCKER_VOLUME_DIR="/app"
declare -r INIT_FLAG_FILE="/etc/DOTFILES"

declare -A DF_REPO
DF_REPO["_dir"]="/usr/local/share/conf"
DF_REPO["linux_dir"]="${DF_REPO["_dir"]}/linux"
DF_REPO["package_list"]="${DF_REPO["linux_dir"]}/packages.txt"
DF_REPO["template_dir"]="${DF_REPO["linux_dir"]}/template"
DF_REPO["hosts_dir"]="${DF_REPO["linux_dir"]}/hosts"
DF_REPO["default_host"]="${DF_REPO["hosts_dir"]}/_default"
DF_REPO["current_host"]="${DF_REPO["hosts_dir"]}/${HOSTNAME,,}"
declare -r DF_REPO

declare -A DF_DATA
DF_DATA["_dir"]="$INSTALL_USER_HOME/conf"
DF_DATA["secret"]="${DF_DATA["_dir"]}/secret"
DF_DATA["backups_dir"]="${DF_DATA["_dir"]}/backups"
declare -A DF_DATA

# TODO: Deprecated
declare -Ar URL=(
	["conf_repo"]="https://github.com/ardotsis/conf.git"
	["dotfiles_install_script"]="https://raw.githubusercontent.com/ardotsis/conf/refs/heads/main/install.sh"
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
		[[ $ignore =~ (^|[[:space:]])$funcname($|[[:space:]]) ]] && continue # TODO: use is_contain
		lineno="${BASH_LINENO[$((i - 2))]}"
		caller="$funcname"
		break
	done

	local timestamp
	timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
	printf "[%s] [%b%s%b] [%s:%s] %b\n" "$timestamp" "${LC["${level}"]}" "${level^^}" "${C["0"]}" "$caller" "$lineno" "$msg" >&2
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
	printf "%b" "$txt"
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
	local pkg_name="$1"

	if [[ "$OS" == "debian" ]]; then
		apt-get install -y --no-install-recommends "$pkg_name"
	fi
}

remove_package() {
	local pkg_name="$1"

	if [[ "$OS" == "debian" ]]; then
		apt-get remove -y "$pkg_name"
		apt-get purge -y "$pkg_name"
		apt-get autoremove -y
		apt-get clean
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
	tar -C "/opt" -xzf "$tgz_path"
	rm -rf "$tgz_path"
}

install_zoxide() {
	local bin_dir="$1"
	local man1_dir="$2"

	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/ajeetdsouza/zoxide/releases/latest/download/zoxide-0.9.8-x86_64-unknown-linux-musl.tar.gz")

	local tmp_dir="$TMP_DIR/zoxide"
	mkdir $tmp_dir
	tar -C "$tmp_dir" -xzf "$tgz_path"
	cp "$tmp_dir/man/man1/"* "$man1_dir"
	mv "$tmp_dir/zoxide" "$bin_dir"
	rm -rf "$tmp_dir" "$tgz_path"
}

install_starship() {
	local bin_dir="$1"

	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/starship/starship/releases/download/v1.24.2/starship-x86_64-unknown-linux-musl.tar.gz")

	tar -C "$TMP_DIR" -xzf "$tgz_path"
	mv "$TMP_DIR/starship" "$bin_dir"
	rm -rf "$tgz_path"
}
build_home() {
	mkdir -p "$INSTALL_USER_HOME"/{.cache,.config,.local,.ssh}
	mkdir "$INSTALL_USER_HOME/.local"/{bin,share,state}
	mkdir "$INSTALL_USER_HOME/.cache/zsh"
	mkdir "$INSTALL_USER_HOME/.local/share/zsh"
	mkdir -p "${DF_DATA["backups_dir"]}"

	chown -R "$INSTALL_USER:$INSTALL_USER" "$INSTALL_USER_HOME"
	chmod -R 700 "$INSTALL_USER_HOME"

	install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "${DF_DATA["secret"]}"
}

add_user() {
	local passwd="$1"

	if [[ "$OS" == "debian" ]]; then
		useradd -s "/bin/zsh" -G "sudo" "$INSTALL_USER"
		printf "%s:%s" "$INSTALL_USER" "$passwd" | chpasswd
		# Allow "sudo" command without password
		printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$INSTALL_USER" | tee "/etc/sudoers.d/$INSTALL_USER"
		build_home
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
	local -n left_arr="$1"
	local -n right_arr="$2"
	local mode="$3"
	# shellcheck disable=SC2178
	local -n result_arr="$4"

	case "$mode" in
	union) comm_num="-12" ;;
	left_only) comm_num="-23" ;;
	right_only) comm_num="-13" ;;
	*) return 1 ;;
	esac

	# shellcheck disable=SC2034
	mapfile -d $'\0' result_arr < <(comm "$comm_num" -z \
		<(printf "%s\0" "${left_arr[@]}" | sort -z) \
		<(printf "%s\0" "${right_arr[@]}" | sort -z))
}

link() {
	local target_dir="$1"
	local host_dir="${2:-}" # Preferrer
	local default_dir="${3:-}"

	_vars "target_dir" "host_dir" "default_dir"

	local all_host_items=() all_default_items=()
	[[ -z "$host_dir" ]] || get_items "$host_dir" "all_host_items"
	[[ -z "$default_dir" ]] || get_items "$default_dir" "all_default_items"

	# shellcheck disable=SC2034
	local union_items=() host_items=() default_items=()
	if [[ -n "$host_dir" && -n "$default_dir" ]]; then
		get_mixed_items "all_host_items" "all_default_items" "union" "union_items"
		get_mixed_items "all_host_items" "all_default_items" "left_only" "host_items"
		get_mixed_items "all_host_items" "all_default_items" "right_only" "default_items"
	elif [[ -n "$host_dir" ]]; then
		# shellcheck disable=SC2034
		local host_items=("${all_host_items[@]}")
	elif [[ -n "$default_dir" ]]; then
		# shellcheck disable=SC2034
		local default_items=("${all_default_items[@]}")
	fi

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
			# shellcheck disable=SC1087
			if [[ "$item_type" == "default" && " ${prefixed_items[*]} " =~ [[:space:]]$renamed_item[[:space:]] ]]; then
				continue
			fi

			local as_target_item="${target_dir}/${item}"
			local as_host_item="${host_dir}/${item}"
			local as_default_item="${default_dir}/${item}"
			local actual_path="${!as_var}"

			local fixed_target_path=""
			if [[ "$item_type" == "host" && "$item" == "$HOST_PREFIX"* ]]; then
				fixed_target_path="${target_dir}/${renamed_item}"
				prefixed_items+=("${renamed_item}")
			fi

			if [[ -d "$actual_path" ]]; then
				[[ -n "$fixed_target_path" ]] && as_target_item="$fixed_target_path"
				install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "$as_target_item" -d
				_debug "Created: \"${LC["path"]}$as_target_item${C["0"]}\""

				if [[ "$item_type" == "union" ]]; then
					link "$as_target_item" "$as_host_item" "$as_default_item" "false"
				elif [[ "$item_type" == "host" ]]; then
					link "$as_target_item" "$as_host_item" "false"
				elif [[ "$item_type" == "default" ]]; then
					link "$as_target_item" "" "$as_default_item" "false"
				fi
			elif [[ -f "$actual_path" ]]; then
				[[ -n "$fixed_target_path" ]] && as_target_item="$fixed_target_path"
				install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "$actual_path" "$as_target_item"
				_debug "Created: \"${LC["path"]}$as_target_item${C["0"]}\""
			fi
		done
	done
}

##################################################
#                   Installers                   #
##################################################
setup_network() {
	# Generate random SSH port
	local ssh_port="$1"

	# openssh-server
	[[ -e "/etc/ssh" ]] && $SUDO rm -rf "/etc/ssh"
	$SUDO install -m 0755 -o "root" -g "root" "/etc/ssh" -d
	$SUDO install -m 0600 -o "root" -g "root" "${DF_REPO["template_dir"]}/openssh-server/sshd_config" "/etc/ssh/sshd_config"
	$SUDO sed -i "s/^Port [0-9]\+/Port $ssh_port/" "/etc/ssh/sshd_config"
	$SUDO ssh-keygen -A

	# iptables
	[[ -e "/etc/iptables" ]] && $SUDO rm -rf "/etc/iptables"
	$SUDO install -m 0755 -o "root" -g "root" "/etc/iptables" -d
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables/rules.v4" "/etc/iptables/rules.v4"
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables/rules.v6" "/etc/iptables/rules.v6"
	$SUDO install -m 0644 -o "root" -g "root" "${DF_REPO["template_dir"]}/iptables/iptables-restore.service" "/etc/systemd/system/iptables-restore.service"
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
	### TODO: REMOVE UNNECCESSARY "$SUDO" CUZ IT"S USER's OP

	_info "Start package installation"
	while read -r pkg; do
		if ! is_cmd_exist "$pkg"; then
			install_package "$pkg"
		fi
	done <"${DF_REPO["package_list"]}"

	local ssh_port
	if [[ ! -e "$INIT_FLAG_FILE" ]]; then
		ssh_port="$((1024 + RANDOM % (65535 - 1024 + 1)))"
		_info "Setup system installation using templates"
		install_nvim
		setup_network "$ssh_port"

		# Create flag file
		$SUDO install -m 0755 -o "root" -g "root" "/dev/null" "$INIT_FLAG_FILE"
		printf "%s" "$ssh_port" | $SUDO tee "$INIT_FLAG_FILE"
	else
		ssh_port="$(<"$INIT_FLAG_FILE")"
	fi

	_info "Start linking dotfiles"
	link "$INSTALL_USER_HOME" "${DF_REPO["current_host"]}" "${DF_REPO["default_host"]}"

	if is_cmd_exist ufw; then
		_info "Uninstall UFW"
		$SUDO ufw disable
		remove_package "ufw"
	fi

	_info "Start SSH setup"
	local ssh_dir="$INSTALL_USER_HOME/.ssh"
	$SUDO install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "$ssh_dir/authorized_keys"
	$SUDO install -m 0600 -o "$INSTALL_USER" -g "$INSTALL_USER" /dev/null "$ssh_dir/config"

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
		printf "# Client's SSH template\n"
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

check_is_root() {
	if ! is_root; then
		printf "%b%s%b\n" "${C[r]}" "conf: need root privilege to run this command" "${C[0]}"
		exit 1
	fi
}

cmd_init() {
	check_is_root

	if [[ -e "${DF_REPO["_dir"]}" ]]; then
		printf "%b%s\n%s%b\n" "${C[y]}" "conf is already installed." "Use 'adduser' command to create new user." "${C[0]}"
		exit 1
	fi

	if ! is_cmd_exist "git"; then
		install_package "git"
	fi

	# Install conf repository
	if [[ "$IS_DEBUG" == "true" ]]; then
		ln -sf "$DOCKER_VOLUME_DIR" "${DF_REPO["_dir"]}"
	else
		git clone -b $GIT_REMOTE_BRANCH "${URL["conf_repo"]}" "${DF_REPO["_dir"]}"
	fi

	ln -sf "${DF_REPO["_dir"]}/conf.sh" "/usr/local/bin/conf"
	chmod +x "${DF_REPO["_dir"]}/conf.sh"

	# Install binaries
	install_nvim

	local data_dir="/usr/local"
	local zsh_plugins_dir="$data_dir/share/zsh/plugins"

	[[ ! -e "$zsh_plugins_dir" ]] && mkdir -p "$zsh_plugins_dir"
	git clone "https://github.com/zsh-users/zsh-autosuggestions.git" "$zsh_plugins_dir/zsh-autosuggestions"
	git clone "https://github.com/zsh-users/zsh-syntax-highlighting.git" "$zsh_plugins_dir/zsh-syntax-highlighting"
	git clone "https://github.com/sindresorhus/pure.git" "$zsh_plugins_dir/pure"

	local man1_dir="$data_dir/share/man/man1"
	[[ ! -e "$man1_dir" ]] && mkdir -p "$man1_dir"
	install_zoxide "$data_dir/bin" "$man1_dir"
	install_starship "$data_dir/bin"

	# Create user (optional)
	if [[ -n "$INSTALL_USER" ]]; then
		_info "Initializing user (additional)"
		cmd_adduser
	fi

	printf "%b%s%b\n" "${C[g]}" "conf has installed." "${C[0]}"
}

cmd_adduser() {
	check_is_root

	if [[ -z "$INSTALL_USER" ]]; then
		echo "Please specify username using --user (-u) parameter"
		exit 1
	fi

	# Backup home directory
	if is_usr_exist "$INSTALL_USER"; then
		_info "Backup current home directory"
		mv "$INSTALL_USER_HOME" "$INSTALL_USER_HOME.old_$(get_safe_random_str 16)"
		rm deluser "$INSTALL_USER" # WARN: Debian only!
	fi

	# Create user
	local passwd
	passwd="$(get_random_str $PASSWD_LENGTH)"
	add_user "$passwd"

	# Store password into "~/.conf/secret"
	{
		printf "# DELETE this file, once you complete the process.\n\n"
		printf "# User password: %s\n" "$passwd"
	} | tee -a "${DF_DATA["secret"]}" >/dev/null

	cmd_apply
}

cmd_apply() {
	check_is_root

	if [[ -z "$INSTALL_USER" ]]; then
		INSTALL_USER=$CURRENT_USER
	fi

	local host_dir=""
	if [[ -n "$HOSTNAME" ]]; then
		host_dir="${DF_REPO["current_host"]}"
	fi

	link "/home/$INSTALL_USER" "$host_dir" "${DF_REPO["default_host"]}"
}

cmd_update() {
	printf "%b%s%b\n" "${C[y]}" "Updating..." "${C[0]}"
}

run() {
	"cmd_$MODE"

	if [[ "$IS_DOCKER" == "true" ]]; then
		printf "Keeping docker container running...\n"
		tail -f /dev/null
	fi
}

run

# Or REMOVE $SUDO entirly. always root (change w/ chmod chown) IT"S SO CLEAN RIGHT?
# TODO: remove INFO log (use debug only, use PRINTF for user info prompt)
