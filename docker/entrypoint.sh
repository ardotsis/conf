#!/usr/bin/env bash
set -e

read -ra params <<<"$DOCKER_CONF_PARAMS"

if $DOCKER_IS_TEST; then
	"$DOCKER_DEV_APP_DIR"/test.sh "_docker-entrypoint" "${params[@]}"
else
	"$DOCKER_DEV_APP_DIR"/conf.sh "_docker-entrypoint" "${params[@]}"
fi
