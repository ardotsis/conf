#!/bin/bash
set -e -u -o pipefail -C

declare -r REPO_URL="https://github.com/ardotsis/conf.git"
declare -r REPO_INSTALL_DIR="/usr/local/share/conf"
declare -r TMP_DIR="/var/tmp"
declare -r DOCKER_VOLUME_DIR="/app"
declare -r SECRET_FILENAME="conf-secret"
# shellcheck disable=SC2155
declare -r CURRENT_USER="$(whoami)"
declare -r PASSWD_LENGTH=72

declare -A CONF_REPO
CONF_REPO["data"]="$REPO_INSTALL_DIR/data"
CONF_REPO["etc"]="${CONF_REPO["data"]}/etc"
CONF_REPO["profiles"]="${CONF_REPO["data"]}/profiles"
declare -r CONF_REPO

declare -Ar C=(
	[0]="\033[0m" # Reset
	[B]="\033[1m" # Bold

	# Normal
	[r]="\033[0;31m" # Red
	[y]="\033[0;33m" # Orange/Yellow
	[g]="\033[0;32m" # Green
	[c]="\033[0;36m" # Cyan
	[b]="\033[0;34m" # Blue
	[p]="\033[0;35m" # Purple
	[k]="\033[0;30m" # Black
	[w]="\033[0;37m" # White

	# Bold
	[R]="\033[1;31m"  # Bold Red
	[Y]="\033[1;33m"  # Bold Orange/Yellow
	[G]="\033[1;32m"  # Bold Green
	[C]="\033[1;36m"  # Bold Cyan
	[B_]="\033[1;34m" # Bold Blue (L for Light/Large)
	[P]="\033[1;35m"  # Bold Purple
	[K]="\033[1;30m"  # Bold Black
	[W]="\033[1;37m"  # Bold White
)

declare -Ar LC=(
	[debug]="${C["w"]}"
	[info]="${C["g"]}"
	[warn]="${C["Y"]}"
	[error]="${C["r"]}"
	[var]="${C["p"]}"
	[value]="${C["c"]}"
	[path]="${C["y"]}"
	[highlight]="${C["r"]}"
)

declare -Ar _OPTION_MAP=(
	[--help]="flag:false"
	[-h]="help"

	[--version]="flag:false"
	[-v]="version"

	[--debug]="flag:false"
	[-d]="debug"

	[--docker]="flag:false"
	[-dk]="docker"

	["--show-log"]="flag:false"
	[-l]="show-log"

	[--love]="value:"
	[-luv]="love"
)

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

	# shellcheck disable=SC1087
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

print_help() {
	local indent="    "
	local col_width="18"
	local fmt="${indent}%-${col_width}s %s\n"

	printf "Usage:\n"
	printf "${indent}%s\n" "conf [option] <command> [<args>]"
	printf "${indent}%s\n" "conf [-v | --version]"
	printf "${indent}%s\n" "conf [-h | --help]"
	printf "\n"

	printf "Options:\n"
	printf "$fmt" "-d,  --debug" "Enable debug mode"
	printf "$fmt" "-dk, --docker" "Enable Docker mode"
	printf "\n"

	printf "Commands:\n"
	printf "$fmt" "install" "install description"
	printf "$fmt" "adduser" "adduser description"
	printf "$fmt" "apply" "apply description"
	printf "$fmt" "pull" "pull description"
}

print_version() {
	printf "conf version 1.0\n"
}

get_err_msg() {
	local msg="$1"
	local with_tip="${2:-false}"

	local tip=""
	if [[ "$with_tip" == "true" ]]; then
		tip=" See 'conf --help'."
	fi
	printf "conf: %s%s\n" "$msg" "$tip"
}

parse_args() {
	local -n option_hash="$1"
	local -n commands_arr="$2"
	local -n err_msg="$3"
	shift 3
	local args=("$@")

	_rm_hyphen() {
		printf "%s" "${1#"${1%%[!-]*}"}"
	}

	for hyphen_option in "${!_OPTION_MAP[@]}"; do
		if [[ "$hyphen_option" == "--"* ]]; then
			IFS=":" read -r _ _default_value <<<"${_OPTION_MAP[$hyphen_option]}"
			option_hash["$(_rm_hyphen "$hyphen_option")"]="$_default_value"
		fi
	done

	local i last_i input
	i=0
	last_i=$(("${#args[@]}" - 1))
	skip_index="false"

	for input in "${args[@]}"; do
		if [[ "$skip_index" == "true" ]]; then
			skip_index="false"
			i=$((i + 1))
			continue
		fi

		if [[ -n "${_OPTION_MAP["$input"]+x}" ]]; then
			local option_type restored_option=""
			IFS=":" read -r option_type _ <<<"${_OPTION_MAP["$input"]}"
			if [[ "$input" =~ ^-[^-] ]]; then
				restored_option="$option_type"
				IFS=":" read -r option_type _ <<<"${_OPTION_MAP["--$option_type"]}"
			fi

			local insert_val
			if [[ "$option_type" == "flag" ]]; then
				insert_val="true"
			elif [[ "$option_type" == "value" ]]; then
				skip_index="true"
				local val_i=$((i + 1))
				if ((val_i > last_i)); then
					err_msg="$(get_err_msg "'$input' require a value." "true")"
					return 1
				fi
				insert_val="${args["$val_i"]}"
			fi

			if [[ -z "$restored_option" ]]; then
				option_hash["$(_rm_hyphen "$input")"]="$insert_val"
			else
				# shellcheck disable=SC2034
				option_hash["$restored_option"]="$insert_val"
			fi
		else
			if [[ "$input" == "-"* ]]; then
				# shellcheck disable=SC2034
				err_msg="$(get_err_msg "'$input' is not a conf option." "true")"
				return 1
			else
				break
			fi
		fi
		i=$((i + 1))
	done
	# shellcheck disable=SC2034
	commands_arr=("${args[@]:$i}")
	return 0
}

declare -A _OPTION=()
declare _PARSE_ERR_MSG=""
declare -a CMDS=()

if ! parse_args "_OPTION" "CMDS" "_PARSE_ERR_MSG" "$@"; then
	printf "%s\n" "$_PARSE_ERR_MSG" >&2
	exit 1
fi

declare -r IS_DEBUG="${_OPTION["debug"]}"
declare -r IS_DOCKER="${_OPTION["docker"]}"
declare -r SHOW_LOG="${_OPTION["show-log"]}"
declare -r SHOW_HELP="${_OPTION["help"]}"
declare -r SHOW_VERSION="${_OPTION["version"]}"
declare -r LOVE="${_OPTION["love"]}"
declare -r OS="$(get_os_name)"

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
	if [[ "$SHOW_LOG" == "true" ]]; then
		printf "[%s] [%b%s%b] [%s:%s] %b\n" "$timestamp" "${LC["${level}"]}" "${level^^}" "${C["0"]}" "$caller" "$lineno" "$msg" >&2
	fi
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
	tgz_path=$(get_tmp_curl_file "https://github.com/ajeetdsouza/zoxide/releases/latest/download/zoxide-0.9.9-x86_64-unknown-linux-musl.tar.gz")

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
	local username="$1"
	local home="/home/$username"

	mkdir -p "$home"/{.cache,.config,.local,.ssh}
	mkdir "$home/.local"/{bin,share,state}
	mkdir "$home/.cache/zsh"
	mkdir "$home/.local/share/zsh"
	# mkdir -p "${DF_DATA["backups_dir"]}"

	chown -R "$username:$username" "$home"
	chmod -R 700 "$home"
	# install -m 0600 -o "$username" -g "$username" /dev/null "${DF_DATA["secret"]}"
}

add_user() {
	local username="$1"
	local passwd="$2"

	if [[ "$OS" == "debian" ]]; then
		useradd -s "/bin/zsh" -G "sudo" "$username"
		printf "%s:%s" "$username" "$passwd" | chpasswd
		# Allow "sudo" command without password
		printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$username" | tee "/etc/sudoers.d/$username"
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
		local as_var
		if [[ "$item_type" == "union" ]]; then
			as_var="as_host_item"
		else
			as_var="as_${item_type}_item"
		fi

		local item
		for item in "${items[@]}"; do
			[[ -z "$item" ]] && continue
			# Skip host prefixed item
			local renamed_item="${item#"${HOST_PREFIX}"}"
			# shellcheck disable=SC1087
			if [[ "$item_type" == "default" ]] && is_contain "$renamed_item" "prefixed_items"; then
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

cmd_install() {
	local username="${1:-}"
	local profile="${2:-}"

	check_is_root

	if [[ -e "$REPO_INSTALL_DIR" ]]; then
		printf "%b%s\n%s%b\n" "${C[y]}" "conf is already installed." "Use 'adduser' command to create new user." "${C[0]}"
		exit 1
	fi

	if ! is_cmd_exist "git"; then
		install_package "git"
	fi

	# Install conf repository
	if [[ "$IS_DEBUG" == "true" ]]; then
		ln -sf "$DOCKER_VOLUME_DIR" "$REPO_INSTALL_DIR"
	else
		git clone -b main "$REPO_URL" "$REPO_INSTALL_DIR"
	fi

	ln -sf "$REPO_INSTALL_DIR/conf.sh" "/usr/local/bin/conf"
	chmod +x "$REPO_INSTALL_DIR/conf.sh"

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
	if [[ -n "$username" ]]; then
		cmd_adduser "$username" "$profile"
	fi

	printf "%b%s%b\n" "${C[G]}" "conf has installed." "${C[0]}"
}

cmd_adduser() {
	local username="${1:-}"
	local profile="${2:-}"

	check_is_root

	if [[ "$username" == "root" ]]; then
		cmd_apply "$username" "$profile"
		return 0
	fi

	local home="/home/$username"
	# Backup home directory
	if is_usr_exist "$username"; then
		_info "Backup current home directory"
		if [[ -e "$home" ]]; then
			mv "$home" "$home.old_$(get_safe_random_str 16)"
		fi
		deluser "$username"
	fi

	local passwd
	passwd="$(get_random_str $PASSWD_LENGTH)"
	add_user "$username" "$passwd"

	# Store password into "~/.conf/secret"
	install -m 0600 -o "$username" -g "$username" /dev/null "$home/$SECRET_FILENAME"
	printf "Password: %s\n" "$passwd" >>"$home/$SECRET_FILENAME"

	cmd_apply "$username" "$profile"
}

cmd_apply() {
	local username="${1:-$CURRENT_USER}"
	local profile="${2:-}"

	local profile_dir=""
	if [[ -n "$profile" ]]; then
		profile_dir="${CONF_REPO["profiles"]}/$profile"
	fi

	local home
	if [[ "$username" == "root" ]]; then
		home="/root"
	else
		home="/home/$username"
	fi

	HOST_PREFIX="${profile}##" INSTALL_USER="$username" link "$home" "$profile_dir" "${CONF_REPO["profiles"]}/default"

	printf "${C[G]}$profile${C[W]} profile has applied.${C[0]}\n"
}

main_() {
	if [[ (($# -eq 0)) || "$SHOW_HELP" == "true" ]]; then
		print_help
		exit 0
	fi

	if [[ "$SHOW_VERSION" == "true" ]]; then
		print_version
		exit 0
	fi

	if (("${#CMDS[@]}" == 0)); then
		printf "%s\n" "$(get_err_msg "Please specify the conf command." "true")" >&2
		exit 1
	fi

	if [[ -n "$LOVE" ]]; then
		printf "i love you %s.\n" "$LOVE"
	fi

	local -ar modes=(
		"install"
		"adduser"
		"apply"
		"pull"
	)

	local mode="${CMDS[0]}"
	if ! is_contain "$mode" "modes"; then
		printf "%s\n" "$(get_err_msg "'$mode' is not conf command." "true")" >&2
		exit 1
	fi

	# Run command
	"cmd_$mode" "${CMDS[@]:1}"

	if [[ "$IS_DEBUG" == "true" ]]; then
		printf "Keeping docker container running...\n"
		tail -f /dev/null
	fi
}

main_ "$@"
