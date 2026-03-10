#!/bin/bash
source /app-dev/conf.sh

# is_git_clean() {
# 	if [[ -n $(git status --porcelain "$REPO_PROFILES_DIR") ]]; then
# 		return 0
# 	else
# 		return 1
# 	fi
# }

get_temp_path() {
	local random_str
	random_str="$(tr -dc A-Za-z0-9 </dev/urandom | head -c 8)"
	printf "/tmp/test-%s" "$random_str"
}

# *Has static rule
_test_main() {
	# New item should be in tracked item!
	_show_msg() {
		printfc "[Test] $1" "$2" >&2
	}

	# Before test
	useradd -G "sudo" "$TEST_USER"

	# Get temp test dir
	local tmp_dir
	tmp_dir="$(get_temp_path)"
	mkdir "$tmp_dir"

	# Homes
	local repo_a_dir="$tmp_dir/a"
	local repo_b_dir="$tmp_dir/b"
	local local_dir="$tmp_dir/out"

	# Track file
	local user_id
	user_id="$(id -u "$TEST_USER")"
	local track_file="$tmp_dir/$user_id"

	_build() {
		rm -rf "${tmp_dir:?}/"*
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

		_build
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

		_build
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

	}

	_add_kana_dir() {
		[[ -d "$repo_a_dir/a_dir/kana" ]] && return 0 || return 1
	}
	_run_add_test "$local_dir/a_dir/kana" "_add_kana_dir"

	# Clean up temp test dir
	_show_msg "Clean up test dir" "${C[C]}"
	rm -rf "$tmp_dir"

	### Modify test
	local modify_content="hello, world 1234"
	_run_modify_test() {
		local modify_file="$1"
		local callback="$2"

		_build

		_run_apply_to_local
		rm -f "$modify_file"
		printf "%s" "$modify_content" >>"$modify_file"
		_run_apply_to_repo

		if "$callback"; then
			_show_msg "$callback - Success" "${C[G]}"
		else
			_show_msg "$callback - Failed" "${C[R]}"
		fi
		printf "\n"

	}

	_modify_a_file1() {
		if [[ "$(cat "$repo_a_dir/a_dir/a_file1")" == "$modify_content" ]]; then
			return 0
		fi
		return 1
	}
	_run_modify_test "$local_dir/a_dir/a_file1" "_modify_a_file1"
}

generate_test_data() {
	local dest_dir="$1"
	local prefix="$2"

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
	mkdir -p "$b_dir/"{b_dir,u_dir,"$prefix"p_dir}
	printf "b" >>"$b_dir/${prefix}p_file"
	touch "$b_dir/${prefix}p_dir/b_"{1..3}
	touch "$b_dir/b_file"{1..3}
	touch "$b_dir/b_dir/b_file"{1..3}
	touch "$b_dir/u_dir/u_file"{1..6}
}

test_apply_to_local() {
	echo "hello"
}

test_apply_to_local() {
	echo "hello"
}

test_run() {
	# Create temporary base
	local tmp_dir
	tmp_dir="$(get_temp_path)"
	mkdir "$tmp_dir"

	# Define test env
	local prefix="kawaii#"

	# Execute test func
	local fn
	# shellcheck disable=SC2128
	for fn in $(declare -F | awk -v f="$FUNCNAME" '$3 ~ /^test_/ && $3 !~ f && $3 !~ /_before$/ {print $3}'); do
		generate_test_data "$tmp_dir" "$prefix"

		"$fn"

		rm -rf "${tmp_dir:?}"/*
	done

	# Clean up temp test dir
	rm -rf "$tmp_dir"
}

test_run
