#!/bin/bash
set -euo pipefail -o noclobber

# System
declare -r TMP_DIR="/var/tmp"
declare -r LOCAL_DIR="/usr/local"
# shellcheck disable=SC2155
declare -r CURRENT_USER="$(whoami)"
# shellcheck disable=SC2155

# Docker environment
declare -r DOCKER_IS_DOCKER
declare -r DOCKER_APP_DIR
declare -r DOCKER_DEV_APP_DIR

if [[ -n "${1+x}" && "$1" == "_docker-entrypoint" ]]; then
	declare -r IS_DOCKER_ENTRYPOINT="true"
	shift
else
	declare -r IS_DOCKER_ENTRYPOINT="false"
fi

# App
declare -r REPO_URL="https://github.com/ardotsis/conf.git"
declare -r REPO_INSTALL_DIR="/usr/local/share/conf"
declare -r REPO_DATA_DIR="$REPO_INSTALL_DIR/data"
declare -r REPO_USER_DIR="$REPO_DATA_DIR/user"
declare -r REPO_PROFILES_DIR="$REPO_DATA_DIR/profiles"
declare -r SSH_PORT_FILE="$REPO_DATA_DIR/ssh_port"
declare -r TRACK_FILENAME="track"
declare -r PACKAGE_LIST_FILENAME="packages"
declare -r DEFAULT_PROFILE_NAME="default"

# User
declare -r SECRET_FILENAME="conf_secret"
declare -r PASSWD_LENGTH=72

# ZSH
declare -r ZSH_PLUGINS_DIR="$LOCAL_DIR/share/zsh/plugins"
declare -ar ZSH_PLUGIN_REPOS=(
	zsh-users/zsh-autosuggestions
	zdharma-continuum/fast-syntax-highlighting
	sindresorhus/pure
)

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
	[Y]="\033[1;33m"  # Bold Yellow
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

	["--show-log"]="flag:false"
	[-l]="show-log"

	[--love]="value:"
	[-luv]="love"
)

get_git_commit_id() {
	printf "%s" "$(git -C "$REPO_INSTALL_DIR" rev-parse HEAD)"
}

get_profile_dir() {
	local profile="$1"
	printf "%s/%s" "$REPO_PROFILES_DIR" "$profile"
}

get_home_profile_dir() {
	local profile="$1"

	local profile_dir
	profile_dir="$(get_profile_dir "$profile")"

	printf "%s/home/%s" "$profile_dir" "$profile"
}

is_root() {
	[[ "$(id -u "$CURRENT_USER")" == "0" ]] && return 0
	return 1
}

is_contain() {
	local value="$1"
	local -n arr_ref="$2"

	if [[ " ${arr_ref[*]} " =~ [[:space:]]"$value"[[:space:]] ]]; then
		return 0
	else
		return 1
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
	if [[ $with_tip == "true" ]]; then
		tip=" See 'conf --help'."
	fi

	printf "conf: %s%s\n" "$msg" "$tip"
}

install_cmd() {
	_debug "Create item: ${C[y]}$*${C[0]}"
	install "${@}"
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
		if [[ $skip_index == "true" ]]; then
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

# Argument parser
declare -A _OPTION=()
declare _PARSE_ERR_MSG=""
declare -a CMDS=()

if ! parse_args "_OPTION" "CMDS" "_PARSE_ERR_MSG" "$@"; then
	printf "%s\n" "$_PARSE_ERR_MSG" >&2
	exit 1
fi

declare -r IS_DEBUG="${_OPTION["debug"]}"
declare -r SHOW_LOG="${_OPTION["show-log"]}"
declare -r SHOW_HELP="${_OPTION["help"]}"
declare -r SHOW_VERSION="${_OPTION["version"]}"
declare -r LOVE="${_OPTION["love"]}"

##################################################
#                 Pure Functions                 #
##################################################
_log() {
	local level="$1"
	local msg="$2"

	local i=0
	local lineno="${BASH_LINENO[1]}"
	local caller=" <GLOBAL> "
	local -r ignore="_log _debug _info _warn _error _vars install_cmd main"
	# todo: prefix "_" func to ignore in log (& main)
	for funcname in "${FUNCNAME[@]}"; do
		i=$((i + 1))
		[[ $ignore =~ (^|[[:space:]])$funcname($|[[:space:]]) ]] && continue # TODO: use is_contain
		lineno="${BASH_LINENO[$((i - 2))]}"
		caller="$funcname"
		break
	done

	local timestamp
	# timestamp="$(date "+%Y-%m-%d %H:%M:%S")"
	printf -v timestamp '%(%Y-%m-%d %H:%M:%S)T' -1
	if [[ $SHOW_LOG == "true" ]]; then
		printf "[%s] [%b%s%b] [%s:%s] %b\n" "$timestamp" "${LC["${level}"]}" "${level^^}" "${C["0"]}" "$caller" "$lineno" "$msg" >&2
	fi
}
_debug() { _log "debug" "$1"; }
_info() { _log "info" "$1"; }
_warn() { _log "warn" "$1"; }
_error() {
	_log "error" "$1"
	exit 1
}
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

info() { printf "%b%s%b\n" "${C[G]}" "$1" "${C[0]}" >&2; }
warn() { printf "%b%s%b\n" "${C[Y]}" "$1" "${C[0]}" >&2; }
error() {
	printf "%b%s%b\n" "${C[R]}" "$1" "${C[0]}" >&2
	exit 1
}

draw_box() {
	local txt="$1"
	local width="$2"

	local s="#"
	local inner=$((width - 2))
	local txt_len=${#txt}

	local space=$((inner - txt_len))
	((space < 0)) && return 1
	local left=$((space / 2))
	local right=$((space - left))

	printf '%*s\n' "$width" | tr ' ' $s

	printf "$s"
	printf '%*s' "$left"
	printf "%s" "$txt"
	printf '%*s' "$right"
	printf "$s\n"

	printf '%*s\n' "$width" | tr ' ' $s
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

	apt-get install -y --no-install-recommends "$pkg_name"
}

remove_package() {
	local pkg_name="$1"

	apt-get remove -y "$pkg_name"
	apt-get purge -y "$pkg_name"
	apt-get autoremove -y
	apt-get clean
}

get_tmp_curl_file() {
	local url="$1"

	local tmp_path
	tmp_path="${TMP_DIR}/$(get_safe_random_str 16)"

	curl -fsSL "$url" -o "$tmp_path"
	printf "%s" "$tmp_path"
}

install_zsh_plugins() {
	local zsh_plugins_dir="$1"

	if [[ -e "$zsh_plugins_dir" ]]; then
		_debug "ZSH plugins are already installed."
		return 0
	fi

	mkdir -p "$zsh_plugins_dir"

	local repo
	for repo in "${ZSH_PLUGIN_REPOS[@]}"; do
		_info "Install ZSH plugin ($repo)"
		local dirname="${repo#*/}"
		local clone_url="https://github.com/$repo.git"
		git clone "$clone_url" "$zsh_plugins_dir/$dirname"
	done
}

install_nvim() {
	if [[ -e "/opt/nvim-linux-x86_64" ]]; then
		_debug "Neovim is already installed."
		return 0
	fi

	local tgz_path
	tgz_path=$(get_tmp_curl_file "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-x86_64.tar.gz")

	tar -C "/opt" -xzf "$tgz_path"
	rm -rf "$tgz_path"
	ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
}

install_zoxide() {
	local bin_dir="$1"
	local man1_dir="$2"

	if [[ -e "$bin_dir/zoxide" ]]; then
		_debug "zoxide is already installed."
		return 0
	fi

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

	if [[ -e "$bin_dir/starship" ]]; then
		_debug "Starship is already installed."
		return 0
	fi

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

	chown -R "$username:$username" "$home"
	chmod -R 700 "$home"
}

add_user() {
	local username="$1"
	local password="$2"

	useradd -s "/bin/zsh" -G "sudo" "$username"
	printf "%s:%s" "$username" "$password" | chpasswd
	printf "%s ALL=(ALL) NOPASSWD: ALL\n" "$username" >>"/etc/sudoers.d/$username"
	build_home "$username"
}

get_items() {
	local dir_path="$1"
	local -n result_arr="$2"

	# shellcheck disable=SC2034
	mapfile -d $'\0' result_arr < \
		<(find "$dir_path" -mindepth 1 -maxdepth 1 ! -type l -printf "%y%f\0" | sort -z)
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
		<(printf "%s\0" "${left_arr[@]}") \
		<(printf "%s\0" "${right_arr[@]}"))
}

is_git_clean() {
	local repo_path="$1"
	local repo_dir="${2:-$repo_path}"

	if [[ -n "$(git -C "$repo_path" status --porcelain "$repo_dir")" ]]; then
		return 0
	else
		return 1
	fi
}

declare -A OWN=(
	[L]=1
	[R]=2
	[U]=3  # Union
	[RR]=4 # Right's prefixed
)

append_track() {
	local track_path="$1"
	local item_type="$2"
	local own="$3"
	local base_path="$4"
	local sum="${5:-}"

	if [[ "$item_type" == "f" ]]; then
		printf "%s%s%s\0%s\0" "$item_type" "${OWN[$own]}" "$base_path" "$sum" >>"$track_path"
	elif [[ "$item_type" == "d" ]]; then
		printf "%s%s%s\0" "$item_type" "${OWN[$own]}" "$base_path" >>"$track_path"
	fi
}

get_prefix() {
	local profile_name="$1"
	printf "%s#" "$profile_name"
}

read_by_null() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -d $'\0' _ref
}

read_byte() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -n 1 _ref
}

get_sum() {
	printf "%s" "$(sha256sum "$1" | cut -d ' ' -f1)"
}

printf_splash() {
	local msg="$1"
	local color_ascii="$2"
	printf "%b%s%b\n" "$color_ascii" "$msg" "${C[0]}" >&2
}

declare -Ar STATE=(
	[_]=0
	[M]=1 # Modified
	[A]=2 # Added
	[D]=3 # Deleted
)

declare -Ar STATE_CLR=(
	[${STATE[_]}]=""
	[${STATE[M]}]="${C[Y]}"
	[${STATE[A]}]="${C[G]}"
	[${STATE[D]}]="${C[R]}"
)

# shellcheck disable=SC2329
patch_mix() {
	local L_dir="${1:-}"
	local R_dir="${2:-}"
	local MIX_dir="$3"

	[[ -z "${MIX_dir_len+x}" ]] && local MIX_dir_len="${#MIX_dir}"

	local all_R_items=() all_L_items=()
	[[ -z "$R_dir" ]] || get_items "$R_dir" "all_R_items"
	[[ -z "$L_dir" ]] || get_items "$L_dir" "all_L_items"

	# shellcheck disable=SC2034
	local U_items=() R_items=() L_items=()
	if [[ -n "$R_dir" && -n "$L_dir" ]]; then
		get_mixed_items "all_R_items" "all_L_items" "union" "U_items"
		get_mixed_items "all_R_items" "all_L_items" "left_only" "R_items"
		get_mixed_items "all_R_items" "all_L_items" "right_only" "L_items"
	elif [[ -n "$R_dir" ]]; then
		# shellcheck disable=SC2034
		local R_items=("${all_R_items[@]}")
	elif [[ -n "$L_dir" ]]; then
		# shellcheck disable=SC2034
		local L_items=("${all_L_items[@]}")
	fi

	local own RR_items=()
	for own in "R" "U" "L"; do
		local -n items="${own}_items"

		local as_var
		if [[ "$own" == "U" ]]; then
			as_var="as_R_item"
		else
			as_var="as_${own}_item"
		fi

		local item
		for item in "${items[@]}"; do
			[[ -z "$item" ]] && continue

			local type="${item:0:1}"
			local base="${item:1}"

			local as_R_item="${R_dir}/${base}"
			local as_L_item="${L_dir}/${base}"
			local LR_path="${!as_var}"

			local sum=""
			if [[ "$type" == "f" ]]; then
				sum="$(get_sum "$LR_path")"
			fi

			local mix_path="${MIX_dir}/${base}"
			local write_path="${mix_path:$MIX_dir_len+1}"
			local write_own="$own"

			# if "L" has "RR" item
			if [[ "$own" == "L" ]] && is_contain "$base" "RR_items"; then
				continue
			fi

			if [[ "$own" == "R" && "$base" == "$_PREFIX"* ]]; then
				local restored_base="${base#"${_PREFIX}"}"
				mix_path="${MIX_dir}/${restored_base}"
				RR_items+=("$restored_base")
				write_path="${mix_path:$MIX_dir_len+1}"
				write_own="RR"
			fi

			append_track "$_TRACK" "$type" "$write_own" "$write_path" "$sum"

			if [[ "$type" == "d" ]]; then
				install_cmd -m 0700 -o "$_OWNER" -g "$_OWNER" "$mix_path" -d
				if [[ "$own" == "U" ]]; then
					patch_mix "$as_L_item" "$as_R_item" "$mix_path"
				elif [[ "$own" == "R" ]]; then
					patch_mix "" "$as_R_item" "$mix_path"
				elif [[ "$own" == "L" ]]; then
					patch_mix "$as_L_item" "" "$mix_path"
				fi
			elif [[ "$type" == "f" ]]; then
				install_cmd -m 0700 -o "$_OWNER" -g "$_OWNER" "$LR_path" "$mix_path"
			fi
		done
	done
}

##################################################
#                    Commands                    #
##################################################
install_etc() {
	local ssh_port="$1"

	# TODO: Set permission correctly
	_debug "using default etc (not implemented yet)"

	local tmpl_etc_dir="$REPO_PROFILES_DIR/default/etc"

	# /etc/ssh
	[[ -e /etc/ssh ]] && rm -rf /etc/ssh
	cp -r "$tmpl_etc_dir/ssh" /etc/ssh
	sed -i "s/^Port [0-9]\+/Port $ssh_port/" /etc/ssh/sshd_config
	_debug "Generating SSH host keys..."
	ssh-keygen -A >/dev/null

	# /etc/iptables
	[[ -e /etc/iptables ]] && rm -rf /etc/iptables
	cp -r "$tmpl_etc_dir/iptables" /etc/iptables

	# /etc/systemd/system/iptables-restore.service
	install_cmd -m 0644 -o root -g root "$tmpl_etc_dir/systemd/system/iptables-restore.service" "/etc/systemd/system/iptables-restore.service"
	sed -i "s|^-A INPUT -p tcp --dport [0-9]\+ -j ACCEPT$|-A INPUT -p tcp --dport $ssh_port -j ACCEPT|" "/etc/iptables/rules.v4"

	if [[ "$DOCKER_IS_DOCKER" == "false" ]]; then
		# Reload sshd config
		_info "Restart sshd service"
		systemctl restart sshd
		# Enable iptables-restore.service
		_info "Reload systemctl daemon"
		systemctl daemon-reload
		_info "Enable iptables-restore service"
		systemctl enable iptables-restore.service
	fi
}

get_home() {
	local username="$1"
	if [[ "$username" == "root" ]]; then
		printf "/root"
	else
		printf "/home/%s" "$username"
	fi
}

update_conf_user_env() {
	local new_username="$1"

	local -n username=_USERNAME
	local -n user_id=_USER_ID
	local -n home=_HOME
	local -n user_data_dir=_USER_DATA_DIR
	local -n track_file=_TRACK_FILE
	username="$new_username"
	user_id="$(id -u "$username")"
	home="$(get_home "$username")"
	user_data_dir="$REPO_USER_DIR/$username"
	track_file="$user_data_dir/$TRACK_FILENAME"
}

cmd_init() {
	local username="${1:-}"
	local profile="${2:-$DEFAULT_PROFILE_NAME}"

	if [[ -e "$REPO_INSTALL_DIR" ]]; then
		warn "conf is already installed." "Use 'adduser' command to create new conf user."
		exit 1
	fi

	##################################
	#    Install conf Repository     #
	##################################
	if [[ $IS_DEBUG == "true" ]]; then
		ln -sf "$DOCKER_APP_DIR" "$REPO_INSTALL_DIR"               # Repository (Docker Copied Repository)
		ln -sf "$DOCKER_DEV_APP_DIR/conf.sh" "/usr/local/bin/conf" # conf bin (Docker Volume Repository)
	else
		git clone -b main "$REPO_URL" "$REPO_INSTALL_DIR"        # Repository (Git)
		ln -sf "$REPO_INSTALL_DIR/conf.sh" "/usr/local/bin/conf" # conf bin (Git)
		chmod +x "$REPO_INSTALL_DIR/conf.sh"
	fi

	[[ ! -e "$REPO_USER_DIR" ]] && mkdir -p "$REPO_USER_DIR"
	git_conf config --global user.email "mona_lisa@example.com"
	git_conf config --global user.name "Mona Lisa"

	##################################
	#      Install APT Packages      #
	##################################
	! is_cmd_exist git && install_package git
	is_cmd_exist ufw && remove_package ufw # uninstall iptables's wrapper

	_debug "use default package list file (not implemented yet)"
	local packages
	packages="$(get_profile_dir "$DEFAULT_PROFILE_NAME")/$PACKAGE_LIST_FILENAME"

	local my_package
	while read -r my_package; do
		if ! is_cmd_exist "$my_package"; then
			install_package "$my_package"
		fi
	done <"$packages"

	##################################
	# Install binaries & ZSH plugins #
	##################################
	install_zsh_plugins "$ZSH_PLUGINS_DIR"
	install_nvim
	install_starship "$LOCAL_DIR/bin"

	local man1_dir="$LOCAL_DIR/share/man/man1"
	[[ ! -e "$man1_dir" ]] && mkdir -p "$man1_dir"
	install_zoxide "$LOCAL_DIR/bin" "$man1_dir"

	if [[ "$DOCKER_IS_DOCKER" == "false" ]]; then
		_info "Executing Docker installation script.."
		sh -c "$(curl -fsSL https://get.docker.com)"
	fi

	##################################
	#       Install etc (WIP)        #
	##################################
	local ssh_port="$((1024 + RANDOM % (65535 - 1024 + 1)))"
	printf "%s" "$ssh_port" >>"$SSH_PORT_FILE"
	install_etc "$ssh_port"

	# After Install
	if [[ $_INTERNAL == "false" ]]; then
		printf "%b%s%b\n" "${C[G]}" "conf has installed." "${C[0]}"
	fi

	if [[ -n "$username" ]]; then
		_INTERNAL="true" cmd_adduser "$username" "$profile"
	fi
}

cmd_adduser() {
	local username="${1:-}"
	local profile="${2:-$DEFAULT_PROFILE_NAME}"

	if [[ -z "$username" ]]; then
		warn "Please specify the username."
		return 1
	fi

	##################################
	#       Reset Target User        #
	##################################
	if [[ "$username" != "root" ]] && is_usr_exist "$username"; then
		_info "$username is already exist. Backup and deleting..."
		local home="/home/$username"
		if [[ -e "$home" ]]; then
			mv "$home" "$home.old_$(get_safe_random_str 16)"
		fi

		deluser "$username"
	fi

	local passwd
	passwd="$(get_random_str $PASSWD_LENGTH)"
	add_user "$username" "$passwd"

	##### Create User (Use Env) #####
	update_conf_user_env "$username"
	mkdir "$_USER_DATA_DIR"

	if [[ "$DOCKER_IS_DOCKER" == "false" ]]; then
		usermod -aG docker "$_USERNAME"
	fi

	local secret_file="$_HOME/$SECRET_FILENAME"
	install_cmd -m 0400 -o "$_USERNAME" -g "$_USERNAME" /dev/null "$secret_file"
	printf "Password: %s\n\n" "$passwd" >>"$secret_file"

	# Set up SSH
	local ssh_dir="$_HOME/.ssh"

	local ssh_publickey
	if [[ "$IS_DEBUG" == "true" ]]; then
		ssh_publickey="some_ssh_publickey"
	else
		read -r -p "Paste SSH public key: " ssh_publickey </dev/tty
	fi
	printf "%s" "$ssh_publickey" >>"$ssh_dir/authorized_keys"

	local ssh_port
	ssh_port=$(<"$SSH_PORT_FILE")

	### Create template example
	{
		printf "# Client's SSH template\n"
		printf "Host yourhost\n"
		printf "  HostName %s\n" "$(curl -fsSL https://api.ipify.org)"
		printf "  Port %s\n" "$ssh_port"
		printf "  User %s\n" "$_USERNAME"
		printf "  IdentityFile ~/.ssh/%s\n" "yourhost"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"$secret_file"

	### This Host -> Git
	local ssh_git_passphrase
	ssh_git_passphrase="$(get_random_str $PASSWD_LENGTH)"
	local git_filename="id_git"
	ssh-keygen -t ed25519 -b 4096 -f "$ssh_dir/$git_filename" -N "$ssh_git_passphrase" -C "" >/dev/null 2>&1
	{
		printf "# SSH passphrase for Git\n%s\n\n" "$ssh_git_passphrase"
		printf "# SSH public key for Git\n"
		cat "$ssh_dir/${git_filename}.pub"
		printf "\n"
	} >>"$secret_file"

	{
		printf "Host git\n"
		printf "  HostName github.com\n"
		printf "  User git\n"
		printf "  IdentityFile ~/.ssh/%s\n" "$git_filename"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"$ssh_dir/config"

	rm -f "$ssh_dir/${git_filename}.pub"

	chown "$_USERNAME:$_USERNAME" "$ssh_dir/"*
	chmod 0600 "$ssh_dir/"*

	if ! $_INTERNAL; then
		info "Added '$_USERNAME' successfully."
	fi

	_INTERNAL="true" cmd_apply "$profile"
}

cmd_apply() {
	local profile="${1:-$DEFAULT_PROFILE_NAME}"

	local profile_dir
	if [[ -z "$profile" || "$profile" == "$DEFAULT_PROFILE_NAME" ]]; then
		profile_dir=""
	else
		profile_dir="$(get_home_profile_dir "$profile")"
		if [[ ! -e "$profile_dir" ]]; then
			error "'$profile' profile doesn't exist."
		fi
	fi

	_TRACK_FILE="$_USER_DATA_DIR/$TRACK_FILENAME" _PROFILE="$profile" _USER="$_USERNAME" _GIT_COMMIT_ID="$(get_git_commit_id)" \
		patch_mix "$_HOME" "$profile_dir" "$(get_home_profile_dir "$DEFAULT_PROFILE_NAME")"

	if ! $_INTERNAL; then
		printf "%bApplied '%s' profile.%b\n" "${C[G]}" "$profile" "${C[0]}"
	fi
}

git_conf() {
	git -C "$REPO_INSTALL_DIR" "$@"
}

write_track_header() {
	local filepath="$1"
	local user_id="$2"
	local profile="$3"
	local git_commit_id="$4"

	printf "%s\0%s\0%s\0" \
		"$user_id" "$profile" "$git_commit_id" >>"$filepath"
}

cmd_update() {
	# git_conf clean -fdx "$REPO_PROFILES_DIR"
	if [[ ! -e "$_TRACK_FILE" ]]; then
		warn "No track file. Try 'apply' command first."
		exit 1
	fi

	local current_commit_id
	current_commit_id="$(get_git_commit_id)"

	{
		# shellcheck disable=SC2034
		local _ profile track_commit_id
		read_by_null _ # old user id
		read_by_null profile
		read_by_null track_commit_id

		local default_dir profile_dir
		default_dir="$(get_home_profile_dir "$DEFAULT_PROFILE_NAME")"
		profile_dir="$(get_home_profile_dir "$profile")"

		if [[ "$current_commit_id" != "$track_commit_id" ]]; then
			warn "You need to apply latest version of git snapshot."
			exit 1
		fi

		local -a unlink_items
		if ! apply_to_repo \
			"$_HOME" \
			"$profile_dir" \
			"$default_dir" \
			"$profile" \
			"unlink_items"; then

			# No change
			_debug "No change on '$_HOME'"
			return 0
		fi

		local archive_path="$_USER_DATA_DIR/$current_commit_id.tar.gz"
		_debug "Backup current home ($archive_path)"
		tar -C "$_HOME" -czf "$archive_path" "${unlink_items[@]}"

		for unlink_item in "${unlink_items[@]}"; do
			_debug "Unlink: $unlink_item"
			rm -rf "$unlink_item"
		done

	} <"$_TRACK_FILE"

	_debug "Committing..."
	git_conf add "$REPO_PROFILES_DIR" >/dev/null 2>&1
	git_conf commit -m "$_USERNAME updates conf" --no-verify >/dev/null 2>&1

	# Update track data
	rm -f "$_TRACK_FILE"

	_INTERNAL="true" cmd_apply "$profile"
}

main_() {
	_debug "args: $*"
	_vars "BASH_VERSION"

	if [[ (($# -eq 0)) ]] || [[ $SHOW_HELP == "true" ]]; then
		print_help
		return 0
	fi

	if [[ $SHOW_VERSION == "true" ]]; then
		print_version
		return 0
	fi

	if (("${#CMDS[@]}" == 0)); then
		printf "%s\n" "$(get_err_msg "Please specify the conf command." "true")" >&2
		return 1
	fi

	if [[ -n "$LOVE" ]]; then
		printf "i love you %s.\n" "$LOVE"
	fi

	local cmd="${CMDS[0]}"
	local cmd_func="cmd_$cmd"

	if ! declare -F "$cmd_func" >/dev/null 2>&1; then
		printf "%s\n" "$(get_err_msg "'$cmd' is not conf command." "true")" >&2
		exit 1
	fi

	if ! is_root; then
		error "Permission denied (you must be root)"
	else
		update_conf_user_env "${SUDO_USER:-$CURRENT_USER}"
		_INTERNAL="false" "$cmd_func" "${CMDS[@]:1}"
	fi

	_debug "conf command exit with $? code"

	if [[ $IS_DOCKER_ENTRYPOINT == "true" ]]; then
		printf "Keeping docker container running...\n"
		tail -f /dev/null
	fi
}

# if [[ -z "${BASH_SOURCE[0]+x}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
# 	# Execute directly, Pipeline
# 	main_ "$@"
# fi

patch_LR() {
	local L_dir="$1"
	local R_dir="$2"
	local MIX_dir="$3"
	local rr="$4" # prefix

	local -A del_parents=() RR_dirs=()
	local -A adds=() mods=() dels=()

	_is_root_item() { [[ "$1" != *"/"* ]] && return 0 || return 1; }

	while :; do
		# Path's Header
		local type own
		read_byte type || break
		read_byte own

		# Path & Sum (file)
		local path="" old_sum=""
		if [[ "$type" == "f" ]]; then
			read_by_null "path"
			read_by_null "old_sum"
		elif [[ "$type" == "d" ]]; then
			read_by_null "path"
		else
			_error "Unknown file type '$type'. Did you read headers correctly?"
		fi

		local parent="${path%/*}"
		local base="${path##*/}"

		if [[ -v del_parents["$parent"] ]]; then
			if [[ "$type" == "d" ]]; then
				del_parents["$path"]=1
			fi
			continue
		fi

		# Generate L or R path
		local LR_path=""

		if [[ -z "$LR_path" ]]; then
			if [[ "$own" == "${OWN[L]}" ]]; then
				LR_path="$L_dir/$path"

			elif [[ "$own" == "${OWN[R]}" ]]; then
				if [[ -v RR_dirs["$parent"] ]]; then
					RR_dir="${RR_dirs["$parent"]}"
					LR_path="$RR_dir/$base"
					if [[ "$type" == "d" ]]; then
						RR_dirs["$path"]="$LR_path"
					fi
				else
					LR_path="$R_dir/$path"
				fi

			elif [[ "$own" == "${OWN[U]}" ]]; then
				LR_path="$R_dir/$path"

			elif [[ "$own" == "${OWN[RR]}" ]]; then
				if _is_root_item "$path"; then
					LR_path="$R_dir/$rr$path"
				else
					LR_path="$R_dir/$parent/$rr$base)"
				fi

				RR_dirs["$path"]="$LR_path"
			fi
		fi

		local mix_path="$MIX_dir/$path"
		local mix_state=${STATE[_]}

		if [[ "$type" == "f" ]]; then
			if [[ -f "$mix_path" ]]; then
				if [[ "$old_sum" != "$(get_sum "$mix_path")" ]]; then
					mix_state="${STATE[M]}"
				fi
			else
				mix_state="${STATE[D]}"
			fi
		fi

		if [[ "$type" == "d" ]]; then
			if [[ -d "$mix_path" ]]; then
				local item
				while read_by_null item; do
					local y="${item:0:1}" f="${item:1}"
					# shellcheck disable=SC2034
					adds["$y$base/$f"]="$y$LR_path/$f"
				done < <(find "$mix_path" -maxdepth 1 -mindepth 1 ! -type l -printf "%y%f\0")
			else
				mix_state=${STATE[D]}
				del_parents["$path"]=1
			fi
		fi

		case "$mix_state" in
		"${STATE[_]}" | "${STATE[M]}")
			unset "adds[$type$path]"
			if [[ "$mix_state" == "${STATE[M]}" ]]; then
				# shellcheck disable=SC2034
				mods["$type$base"]="$type$LR_path"
			fi
			;;
		"${STATE[D]}")
			# shellcheck disable=SC2034
			dels["$type$base"]="$type$LR_path"
			;;
		esac
	done

	local kind
	for kind in "adds" "dels" "mods"; do
		local -n items="$kind"
		if ((${#items[@]} > 0)); then
			printf "[$kind] %s\n" "${items[@]}"
		fi
	done
}
