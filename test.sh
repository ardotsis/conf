#!/bin/bash
set -e -u -o pipefail -C

# declare -Ar C=(
# 	[0]="\033[0m" # Reset
# 	[B]="\033[1m" # Bold

# 	# Normal
# 	[r]="\033[0;31m" # Red
# 	[y]="\033[0;33m" # Orange/Yellow
# 	[g]="\033[0;32m" # Green
# 	[c]="\033[0;36m" # Cyan
# 	[b]="\033[0;34m" # Blue
# 	[p]="\033[0;35m" # Purple
# 	[k]="\033[0;30m" # Black
# 	[w]="\033[0;37m" # White

# 	# Bold
# 	[R]="\033[1;31m"  # Bold Red
# 	[Y]="\033[1;33m"  # Bold Yellow
# 	[G]="\033[1;32m"  # Bold Green
# 	[C]="\033[1;36m"  # Bold Cyan
# 	[B_]="\033[1;34m" # Bold Blue (L for Light/Large)
# 	[P]="\033[1;35m"  # Bold Purple
# 	[K]="\033[1;30m"  # Bold Black
# 	[W]="\033[1;37m"  # Bold White
# )

# declare -A OWN=(
# 	[default]=1
# 	[override]=2
# 	[union]=3
# 	[prefixed]=4
# )

# declare -Ar STATE=(
# 	[_]=0
# 	[M]=1 # Modified
# 	[A]=2 # Added
# 	[D]=3 # Deleted
# )

# declare -Ar STATE_CLR=(
# 	[${STATE[_]}]=""
# 	[${STATE[M]}]="${C[Y]}"
# 	[${STATE[A]}]="${C[G]}"
# 	[${STATE[D]}]="${C[R]}"
# )

# is_contain() {
# 	local value="$1"
# 	local -n arr_ref="$2"

# 	if [[ " ${arr_ref[*]} " =~ [[:space:]]"$value"[[:space:]] ]]; then
# 		return 0
# 	else
# 		return 1
# 	fi
# }

# printfc() {
# 	local msg="$1"
# 	local c="$2"
# 	printf "%b%s%b\n" "$c" "$msg" "${C[0]}"
# }

# is_git_clean() {
# 	if [[ -n $(git status --porcelain "$REPO_PROFILES_DIR") ]]; then
# 		return 0
# 	else
# 		return 1
# 	fi
# }

# get_sum() {
# 	printf "%s" "$(sha256sum "$1" | cut -d ' ' -f1)"
# }

# read_by_null() {
# 	local -n _ref="${1:-REPLY}"
# 	IFS="" read -r -d $'\0' _ref
# }

# read_byte() {
# 	local -n _ref="${1:-REPLY}"
# 	IFS="" read -r -n 1 _ref
# }

# get_items() {
# 	local dir_path="$1"
# 	local -n result_arr="$2"

# 	# shellcheck disable=SC2034
# 	mapfile -d $'\0' result_arr < \
# 		<(find "$dir_path" -mindepth 1 -maxdepth 1 ! -type l -printf "%y%f\0" | sort -z)
# }

# get_mixed_items() {
# 	# todo: arr1 arr2
# 	local -n left_arr="$1"
# 	local -n right_arr="$2"
# 	local mode="$3"
# 	# shellcheck disable=SC2178
# 	local -n result_arr="$4"

# 	case "$mode" in
# 	union) comm_num="-12" ;;
# 	left_only) comm_num="-23" ;;
# 	right_only) comm_num="-13" ;;
# 	*) return 1 ;;
# 	esac

# 	# shellcheck disable=SC2034
# 	mapfile -d $'\0' result_arr < <(comm "$comm_num" -z \
# 		<(printf "%s\0" "${left_arr[@]}") \
# 		<(printf "%s\0" "${right_arr[@]}"))
# }

# _append_track() {
# 	local track_path="$1"
# 	local item_type="$2"
# 	local own="$3"
# 	local base_path="$4"
# 	local sum="${5:-}"

# 	if [[ "$item_type" == "f" ]]; then
# 		printf "%s%s%s\0%s\0" "$item_type" "${OWN[$own]}" "$base_path" "$sum" >>"$track_path"
# 	elif [[ "$item_type" == "d" ]]; then
# 		printf "%s%s%s\0" "$item_type" "${OWN[$own]}" "$base_path" >>"$track_path"
# 	fi
# }

# link() {
# 	local output_dir="$1"
# 	local override_dir="${2:-}" # Preferrer
# 	local default_dir="${3:-}"

# 	if [[ -z "${output_dir_len+x}" ]]; then
# 		local output_dir_len="${#output_dir}"
# 	fi

# 	local all_override_items=() all_default_items=()
# 	# TODO: include item type (find command)
# 	[[ -z "$override_dir" ]] || get_items "$override_dir" "all_override_items"
# 	[[ -z "$default_dir" ]] || get_items "$default_dir" "all_default_items"

# 	# shellcheck disable=SC2034
# 	local union_items=() override_items=() default_items=()
# 	if [[ -n "$override_dir" && -n "$default_dir" ]]; then
# 		get_mixed_items "all_override_items" "all_default_items" "union" "union_items"
# 		get_mixed_items "all_override_items" "all_default_items" "left_only" "override_items"
# 		get_mixed_items "all_override_items" "all_default_items" "right_only" "default_items"
# 	elif [[ -n "$override_dir" ]]; then
# 		# shellcheck disable=SC2034
# 		local override_items=("${all_override_items[@]}")
# 	elif [[ -n "$default_dir" ]]; then
# 		# shellcheck disable=SC2034
# 		local default_items=("${all_default_items[@]}")
# 	fi

# 	local own prefixed_items=()
# 	for own in "override" "union" "default"; do
# 		local -n items="${own}_items"

# 		local as_var
# 		if [[ "$own" == "union" ]]; then
# 			as_var="as_override_item" # choose override path
# 		else
# 			as_var="as_${own}_item"
# 		fi

# 		local item
# 		for item in "${items[@]}"; do
# 			[[ -z "$item" ]] && continue

# 			local type="${item:0:1}"
# 			local base="${item:1}"

# 			local as_override_item="${override_dir}/${base}"
# 			local as_default_item="${default_dir}/${base}"
# 			local repo_path="${!as_var}"

# 			local sum=""
# 			if [[ "$type" == "f" ]]; then
# 				sum="$(sha256sum "$repo_path" | cut -d ' ' -f1)"
# 			fi

# 			local output_path="${output_dir}/${base}"
# 			local write_path="${output_path:$output_dir_len+1}"
# 			local write_own="$own"

# 			# Skip prefixed override path (for default)
# 			if [[ "$own" == "default" ]] && is_contain "$base" "prefixed_items"; then
# 				continue
# 			fi

# 			# Fix: <Prefixed Path> -> <Output Path>
# 			if [[ "$own" == "override" && "$base" == "$PROFILE_PREFIX"* ]]; then
# 				local origin_base="${base#"${PROFILE_PREFIX}"}"
# 				output_path="${output_dir}/${origin_base}"
# 				prefixed_items+=("$origin_base")
# 				write_path="${output_path:$output_dir_len+1}"
# 				write_own="prefixed"
# 			fi

# 			if [[ "$type" == "d" ]]; then
# 				_append_track "$TRACK" "$type" "$write_own" "$write_path"
# 				install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "$output_path" -d
# 				if [[ "$own" == "union" ]]; then
# 					link "$output_path" "$as_override_item" "$as_default_item"
# 				elif [[ "$own" == "override" ]]; then
# 					link "$output_path" "$as_override_item" ""
# 				elif [[ "$own" == "default" ]]; then
# 					link "$output_path" "" "$as_default_item"
# 				fi
# 			elif [[ "$type" == "f" ]]; then
# 				_append_track "$TRACK" "$type" "$write_own" "$write_path" "$sum"
# 				install -m 0700 -o "$INSTALL_USER" -g "$INSTALL_USER" "$repo_path" "$output_path"
# 			fi
# 		done
# 	done
# }

# apply_local_change() {
# 	local output_dir="$1"
# 	local default_dir="$2"
# 	local override_dir="$3"
# 	local track_file="$4"

# 	_show_err() {
# 		printf "apply_local_change err: %s\n" "$1" >&2
# 		exit 1
# 	}

# 	# File: <type><own><base>\0<sum>\0
# 	# Dir : <type><own><base>\0
# 	{
# 		local user_id profile commit_id prefix
# 		read_by_null "user_id"
# 		read_by_null "profile"
# 		read_by_null "commit_id"
# 		prefix="$profile#"

# 		local -A new_item=() del_dir=()
# 		local prefix_dir="" prefix_base=""
# 		while :; do

# 			# Read Item Header (Or EOF)
# 			local type own
# 			read_byte type || break
# 			read_byte own

# 			# Read Item Contents
# 			local base sum
# 			if [[ "$type" == "f" ]]; then
# 				read_by_null "base"
# 				read_by_null "sum"
# 			elif [[ "$type" == "d" ]]; then
# 				read_by_null "base"
# 			else
# 				_show_err "unknown file type: '$type'"
# 			fi

# 			local in_dir="${base%/*}"
# 			if [[ -v del_dir["$in_dir"] ]]; then
# 				if [[ "$type" == "d" ]]; then
# 					del_dir["$base"]=1
# 				fi
# 				# printfc "($type:$own) ├─ $base" "${STATE_CLR[$state]}"
# 				continue
# 			fi

# 			# Resolve Repository Path
# 			local repo_path has_repo_path=false
# 			if [[ -n "$prefix_dir" ]]; then
# 				if [[ "$base" == "$prefix_base/"* ]]; then
# 					has_repo_path=true
# 					repo_path=$prefix_dir/${base##*/}
# 				else
# 					prefix_base=""
# 					prefix_dir=""
# 				fi
# 			fi

# 			if ! $has_repo_path; then
# 				if [[ "$own" == "${OWN[prefixed]}" ]]; then
# 					if [[ "$base" == *"/"* ]]; then
# 						repo_path="$override_dir/${base%/*}/$prefix${base##*/}"
# 					else
# 						repo_path="$override_dir/$prefix$base"
# 					fi
# 					# Store prefix directory
# 					if [[ "$type" == "d" ]]; then
# 						prefix_base="$base"
# 						prefix_dir="$repo_path"
# 					fi
# 				elif [[ "$own" == "${OWN[override]}" || "$own" == "${OWN[union]}" ]]; then
# 					repo_path="$override_dir/$base"
# 				elif [[ "$own" == "${OWN[default]}" ]]; then
# 					repo_path="$default_dir/$base"
# 				else
# 					_show_err "unknown own type '$own'"
# 				fi
# 			fi

# 			local home_path="$output_dir/$base" state=${STATE[_]}
# 			if [[ "$type" == "f" ]]; then
# 				if [[ -f "$home_path" ]]; then
# 					if [[ "$sum" != "$(get_sum "$home_path")" ]]; then
# 						state=${STATE[M]}
# 					fi
# 				else
# 					state=${STATE[D]} # deleted (or dir)
# 				fi
# 			else
# 				if [[ -d "$home_path" ]]; then
# 					local item
# 					while read_by_null item; do
# 						new_item["$item"]=1
# 					done < <(find "$home_path" -maxdepth 1 -mindepth 1 ! -type l -printf "%y%p\0")
# 				else
# 					state=${STATE[D]} # deleted (or file)
# 					del_dir["$base"]=1
# 				fi
# 			fi

# 			case "$state" in
# 			"${STATE[_]}" | "${STATE[M]}")
# 				unset "new_item[$type$home_path]"
# 				if [[ "$state" == "${STATE[M]}" ]]; then
# 					rm -f "$repo_path"
# 					install -o root -g root -m 700 "$home_path" "$repo_path"
# 				fi
# 				;;
# 			"${STATE[D]}")
# 				# local usr_input
# 				if [[ "$own" == "${OWN[union]}" ]]; then
# 					# printf "($base) this item has alias on default profile.\nDo you want to delete it too?\n"
# 					rm -rf "$default_dir/$base"
# 					# read -r usr_input </dev/tty
# 					# if [[ "$usr_input" == "y" ]]; then
# 					# 	rm -rf "$default_dir/$base"
# 					# fi
# 				fi
# 				rm -rf "$repo_path"
# 				;;
# 			esac

# 			# printfc "($type:$own) $base" "${STATE_CLR[$state]}"
# 		done

# 		for new_item in "${!new_item[@]}"; do
# 			local n_path=""
# 			local n_type=""
# 			# printfc "new item: $new_item" "${STATE_CLR[${STATE[A]}]}"
# 		done

# 	} <"$track_file"

# }

# # Env
# USER="kana"
# PROFILE="uwu"
# REPO_INSTALL_DIR="/app"
# REPO_DATA_DIR="$REPO_INSTALL_DIR/data"
# REPO_PROFILES_DIR="$REPO_DATA_DIR/profiles"
# TRACK_FILE="/tmp/tracks_$USER"
# HOME_DIR="/home/$USER"
# DEFAULT_DIR="$REPO_PROFILES_DIR/default/home/default"
# OVERRIDE_DIR="$REPO_PROFILES_DIR/$PROFILE/home/$PROFILE"
# PREFIX="$PROFILE#"

# useradd -s "/bin/zsh" -G "sudo" "$USER"
# printf "%s\0%s\0%s\0" "$(id -u "$USER")" "$PROFILE" "<git_commit_id>" >>"$TRACK_FILE"
# TRACK="$TRACK_FILE" PROFILE_PREFIX="$PREFIX" INSTALL_USER="$USER" \
# 	link "$HOME_DIR" "$OVERRIDE_DIR" "$DEFAULT_DIR"

# run_test() {
# 	_show_msg() {
# 		printfc "[Test:$1] $2" "$3" >&2
# 	}

# 	local f
# 	for f in $(declare -F | cut -d ' ' -f3 | grep "^test_" | grep -v "_after$"); do
# 		if ! $f; then
# 			_show_msg "$f" "Prepare failed" "${C[R]}"
# 			return 1
# 		fi

# 		apply_local_change "$HOME_DIR" "$DEFAULT_DIR" "$OVERRIDE_DIR" "$TRACK_FILE"

# 		if "${f}_after"; then
# 			_show_msg "$f" "Success" "${C[G]}"
# 		else
# 			_show_msg "$f" "Failed" "${C[R]}"
# 		fi
# 	done
# }

# TEST_DUMMY_DIR="_dummy"
# TEST_DEFAULT_DIR="$TEST_DUMMY_DIR/defaultDir"
# TEST_DEFAULT_FILE="$TEST_DUMMY_DIR/defaultFile"

# # shellcheck disable=SC2329
# test_del_default_dir() {
# 	[[ ! -d "$HOME_DIR/$TEST_DEFAULT_DIR" ]] && return 1
# 	rm -rf "$HOME_DIR/$TEST_DEFAULT_DIR"
# }
# # shellcheck disable=SC2329
# test_del_default_dir_after() {
# 	[[ ! -d "$DEFAULT_DIR/$TEST_DEFAULT_DIR" ]] && return 0
# 	return 1
# }

# # shellcheck disable=SC2329
# test_del_default_file() {
# 	[[ ! -f "$HOME_DIR/$TEST_DEFAULT_FILE" ]] && return 1
# 	rm -f "$HOME_DIR/$TEST_DEFAULT_FILE"
# }
# # shellcheck disable=SC2329
# test_del_default_file_after() {
# 	[[ ! -f "$DEFAULT_DIR/$TEST_DEFAULT_FILE" ]] && return 0
# 	return 1
# }

# run_test

# # tail -f /dev/null

PROFILE="uwu"

create_test_env() {
	local output_dir="$1"

	mkdir -p "$output_dir/"{default,override,home}

	# Default directory
	mkdir -p "$output_dir/default/"{defaultDir,union,my_folder}
	printf "DEFAULT" >>"$output_dir/default/my_file"
	touch "$output_dir/default/my_folder/defaultFile_"{1..3}.txt
	touch "$output_dir/default/defaultFile_"{1..3}.txt
	touch "$output_dir/default/defaultDir/defaultFile_"{1..3}.ini
	touch "$output_dir/default/union/union_"{1..3}.sh

	# Override directory
	mkdir -p "$output_dir/override/"{overrideDir,union,$PROFILE#my_folder}
	printf "OVERRIDE" >>"$output_dir/override/my_file"
	touch "$output_dir/override/$PROFILE#my_folder/overrideFile_"{1..3}.txt # Prefixed directory
	touch "$output_dir/override/overrideFile_"{1..3}.txt
	touch "$output_dir/override/overrideDir/overrideFile_"{1..3}.ini
	touch "$output_dir/override/union/union_"{1..5}.sh
}

get_temp_dir() {
	local random_str
	random_str="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
	printf "/tmp/test-%s" "$random_str"
}

main_() {
	local tmp_dir="$(get_temp_dir)"
	echo "Create test dir: $tmp_dir"
	mkdir "$tmp_dir"
	create_test_env "$tmp_dir"

	tree "$tmp_dir"
}

main_
