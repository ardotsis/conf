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

declare -Ar ITEM=(
	[_]=0
	[F]=1
	[pF]=2
	[D]=3
	[pD]=4
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
	IFS="" read -r -d $'\0' "$1"
}

has_p_prefix() {
	if [[ "$1" == $'\1'* ]]; then
		return 0
	else
		return 1
	fi
}

is_profiles() {
	if (($1 % 2 == 0)); then
		return 0
	else
		return 1
	fi
}

is_file() {
	if (($1 <= 2)); then
		return 0
	else
		return 1
	fi
}

update() {
	local track_file="$1"

	{
		local prof commid
		read_by_null "prof"
		read_by_null "commid"
		echo "profile $prof commit id: $commid"

		local base sum
		while read_by_null base && read_by_null sum; do
			local type=${ITEM[_]}
			if [[ -n "$sum" ]]; then
				has_p_prefix "$base" && type=${ITEM[pF]} || type=${ITEM[F]}
			else
				has_p_prefix "$base" && type=${ITEM[pD]} || type=${ITEM[D]}
			fi

			local home_path orig_path
			if is_profiles $type; then
				base="${base:1}"
				orig_path="$PROFILE_DIR/$base"
				home_path="$HOME_DIR/$base"
			else
				orig_path="$DEFAULT_DIR/$base"
				home_path="$HOME_DIR/$base"
			fi

			local state=${STATE[_]}
			if is_file $type; then
				if [[ -f "$home_path" ]]; then
					if [[ "$sum" == "$(get_sum "$home_path")" ]]; then
						:
					else
						state=${STATE[M]}
					fi
				else
					state=${STATE[D]}
				fi
			else
				if [[ -d "$home_path" ]]; then
					:
				else
					state=${STATE[D]}
				fi
			fi

			printfc "$home_path" "${STATE_CLR[$state]}"
		done
	} <"$track_file"

}

main() {
	HOME_DIR="/home/kana" DEFAULT_DIR="$(get_home_profile_dir "default")" PROFILE_DIR="$(get_home_profile_dir "uwu")" \
		update "$REPO_TRACKS_DIR/1000"
}

main
