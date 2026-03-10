#!/bin/bash
set -e -u -o pipefail -C

# System
declare -r TMP_DIR="/var/tmp"
declare -r DOCKER_VOLUME_DIR="/app"
declare -r PORT_NUM_FILE="/etc/conf_port"
# shellcheck disable=SC2155
declare -r CURRENT_USER="$(whoami)"
# Repository
declare -r REPO_URL="https://github.com/ardotsis/conf.git"
declare -r REPO_INSTALL_DIR="/usr/local/share/conf"
declare -r REPO_DATA_DIR="$REPO_INSTALL_DIR/data"
declare -r REPO_TRACKS_DIR="$REPO_DATA_DIR/tracks"
declare -r REPO_PROFILES_DIR="$REPO_DATA_DIR/profiles"
declare -r REPO_PACKAGES_FILE="$REPO_PROFILES_DIR/packages"
# User
declare -r SECRET_FILENAME="conf_secret"
declare -r PASSWD_LENGTH=72

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

	[--docker]="flag:false"
	[-dk]="docker"

	["--show-log"]="flag:false"
	[-l]="show-log"

	[--love]="value:"
	[-luv]="love"
)

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
	if [[ "$(id -u)" == "0" ]]; then
		return 0
	else
		return 1
	fi
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
	if $with_tip; then
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
	skip_index=false

	for input in "${args[@]}"; do
		if $skip_index; then
			skip_index=false
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
				insert_val=true
			elif [[ "$option_type" == "value" ]]; then
				skip_index=true
				local val_i=$((i + 1))
				if ((val_i > last_i)); then
					err_msg="$(get_err_msg "'$input' require a value." true)"
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
				err_msg="$(get_err_msg "'$input' is not a conf option." true)"
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
	if $SHOW_LOG; then
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

	if $with_quote; then
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

	# if [[ "$OS" == "debian" ]]; then
	apt-get install -y --no-install-recommends "$pkg_name"
	# fi
}

remove_package() {
	local pkg_name="$1"

	# if [[ "$OS" == "debian" ]]; then
	apt-get remove -y "$pkg_name"
	apt-get purge -y "$pkg_name"
	apt-get autoremove -y
	apt-get clean
	# fi
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
	ln -s /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
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

	useradd -s "/bin/zsh" -G "sudo" "$username"
	printf "%s:%s" "$username" "$passwd" | chpasswd
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

declare -A OWN=(
	[default]=1
	[override]=2
	[union]=3
	[prefixed]=4
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

get_sum() {
	printf "%s" "$(sha256sum "$1" | cut -d ' ' -f1)"
}

printfc() {
	local msg="$1"
	local c="$2"
	printf "%b%s%b\n" "$c" "$msg" "${C[0]}"
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

apply_to_local() {
	local output_dir="$1"
	local override_dir="${2:-}" # Preferrer
	local default_dir="${3:-}"

	if [[ -z "${output_dir_len+x}" ]]; then
		local output_dir_len="${#output_dir}"
	fi

	local all_override_items=() all_default_items=()
	# TODO: include item type (find command)
	[[ -z "$override_dir" ]] || get_items "$override_dir" "all_override_items"
	[[ -z "$default_dir" ]] || get_items "$default_dir" "all_default_items"

	# shellcheck disable=SC2034
	local union_items=() override_items=() default_items=()
	if [[ -n "$override_dir" && -n "$default_dir" ]]; then
		get_mixed_items "all_override_items" "all_default_items" "union" "union_items"
		get_mixed_items "all_override_items" "all_default_items" "left_only" "override_items"
		get_mixed_items "all_override_items" "all_default_items" "right_only" "default_items"
	elif [[ -n "$override_dir" ]]; then
		# shellcheck disable=SC2034
		local override_items=("${all_override_items[@]}")
	elif [[ -n "$default_dir" ]]; then
		# shellcheck disable=SC2034
		local default_items=("${all_default_items[@]}")
	fi

	local own prefixed_items=()
	for own in "override" "union" "default"; do
		local -n items="${own}_items"

		local as_var
		if [[ "$own" == "union" ]]; then
			as_var="as_override_item" # choose override path
		else
			as_var="as_${own}_item"
		fi

		local item
		for item in "${items[@]}"; do
			[[ -z "$item" ]] && continue

			local type="${item:0:1}"
			local base="${item:1}"

			local as_override_item="${override_dir}/${base}"
			local as_default_item="${default_dir}/${base}"
			local repo_path="${!as_var}"

			local sum=""
			if [[ "$type" == "f" ]]; then
				sum="$(sha256sum "$repo_path" | cut -d ' ' -f1)"
			fi

			local output_path="${output_dir}/${base}"
			local write_path="${output_path:$output_dir_len+1}"
			local write_own="$own"

			# Skip prefixed override path (for default)
			if [[ "$own" == "default" ]] && is_contain "$base" "prefixed_items"; then
				continue
			fi

			# Fix: <Prefixed Path> -> <Output Path>
			if [[ "$own" == "override" && "$base" == "$_PREFIX"* ]]; then
				local origin_base="${base#"${_PREFIX}"}"
				output_path="${output_dir}/${origin_base}"
				prefixed_items+=("$origin_base")
				write_path="${output_path:$output_dir_len+1}"
				write_own="prefixed"
			fi

			_debug "Create: $output_path"
			append_track "$_TRACK_FILE" "$type" "$write_own" "$write_path" "$sum"
			if [[ "$type" == "d" ]]; then
				install -m 0700 -o "$_USER" -g "$_USER" "$output_path" -d
				if [[ "$own" == "union" ]]; then
					apply_to_local "$output_path" "$as_override_item" "$as_default_item"
				elif [[ "$own" == "override" ]]; then
					apply_to_local "$output_path" "$as_override_item" ""
				elif [[ "$own" == "default" ]]; then
					apply_to_local "$output_path" "" "$as_default_item"
				fi
			elif [[ "$type" == "f" ]]; then
				install -m 0700 -o "$_USER" -g "$_USER" "$repo_path" "$output_path"
			fi
		done
	done
}

apply_to_repo() {
	local output_dir="$1"
	local override_dir="$2"
	local default_dir="$3"

	local output_dir_len="${#output_dir}"

	_show_err() {
		printf "apply_local_repo err: %s\n" "$1" >&2
		exit 1
	}

	{
		local profile commit_id
		read_by_null "profile"
		read_by_null "commit_id"
		local prefix
		prefix="$(get_prefix "$profile")"

		local -A new_item=() del_dir=()
		local prefix_dir="" prefix_base=""
		while :; do
			local type own
			read_byte type || break
			read_byte own

			# Read Item Contents
			local base sum
			if [[ "$type" == "f" ]]; then
				read_by_null "base"
				read_by_null "sum"
			elif [[ "$type" == "d" ]]; then
				read_by_null "base"
			else
				_show_err "unknown file type: '$type'"
			fi

			local in_dir="${base%/*}"
			if [[ -v del_dir["$in_dir"] ]]; then
				if [[ "$type" == "d" ]]; then
					del_dir["$base"]=1
				fi
				printfc "($type:$own) ├─ $base" "${STATE_CLR[$state]}"
				continue
			fi

			# Resolve Repository Path
			local repo_path has_repo_path=false
			if [[ -n "$prefix_dir" ]]; then
				if [[ "$base" == "$prefix_base/"* ]]; then
					has_repo_path=true
					repo_path=$prefix_dir/${base##*/}
				else
					prefix_base=""
					prefix_dir=""
				fi
			fi

			if ! $has_repo_path; then
				if [[ "$own" == "${OWN[prefixed]}" ]]; then
					if [[ "$base" == *"/"* ]]; then
						repo_path="$override_dir/${base%/*}/$prefix${base##*/}"
					else
						repo_path="$override_dir/$prefix$base"
					fi
					if [[ "$type" == "d" ]]; then
						prefix_base="$base"
						prefix_dir="$repo_path"
					fi
				elif [[ "$own" == "${OWN[override]}" || "$own" == "${OWN[union]}" ]]; then
					repo_path="$override_dir/$base"
				elif [[ "$own" == "${OWN[default]}" ]]; then
					repo_path="$default_dir/$base"
				else
					_show_err "unknown own type '$own'"
				fi
			fi

			local home_path="$output_dir/$base" state=${STATE[_]}
			if [[ "$type" == "f" ]]; then
				if [[ -f "$home_path" ]]; then
					if [[ "$sum" != "$(get_sum "$home_path")" ]]; then
						state=${STATE[M]}
					fi
				else
					state=${STATE[D]}
				fi
			else
				if [[ -d "$home_path" ]]; then
					local item
					while read_by_null item; do
						new_item["$item"]=1
					done < <(find "$home_path" -maxdepth 1 -mindepth 1 ! -type l -printf "%y%p\0")
				else
					state=${STATE[D]}
					del_dir["$base"]=1
				fi
			fi

			case "$state" in
			"${STATE[_]}" | "${STATE[M]}")
				unset "new_item[$type$home_path]"
				if [[ "$state" == "${STATE[M]}" ]]; then
					rm -f "$repo_path"
					install -o root -g root -m 700 "$home_path" "$repo_path"
				fi
				;;
			"${STATE[D]}")
				if [[ "$own" == "${OWN[union]}" ]]; then
					rm -rf "${default_dir:?}/$base"
				fi
				rm -rf "$repo_path"
				;;
			esac
			printfc "($type:$own) $base" "${STATE_CLR[$state]}"
		done

		for new_item in "${!new_item[@]}"; do
			local new_base="${new_item:1+$output_dir_len+1}" # TODO: Refactor
			cp -r "${new_item:1}" "$default_dir/$new_base"   # TODO: if 'd' or 'f'
			printfc "Added: $new_base" "${STATE_CLR[${STATE[A]}]}"
		done

	} <"$_TRACK_FILE"

}

##################################################
#                    Commands                    #
##################################################
setup_network() {
	local ssh_port="$1"
	_debug "using default etc (not implemented yet)"

	# TODO: chown, chmod
	local tmpl_etc_dir="$REPO_PROFILES_DIR/default/etc"

	# /etc/ssh
	[[ -e /etc/ssh ]] && rm -rf /etc/ssh
	cp -r "$tmpl_etc_dir/ssh" /etc/ssh
	sed -i "s/^Port [0-9]\+/Port $port_num/" /etc/ssh/sshd_config
	ssh-keygen -A

	# /etc/iptables
	[[ -e /etc/iptables ]] && rm -rf /etc/iptables
	cp -r "$tmpl_etc_dir/iptables" /etc/iptables

	# /etc/systemd/system/iptables-restore.service
	install -m 0644 -o root -g root "$tmpl_etc_dir/systemd/system/iptables-restore.service" "/etc/systemd/system/iptables-restore.service"
	sed -i "s|^-A INPUT -p tcp --dport [0-9]\+ -j ACCEPT$|-A INPUT -p tcp --dport $ssh_port -j ACCEPT|" "/etc/iptables/rules.v4"

	if [[ "$IS_DOCKER" == "false" ]]; then
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

check_is_root() {
	if ! is_root; then
		printf "%b%s%b\n" "${C[R]}" "$(get_err_msg "Root access required for this operation.")" "${C[0]}"
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

	if is_cmd_exist ufw; then
		_info "Uninstall UFW"
		ufw disable
		remove_package "ufw"
	fi

	if ! is_cmd_exist "git"; then
		install_package "git"
	fi

	# Install conf repository
	if $IS_DEBUG; then
		ln -sf "$DOCKER_VOLUME_DIR" "$REPO_INSTALL_DIR"
	else
		git clone -b main "$REPO_URL" "$REPO_INSTALL_DIR"
	fi

	if [[ ! -e "$REPO_TRACKS_DIR" ]]; then
		mkdir "$REPO_TRACKS_DIR"
	fi

	local pkg_name
	while read -r pkg_name; do
		if ! is_cmd_exist "$pkg_name"; then
			install_package "$pkg_name"
		fi
	done <"$REPO_PACKAGES_FILE"

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

	if [[ "$IS_DOCKER" == "false" ]]; then
		_info "Executing Docker installation script.."
		sh -c "$(curl -fsSL https://get.docker.com)"
		usermod -aG docker "$username"
	fi

	local port_num="$((1024 + RANDOM % (65535 - 1024 + 1)))"
	printf "%s" "$port_num" >>"$PORT_NUM_FILE"
	setup_network "$port_num"

	if ! $INTERNAL; then
		printf "%b%s%b\n" "${C[G]}" "conf has installed." "${C[0]}"
	fi

	if [[ -n "$username" ]]; then
		INTERNAL=true cmd_adduser "$username" "$profile"
	fi
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

	local secret_file="$home/$SECRET_FILENAME"

	# Store password into "~/.conf/secret"
	install -m 0400 -o "$username" -g "$username" /dev/null "$secret_file"
	printf "Password: %s\n\n" "$passwd" >>"$home/$SECRET_FILENAME"

	if ! $INTERNAL; then
		printf "%bAdded '%s' successfully.%b\n" "${C[G]}" "$username" "${C[0]}"
	fi

	# Set up SSH
	## Create SSH home correctly
	local ssh_dir="$home/.ssh"
	# install -m 0600 -o "$username" -g "$username" /dev/null "$ssh_dir/authorized_keys"
	# install -m 0600 -o "$username" -g "$username" /dev/null "$ssh_dir/config"

	local ssh_publickey
	if [[ "$IS_DEBUG" == "true" ]]; then
		ssh_publickey="some_ssh_publickey"
	else
		read -r -p "Paste SSH public key: " ssh_publickey </dev/tty
	fi
	printf "%s" "$ssh_publickey" >>"$ssh_dir/authorized_keys"

	local ssh_port
	ssh_port=$(<"$PORT_NUM_FILE")
	### Create template example
	{
		printf "# Client's SSH template\n"
		printf "Host yourhost\n"
		printf "  HostName %s\n" "$(curl -fsSL https://api.ipify.org)"
		printf "  Port %s\n" "$ssh_port"
		printf "  User %s\n" "$username"
		printf "  IdentityFile ~/.ssh/%s\n" "yourhost"
		printf "  IdentitiesOnly yes\n"
		printf "\n"
	} >>"$secret_file"

	### This Host -> Git
	local ssh_git_passphrase
	ssh_git_passphrase="$(get_random_str $PASSWD_LENGTH)"
	local git_filename="git"
	ssh-keygen -t ed25519 -b 4096 -f "$ssh_dir/$git_filename" -N "$ssh_git_passphrase" -C ""
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

	chown "$username:$username" "$ssh_dir/"*
	chmod 0600 "$ssh_dir/"*

	INTERNAL=true cmd_apply "$username" "$profile"
}

cmd_apply() {
	case "$INTERNAL" in
	# Via user
	false)
		local username="$CURRENT_USER"
		local profile="$1"
		;;
	# Via function
	true)
		local username="$1"
		local profile="$2"
		;;
	esac

	_vars "username" "profile"

	local profile_dir=""
	if [[ -n "$profile" ]]; then
		profile_dir="$(get_home_profile_dir "$profile")"
	fi

	local home
	if [[ "$username" == "root" ]]; then
		home="/root"
	else
		home="/home/$username"
	fi

	local track_file
	track_file="$REPO_TRACKS_DIR/$(id -u "$username")"
	install -m 0644 /dev/null "$track_file"
	# track header

	printf "%s\0%s\0%s\0" "$(id -u "$username")" "$profile" "$(git -C "$REPO_INSTALL_DIR" rev-parse HEAD)" >>"$track_file"

	_TRACK_FILE="$track_file" _PREFIX="${profile}#" _USER="$username" \
		apply_to_local "$home" "$profile_dir" "$(get_home_profile_dir "default")"

	if [[ -z "$profile" ]]; then
		profile="default"
	fi

	if ! $INTERNAL; then
		printf "%bApplied '%s' profile.%b\n" "${C[G]}" "$profile" "${C[0]}"
	fi
}

cmd_update() {
	local current_git_commit
	:
}

main_() {
	_vars "BASH_VERSION"

	if [[ (($# -eq 0)) ]] || $SHOW_HELP; then
		print_help
		exit 0
	fi

	if $SHOW_VERSION; then
		print_version
		exit 0
	fi

	if (("${#CMDS[@]}" == 0)); then
		printf "%s\n" "$(get_err_msg "Please specify the conf command." true)" >&2
		exit 1
	fi

	if [[ -n "$LOVE" ]]; then
		printf "i love you %s.\n" "$LOVE"
	fi

	# shellcheck disable=SC2034
	local -ar modes=(
		"install"
		"adduser"
		"apply"
		"pull"
	)

	local mode="${CMDS[0]}"
	if ! is_contain "$mode" "modes"; then
		printf "%s\n" "$(get_err_msg "'$mode' is not conf command." true)" >&2
		exit 1
	fi

	# Run command
	INTERNAL=false "cmd_$mode" "${CMDS[@]:1}"

	if $IS_DOCKER; then
		printf "Keeping docker container running...\n"
		tail -f /dev/null
	fi
}

if [[ -z "${BASH_SOURCE[0]+x}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
	# Execute via pipeline or directly
	main_ "$@"
fi
