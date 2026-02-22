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

declare -Ar TYPE=(
	[F]=1
	[D]=2

	[pF]=3
	[pD]=4

	[xF]=5
	[xD]=6
)

declare -Ar TYPE_CLR=(
	[${TYPE[D]}]="${C[w]}"
	[${TYPE[F]}]="${C[W]}"
	[${TYPE[pD]}]="${C[g]}"
	[${TYPE[pF]}]="${C[G]}"
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

is_in_skip_dir() {
	local skip_dir="$1"
	local current_path="$2"

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

	local -A UNTRACKED_TYPE=()
	{
		local user_id profile commit_id
		read_by_null "user_id"
		read_by_null "profile"
		read_by_null "commit_id"
		echo "user_id=$user_id, profile=$profile, commit id=$commit_id"

		local SKIP_DIR="" type
		while :; do
			if ! read_byte type; then
				break
			fi

			local base="" sum=""
			if is_file "$type"; then
				read_by_null "base"
				read_by_null "sum"
			else
				read_by_null "base"
			fi
			printf "($type)  $base\n"

			# local state=${STATE[_]}
			# if [[ -n "$SKIP_DIR" ]]; then
			# 	if [[ "$base" == "$SKIP_DIR/"* ]]; then
			# 		state=${STATE[D]}
			# 		printfc "($type) ├─ $base" "${STATE_CLR[$state]}"
			# 		continue
			# 	else
			# 		SKIP_DIR=""
			# 	fi
			# fi

			# local home_path="$HOME_DIR/$base"

			# if is_file "$type"; then
			# 	if [[ -f "$home_path" ]]; then
			# 		if [[ "$sum" != "$(get_sum "$home_path")" ]]; then
			# 			state=${STATE[M]}
			# 		fi
			# 	else
			# 		state=${STATE[D]} # deleted (or dir)
			# 	fi
			# else
			# 	if [[ -d "$home_path" ]]; then
			# 		local item
			# 		while read_by_null item; do
			# 			UNTRACKED_TYPE["$item"]=1
			# 		done < <(find "$home_path" -maxdepth 1 -mindepth 1 -print0)
			# 	else
			# 		state=${STATE[D]} # deleted (or file)
			# 		SKIP_DIR="$base"
			# 	fi
			# fi

			# case "$state" in
			# "${STATE[_]}" | "${STATE[M]}")
			# 	unset "UNTRACKED_TYPE[$home_path]"
			# 	if [[ "$state" == "${STATE[M]}" ]]; then
			# 		echo 'writing...'
			# 		install -o root -g root -m 700 "$home_path" "$repo_path"
			# 	fi
			# 	;;
			# "${STATE[D]}") ;;
			# esac

			# printfc "($type) $base" "${STATE_CLR[$state]}"
		done

	} <"$track_file"

	for untracked_item in "${!UNTRACKED_TYPE[@]}"; do
		printfc "$untracked_item" "${STATE_CLR[${STATE[A]}]}"
	done
}

main() {
	HOME_DIR="/home/kana" DEFAULT_DIR="$(get_home_profile_dir "default")" PROFILE_DIR="$(get_home_profile_dir "uwu")" \
		diff "$REPO_TRACKS_DIR/1000"
}

main
