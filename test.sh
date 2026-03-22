#!/usr/bin/env bash

# shellcheck disable=SC1091
source "$DOCKER_DEV_APP_DIR"/conf.sh

declare -r T_USER="kana"
declare -r T_PROFILE="mine"
declare -r T_GIT_COMMIT_ID="test_git_commit_id"
declare -r T_LEFT_DIRNAME="LEFT"
declare -r T_RIGHT_DIRNAME="RIGHT"
declare -r T_MIX_DIRNAME="_MIX"

log_test() {
	local msg="$1"
	_debug "TEST - $msg" >&2
}

print_tree() {
	local dir="$1"
	local tag="$2"

	printf "========== %s ==========\n" "$tag"
	tree "$dir" --noreport
	printf "========== %s (END) ==========\n" "$tag"
}

get_temp_path() {
	local random_str
	random_str="$(tr -dc a-z0-9 </dev/urandom | head -c 6)"
	printf "/tmp/%s" "$random_str"
}
generate_test_data() {
	local dest_dir="$1"
	local prefix="$2"

	mkdir -p "$dest_dir/"{$T_LEFT_DIRNAME,$T_RIGHT_DIRNAME,$T_MIX_DIRNAME}
	local L_dir="$dest_dir/$T_LEFT_DIRNAME"
	local R_dir="$dest_dir/$T_RIGHT_DIRNAME"

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

test_main() {
	useradd -G "sudo" "$T_USER"

	# Create test environment
	local tmp_dir
	tmp_dir="/tmp/test_"
	mkdir "$tmp_dir"
	generate_test_data "$tmp_dir" "$(get_prefix "$T_PROFILE")"
	print_tree "$tmp_dir" "CREATE TEST DATA"

	local L_dir="$tmp_dir/$T_LEFT_DIRNAME"
	local R_dir="$tmp_dir/$T_RIGHT_DIRNAME"
	local MIX_dir="$tmp_dir/$T_MIX_DIRNAME"
	local track="$tmp_dir/$TRACK_FILENAME"

	write_track_header "$track" "$(id -u "$T_USER")" "$T_PROFILE" "$T_GIT_COMMIT_ID"
	_TRACK="$track" _PREFIX="$(get_prefix "$T_PROFILE")" _OWNER="$T_USER" \
		patch_mix "$L_dir" "$R_dir" "$MIX_dir"
	print_tree "$tmp_dir" "Patch Mix"

	# Create change
	rm -rf "$MIX_dir/U_dir"
	# rm -rf "$MIX_dir/R_dir"
	local new_di="$MIX_dir/X_dir/X2_dir/test_new_dir"
	mkdir "$new_di"
	touch "$new_di/hello"content{1..3}

	# Read meta headers
	{
		local user_id profile commit_id
		read_by_null user_id
		read_by_null profile
		read_by_null commit_id

		# shellcheck disable=SC2034
		local -A adds=() dels=() mods=() uncs=() roots=()
		local -ra patch_LR_args=(
			"adds"
			"dels"
			"mods"
			"uncs"
			"roots"
			"$L_dir"
			"$R_dir"
			"$MIX_dir"
			"$profile#"
		)
		patch_LR "${patch_LR_args[@]}"

		local kind
		for kind in "adds" "dels" "mods" "uncs"; do
			local -n items="$kind"
			local state_char="${kind:0:1}"
			state_char="${state_char^^}"
			local state="${STATE[$state_char]}"

			if ((${#items[@]} > 0)); then
				for item in "${!items[@]}"; do
					local type="${item:0:1}"
					local MIX_path="${item:1}"
					local LR_path="${items[$item]}"
					LR_path="${LR_path:1}"

					printf "%b[${state_char}] %s%b\n" "${STATE_CLR[$state]}" "$MIX_path" "${C[0]}"

					case "$state" in
					"${STATE[A]}")
						case "$type" in
						"d")
							cp -r "$MIX_path" "$LR_path"
							chown "$T_USER:$T_USER" "$LR_path"
							;;
						"f")
							install_cmd -m 0700 -o "$T_USER" -g "$T_USER" "$MIX_path" "$LR_path"
							;;
						esac
						;;
					"${STATE[D]}")
						case "$type" in
						"d")
							rm -rf "$LR_path"
							;;
						"f")
							rm -f "$LR_path"
							;;
						esac
						;;
					"${STATE[M]}")
						rm -f "$LR_path"
						install_cmd -m 0700 -o "$T_USER" -g "$T_USER" "$MIX_path" "$LR_path"
						#
						;;
					"${STATE[U]}")
						# Do nothing
						;;
					esac

				done
			fi
		done
	} <"$track"

	print_tree "$tmp_dir" "Patch LR"
}

test_main
