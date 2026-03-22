#!/usr/bin/env bash
set -euo pipefail -o noclobber

# shellcheck disable=SC1091
source "$DOCKER_DEV_APP_DIR"/conf.sh

generate_test_data() {
	local dest_dir="$1"
	local prefix="$2"

	mkdir -p "$dest_dir/"{LEFT,RIGHT,_MIX}

	local L_dir="$dest_dir/LEFT"
	local R_dir="$dest_dir/RIGHT"

	# base directory
	mkdir -p "$L_dir/"{L_dir,U_dir,X_dir}
	printf "L" >>"$L_dir/X_file"
	touch "$L_dir/X_dir/L_file"{1..3}
	mkdir "$L_dir/X_dir/X2_dir"
	touch "$L_dir/X_dir/X2_dir/L_file"{1..3}
	touch "$L_dir/L_file"{1..3}
	touch "$L_dir/L_dir/L_file"{1..3}
	touch "$L_dir/U_dir/U_file"{1..6}

	# override directory
	mkdir -p "$R_dir/"{R_dir,U_dir,"$prefix"X_dir}
	printf "R" >>"$R_dir/${prefix}X_file"
	touch "$R_dir/${prefix}X_dir/R_file"{1..3}
	mkdir "$R_dir/${prefix}X_dir/X2_dir"
	touch "$R_dir/${prefix}X_dir/X2_dir/R_file"{1..3}
	touch "$R_dir/R_file"{1..3}
	touch "$R_dir/R_dir/R_file"{1..3}
	touch "$R_dir/U_dir/U_file"{1..3}
}

get_temp_path() {
	local random_str
	random_str="$(tr -dc a-z0-9 </dev/urandom | head -c 6)"
	printf "/tmp/%s" "$random_str"
}

log_test() {
	local msg="$1"
	_debug "TEST - $msg" >&2
}

print_tree() {
	local dir="$1"
	local tag="$2"

	printf "========== %s - START ==========\n" "$tag"
	tree "$dir" --noreport
	printf "========== %s - FINISH ==========\n" "$tag"
}

test_main() {
	useradd -G "sudo" "$TEST_USER"
	log_test "Created test user: $TEST_USER"

	# Get temp test dir
	local tmp_dir
	tmp_dir="$(get_temp_path)"
	mkdir "$tmp_dir"
	log_test "Created test temp dir: $tmp_dir"

	# Homes
	local repo_a_dir="$tmp_dir/a"
	local repo_b_dir="$tmp_dir/b"
	local out_dir="$tmp_dir/out"

	local track_file="$tmp_dir/$TRACK_FILENAME"

	_build() {
		rm -rf "${tmp_dir:?}/"*
		generate_test_data "$tmp_dir" "$TEST_PREFIX"
		print_tree "$tmp_dir" "BUILT"
	}

	_run_apply_to_local() {
		_TRACK_FILE="$track_file" _PROFILE="$TEST_PROFILE" _USER="$TEST_USER" _GIT_COMMIT_ID="$TEST_GIT_COMMIT_ID" \
			apply_to_local "$out_dir" "$repo_b_dir" "$repo_a_dir"
	}

	_run_apply_to_repo() {
		{
			read_by_null _ # old user id
			read_by_null profile
			read_by_null track_commit_id

			local -a unlinks_ref
			apply_to_repo "$out_dir" "$repo_b_dir" "$repo_a_dir" "$TEST_PROFILE" "unlinks_ref"
		} <"$track_file"

		for item in "${unlinks_ref[@]}"; do
			echo "unlink: $item"
		done
		print_tree "$tmp_dir" "APPLIED TO REPO"
	}

	### Delete test
	_run_del_test() {
		local rm_dir="$1"
		local callback="$2"

		_build
		_run_apply_to_local

		if [[ ! -e "$rm_dir" ]]; then
			log_test "Invalid del dir: $rm_dir" "${C[R]}"
			exit 1
		fi

		rm -rf "$rm_dir"
		_run_apply_to_repo

		if "$callback"; then
			log_test "$callback - Success" "${C[G]}"
		else
			log_test "$callback - Failed" "${C[R]}"
		fi
		printf "\n"
	}

	_del_a_dir() {
		[[ ! -e "$repo_a_dir/a_dir" ]] && return 0 || return 1
	}
	_run_del_test "$out_dir/a_dir" "_del_a_dir"

	_del_u_dir() {
		[[ ! -e "$repo_a_dir/u_dir" && ! -e "$repo_b_dir/u_dir" ]] && return 0 || return 1
	}
	_run_del_test "$out_dir/u_dir" "_del_u_dir"

	_del_p_dir() {
		[[ ! -e "$repo_b_dir/${TEST_PREFIX}p_dir" ]] && return 0 || return 1
	}
	_run_del_test "$out_dir/p_dir" "_del_p_dir"

	### Add test
	_run_add_test() {
		local add_dir="$1" # TODO: support file
		local callback="$2"

		_build

		_run_apply_to_local
		mkdir "$add_dir"
		_run_apply_to_repo

		if "$callback"; then
			log_test "$callback - Success" "${C[G]}"
		else
			log_test "$callback - Failed" "${C[R]}"
		fi
		printf "\n"

	}

	_add_kana_dir() {
		[[ -d "$repo_a_dir/a_dir/kana" ]] && return 0 || return 1
	}
	_run_add_test "$out_dir/a_dir/kana" "_add_kana_dir"

	_add_kana_dir_to_p() {
		[[ -d "$repo_b_dir/${TEST_PREFIX}p_dir/kana" ]] && return 0 || return 1
	}
	_run_add_test "$out_dir/p_dir/kana" "_add_kana_dir_to_p"

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
			log_test "$callback - Success" "${C[G]}"
		else
			log_test "$callback - Failed" "${C[R]}"
		fi
		printf "\n"

	}

	_modify_a_file1() {
		if [[ "$(cat "$repo_a_dir/a_dir/a_file1")" == "$modify_content" ]]; then
			return 0
		fi
		return 1
	}
	_run_modify_test "$out_dir/a_dir/a_file1" "_modify_a_file1"
}

# test_main
declare -r TEST_USER="kana"
declare -r TEST_PROFILE="mine"
declare -r TEST_GIT_COMMIT_ID="test_git_commit_id"

test_patch_diff() {
	# Create test environment
	log_test "Create user"
	useradd -G "sudo" "$TEST_USER"

	log_test "Create temp test directory"
	local tmp_dir
	tmp_dir="/tmp/test_"
	mkdir "$tmp_dir"

	log_test "Create test data"
	generate_test_data "$tmp_dir" "$(get_prefix "$TEST_PROFILE")"
	print_tree "$tmp_dir" "CREATE TEST DATA"

	local L_dir="$tmp_dir/LEFT"
	local R_dir="$tmp_dir/RIGHT"
	local MIX_dir="$tmp_dir/_MIX"
	local track="$tmp_dir/$TRACK_FILENAME"

	write_track_header "$track" "$(id -u "$TEST_USER")" "$TEST_PROFILE" "some_git_commit_id"
	_TRACK="$track" _PREFIX="$TEST_PROFILE#" _OWNER="$TEST_USER" \
		patch_mix "$L_dir" "$R_dir" "$MIX_dir"

	print_tree "$tmp_dir" "MIXING"

	# Create change
	rm -rf "$MIX_dir/L_dir"
	touch "$MIX_dir/R_dir/newFile"
	rm -f "$MIX_dir/R_dir/R_file1"
	echo 'helo' >"$MIX_dir/R_dir/R_file1"

	# Read meta headers
	{
		local user_id profile commit_id
		read_by_null user_id
		read_by_null profile
		read_by_null commit_id

		# Pass paths to patcher
		patch_LR "$L_dir" "$R_dir" "$MIX_dir" "$profile#"

	} <"$track"
}

test_patch_diff
