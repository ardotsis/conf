#!/bin/bash
TMP_DIR="/tmp"

_get_random_str() {
	local length="$1"
	local chars="$2"

	printf "%s" "$(tr -dc "$chars" </dev/urandom | head -c "$length")"
}

get_safe_random_str() {
	local length="$1"
	_get_random_str "$length" "A-Za-z0-9"
}

printf "%s" "$(get_safe_random_str 16)"

make_env() {
	local base_dir="$1"

	local home_dir="$base_dir/home"
	local default_dir="$base_dir/profiles/default"
	local override_dir="$base_dir/profiles/override"

	mkdir -p "$home_dir"
	mkdir -p "$base_dir/profiles/"{default,override}

	ls -al "$base_dir"
}

make_env "$TMP_DIR/$(get_safe_random_str 16)"
