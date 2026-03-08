#!/bin/bash
set -e -u -o pipefail -C

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

is_contain() {
	local value="$1"
	local -n arr_ref="$2"

	if [[ " ${arr_ref[*]} " =~ [[:space:]]"$value"[[:space:]] ]]; then
		return 0
	else
		return 1
	fi
}

printfc() {
	local msg="$1"
	local c="$2"
	printf "%b%s%b\n" "$c" "$msg" "${C[0]}"
}

is_git_clean() {
	if [[ -n $(git status --porcelain "$REPO_PROFILES_DIR") ]]; then
		return 0
	else
		return 1
	fi
}

get_sum() {
	printf "%s" "$(sha256sum "$1" | cut -d ' ' -f1)"
}

read_by_null() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -d $'\0' _ref
}

read_byte() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -n 1 _ref
}

get_prefix() {
	printf "%s#" "$1"
}

apply_to_repo() {
	local output_dir="$1"
	local override_dir="$2"
	local default_dir="$3"

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
			# Read Item Header (Or EOF)
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
					# Store prefix directory
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
					state=${STATE[D]} # deleted (or dir)
				fi
			else
				if [[ -d "$home_path" ]]; then
					local item
					while read_by_null item; do
						new_item["$item"]=1
					done < <(find "$home_path" -maxdepth 1 -mindepth 1 ! -type l -printf "%y%p\0")
				else
					state=${STATE[D]} # deleted (or file)
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
				# local usr_input
				if [[ "$own" == "${OWN[union]}" ]]; then
					# printf "($base) this item has alias on default profile.\nDo you want to delete it too?\n"
					rm -rf "${default_dir:?}/$base"
					# read -r usr_input </dev/tty
					# if [[ "$usr_input" == "y" ]]; then
					# 	rm -rf "$default_dir/$base"
					# fi
				fi
				rm -rf "$repo_path"
				;;
			esac

			printfc "($type:$own) $base" "${STATE_CLR[$state]}"
		done

		for new_item in "${!new_item[@]}"; do
			# local new_type="${new_item:0:1}"
			# local new_base="${new_item:1}"
			# cp -r "$new_base" "$default_dir/$new_base"
			printfc "new item: $new_item" "${STATE_CLR[${STATE[A]}]}"
		done

	} <"$_TRACK_FILE"

}

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

get_temp_dir() {
	local random_str
	random_str="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
	printf "/tmp/test-%s" "$random_str"
}

# debug() {
# 	local msg="$1"
# 	printf "%b[TEST] %s%b\n" "\033[1;36m" "$msg" "\033[0m" >&2
# }

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

			if [[ "$type" == "d" ]]; then
				append_track "$_TRACK_FILE" "$type" "$write_own" "$write_path"
				install -m 0700 -o "$_USER" -g "$_USER" "$output_path" -d
				if [[ "$own" == "union" ]]; then
					apply_to_local "$output_path" "$as_override_item" "$as_default_item"
				elif [[ "$own" == "override" ]]; then
					apply_to_local "$output_path" "$as_override_item" ""
				elif [[ "$own" == "default" ]]; then
					apply_to_local "$output_path" "" "$as_default_item"
				fi
			elif [[ "$type" == "f" ]]; then
				append_track "$_TRACK_FILE" "$type" "$write_own" "$write_path" "$sum"
				install -m 0700 -o "$_USER" -g "$_USER" "$repo_path" "$output_path"
			fi
		done
	done
}

############## TEST ##############
TEST_USER="kana"
TEST_PROFILE="uwu"
TEST_PREFIX="$(get_prefix "$TEST_PROFILE")"

# *Has static rule
generate_test_data() {
	local dest_dir="$1"

	mkdir -p "$dest_dir/"{a,b,out}

	local a_dir="$dest_dir/a"
	local b_dir="$dest_dir/b"

	# base directory
	mkdir -p "$a_dir/"{a_dir,u_dir,p_dir}
	printf "a" >>"$a_dir/p_file"
	touch "$a_dir/p_dir/a_file"{1..3}
	touch "$a_dir/a_file"{1..3}
	touch "$a_dir/a_dir/a_file"{1..3}
	touch "$a_dir/u_dir/u_file"{1..3}

	# override directory
	mkdir -p "$b_dir/"{b_dir,u_dir,"$TEST_PREFIX"p_dir}
	printf "b" >>"$b_dir/${TEST_PREFIX}p_file"
	touch "$b_dir/${TEST_PREFIX}p_dir/b_"{1..3}
	touch "$b_dir/b_file"{1..3}
	touch "$b_dir/b_dir/b_file"{1..3}
	touch "$b_dir/u_dir/u_file"{1..6}

}

test_main() {
	# New item should be in tracked item!
	_show_msg() {
		printfc "[Test] $1" "$2" >&2
	}

	# Before test
	useradd -G "sudo" "$TEST_USER"

	# Get temp test dir
	local tmp_dir
	tmp_dir="$(get_temp_dir)"
	mkdir "$tmp_dir"

	# Homes
	local repo_a_dir="$tmp_dir/a"
	local repo_b_dir="$tmp_dir/b"
	local local_dir="$tmp_dir/out"
	generate_test_data "$tmp_dir"

	# Track file
	local user_id
	user_id="$(id -u "$TEST_USER")"
	local track_file="$tmp_dir/$user_id"

	_reset() {
		rm -rf "${tmp_dir:?}/"*
		generate_test_data "$tmp_dir"
	}

	_run_apply_to_local() {
		# Write track headers
		printf "%s\0%s\0" "$TEST_PROFILE" "<git_commit_id>" >>"$track_file"

		_TRACK_FILE="$track_file" _PREFIX="$TEST_PREFIX" _USER="$TEST_USER" \
			apply_to_local "$local_dir" "$repo_b_dir" "$repo_a_dir"
	}

	_run_apply_to_repo() {
		_TRACK_FILE="$track_file" \
			apply_to_repo "$local_dir" "$repo_b_dir" "$repo_a_dir"
	}

	### Delete test
	_run_del_test() {
		local rm_dir="$1"
		local callback="$2"

		_run_apply_to_local

		if [[ ! -e "$rm_dir" ]]; then
			_show_msg "Invalid del dir: $rm_dir" "${C[R]}"
			exit 1
		fi

		rm -rf "$rm_dir"
		_run_apply_to_repo

		if "$callback"; then
			_show_msg "$callback - Success" "${C[G]}"
		else
			_show_msg "$callback - Failed" "${C[R]}"
		fi
		printf "\n"

		_reset
	}

	_del_a_dir() {
		[[ ! -e "$repo_a_dir/a_dir" ]] && return 0 || return 1
	}
	_run_del_test "$local_dir/a_dir" "_del_a_dir"

	_del_u_dir() {
		[[ ! -e "$repo_a_dir/u_dir" && ! -e "$repo_b_dir/u_dir" ]] && return 0 || return 1
	}
	_run_del_test "$local_dir/u_dir" "_del_u_dir"

	### Add test
	_run_add_test() {
		local add_dir="$1" # TODO: support file
		local callback="$2"

		# TODO: Detect not in tracked item (=root item)

		_run_apply_to_local
		mkdir "$add_dir"
		_run_apply_to_repo

		if "$callback"; then
			_show_msg "$callback - Success" "${C[G]}"
		else
			_show_msg "$callback - Failed" "${C[R]}"
		fi
		printf "\n"

		_reset
	}

	_add_kana_dir() {
		[[ -e "$repo_a_dir/a_dir/kana" ]] && return 0 || return 1
	}
	_run_add_test "$local_dir/a_dir/kana" "_add_kana_dir"

	# Clean up temp test dir
	_show_msg "Clean up test dir" "${C[C]}"
	rm -rf "$tmp_dir"
}

test_main
