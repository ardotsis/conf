#!/bin/bash
set -euo pipefail -o noclobber

# fn() {
# 	echo hello >/root/hello.txt
# }

# declare -f fn

is_git_clean() {
	local repo_path="$1"
	local dir="${2:-$repo_path}"
	# local dir="$repo_path/${2:-$repo_path}"

	echo "$repo_path"
	echo "$dir"

	if [[ -z "$(git -C "$repo_path" status --porcelain "$dir")" ]]; then
		return 0
	else
		return 1
	fi
}

if is_git_clean '/app' 'data/profiles'; then
	echo 'git is clean'
else
	echo 'some changes are detected'
fi
