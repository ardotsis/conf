#!/bin/bash
set -e -u -o pipefail -C

declare -r REPO_INSTALL_DIR="/usr/local/share/conf"
declare -r REPO_DATA_DIR="$REPO_INSTALL_DIR/data"
declare -r REPO_TRACKS_DIR="$REPO_DATA_DIR/tracks"
declare -r REPO_PROFILES_DIR="$REPO_DATA_DIR/profiles"
declare -r REPO_PACKAGES_FILE="$REPO_PROFILES_DIR/packages"

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
	# Prefixed item might have alias on default (so we just delte the prefixed one)
	[prefixed]=4
	[ghost]=9
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

get_commit_id() {
	git -C "$REPO_INSTALL_DIR" rev-parse HEAD
}

read_by_null() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -d $'\0' _ref
}

read_byte() {
	local -n _ref="${1:-REPLY}"
	IFS="" read -r -n 1 _ref
}

is_profiles() {
	if (($1 % 2 == 0)); then
		return 0
	else
		return 1
	fi
}

is_file() {
	if (($1 % 2 != 0)); then
		return 0
	else
		return 1
	fi
}

get_items() {
	local dir_path="$1"
	local -n arr_ref="$2"

	# shellcheck disable=SC2034
	mapfile -d $'\0' arr_ref < \
		<(find "$dir_path" -mindepth 1 -maxdepth 1 -printf "%f\0")
}

diff() {
	local track_file="$1"

	_show_err() {
		printf "parse err: %s\n" "$1" >&2
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

		local -A new_item=()
		local skip_base="" prefix_dir="" prefix_base=""
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

			local state=${STATE[_]}
			if [[ -n "$skip_base" ]]; then
				if [[ "$base" == "$skip_base/"* ]]; then
					state=${STATE[D]}
					printfc "($type:$own) ├─ $base" "${STATE_CLR[$state]}"
					continue
				else
					skip_base=""
				fi
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
						repo_path="$_OVERRIDE_DIR/${base%/*}/$prefix${base##*/}"
					else
						repo_path="$_OVERRIDE_DIR/$prefix$base"
					fi
					# Store prefix directory
					if [[ "$type" == "d" ]]; then
						prefix_base="$base"
						prefix_dir="$repo_path"
					fi
				elif [[ "$own" == "${OWN[override]}" || "$own" == "${OWN[both]}" ]]; then
					repo_path="$_OVERRIDE_DIR/$base"
				elif [[ "$own" == "${OWN[default]}" ]]; then
					repo_path="$_DEFAULT_DIR/$base"
				else
					_show_err "unknown own type '$own'"
				fi
			fi

			local home_path="$_HOME_DIR/$base"
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
					done < <(find "$home_path" -maxdepth 1 -mindepth 1 -print0)
				else
					state=${STATE[D]} # deleted (or file)
					skip_base="$base"
				fi
			fi

			case "$state" in
			"${STATE[_]}" | "${STATE[M]}")
				unset "new_item[$home_path]"
				if [[ "$state" == "${STATE[M]}" ]]; then
					install -o root -g root -m 700 "$home_path" "$repo_path"
				fi
				;;
			"${STATE[D]}")
				rm -rf "$repo_path"
				;;
			esac

			printfc "($type:$own) $base" "${STATE_CLR[$state]}"
		done

		for new_item in "${!new_item[@]}"; do
			printfc "$new_item" "${STATE_CLR[${STATE[A]}]}"
		done

	} <"$track_file"

}

main() {
	local home="/home/kana"
	local del_base="$home/.config/zsh"
	local del_repo_path="$home/.config/zsh"

	if [[ -e "$del_base" ]]; then
		echo "exist ok: $del_base"
	fi

	rm -rf "$del_base"

	_HOME_DIR="$home" _DEFAULT_DIR="$(get_home_profile_dir "default")" _OVERRIDE_DIR="$(get_home_profile_dir "uwu")" \
		diff "$REPO_TRACKS_DIR/1000"

}

main
