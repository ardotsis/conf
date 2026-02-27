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

declare -A OWN=(
	[default]=1
	[override]=2
	[both]=3
	[prefixed]=4
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

get_items() {
	local dir_path="$1"
	local -n arr_ref="$2"

	# shellcheck disable=SC2034
	mapfile -d $'\0' arr_ref < \
		<(find "$dir_path" -mindepth 1 -maxdepth 1 -printf "%f\0")
}

diff() {
	local output_dir="$1"
	local default_dir="$2"
	local override_dir="$3"
	local track_file="$4"

	_show_err() {
		printf "diff err: %s\n" "$1" >&2
		exit 1
	}

	# File: <type><own><base>\0<sum>\0
	# Dir : <type><own><base>\0
	{
		local user_id profile commit_id prefix
		read_by_null "user_id"
		read_by_null "profile"
		read_by_null "commit_id"
		prefix="$profile#"

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
						echo "pb: $base"
						repo_path="$override_dir/${base%/*}/$prefix${base##*/}"
					else
						repo_path="$override_dir/$prefix$base"
					fi
					# Store prefix directory
					if [[ "$type" == "d" ]]; then
						prefix_base="$base"
						prefix_dir="$repo_path"
					fi
				elif [[ "$own" == "${OWN[override]}" || "$own" == "${OWN[both]}" ]]; then
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
				local usr_input
				if [[ "$own" == "${OWN[both]}" ]]; then
					printf "($base) this item has alias on default profile.\nDo you want to delete it too?\n"
					rm -rf "$default_dir/$base"
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
			printfc "$new_item" "${STATE_CLR[${STATE[A]}]}"
		done

		printf "del dir: %s\n" "${!del_dir[@]}"

	} <"$track_file"

}

# Env
USER="kana"
PROFILE="uwu"
REPO_INSTALL_DIR="/usr/local/share/conf"
REPO_DATA_DIR="$REPO_INSTALL_DIR/data"
REPO_PROFILES_DIR="$REPO_DATA_DIR/profiles"
REPO_TRACKS_DIR="$REPO_DATA_DIR/tracks"
HOME_DIR="/home/$USER"

TEST_MODIFY_STR="Hello, This is conf tester!"
DEFAULT_DIR="$REPO_PROFILES_DIR/default/home/default"
OVERRIDE_DIR="$REPO_PROFILES_DIR/$PROFILE/home/$PROFILE"
PREFIX="$PROFILE#"

test_apply_local_change() {
	local desc="$1"
	local item_path="$2"
	local change_state="$3"
	local add_type="${4:-f}"

	local home_item="$HOME_DIR/$item_path"
	local default_item="$DEFAULT_DIR/$item_path"
	local override_item=$OVERRIDE_DIR/$item_path

	printfc "[TEST] $desc ($item_path)" "${C[C]}"

	# Detect own type
	local own
	if [[ -e "$default_item" && -e "$override_item" ]]; then
		own="${OWN[both]}"
	elif [[ -e "$default_item" ]]; then
		own="${OWN[default]}"
	elif [[ -e "$override_item" ]]; then
		own="${OWN[override]}"
	else
		if [[ "$item_path" == *"/"* ]]; then
			override_item="$OVERRIDE_DIR/${item_path%/*}/$PREFIX${item_path##*/}"
		else
			override_item="$OVERRIDE_DIR/$PREFIX$item_path"
		fi
		if [[ -e "$override_item" ]]; then
			own="${OWN[prefixed]}"
		else
			printfc "invalid item path '$item_path'" "${C[R]}" >&2
			return 1
		fi
	fi

	# Create change
	case "$change_state" in
	"${STATE[_]}")
		# Do nothing
		:
		;;
	"${STATE[M]}")
		# Modify file
		printf "%s" "$TEST_MODIFY_STR" >>"$home_item"
		;;
	"${STATE[A]}")
		if [[ "$add_type" == "d" ]]; then
			mkdir -p "$home_path"
		elif [[ "$add_type" == "f" ]]; then
			printf "%s" "$TEST_MODIFY_STR" >>"$home_item"
		fi
		;;
	"${STATE[D]}")
		if [[ -d "$home_item" ]]; then
			rm -rf "$home_item"
		elif [[ -f "$home_item" ]]; then
			rm -f "$home_item"
		fi
		;;
	esac

	# RUN TEST
	# RUN TEST
	# RUN TEST
	# RUN TEST
	diff "$HOME_DIR" "$DEFAULT_DIR" "$OVERRIDE_DIR" "$REPO_TRACKS_DIR/1000"

	case "$own" in
	"${OWN[both]}")
		if [[ ! -e "$default_item" && ! -e "$override_item" ]]; then
			printfc "[TEST] Success!" "${C[G]}"
		else
			printfc "[TEST] Failed" "${C[R]}"
		fi

		;;
	esac
}

item_1="aaaa"
state_1="${STATE[D]}"
test_apply_local_change "Delete prefixed item" "$item_1" "$state_1"

item_2=".config/zsh"
state_1="${STATE[D]}"
test_apply_local_change "Delete both directory" "$item_2" "$state_1"

# TODO: DEFAULT_DIR, OVERRIDE_DIR to Global var (etc REPO...)
# diff "$HOME_DIR" "$DEFAULT_DIR" "$OVERRIDE_DIR" "$REPO_TRACKS_DIR/1000"
