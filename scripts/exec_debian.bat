@echo off

set "USERNAME=%~1"
set "IMAGE_NAME=conf"
set "CONTAINER_NAME=%IMAGE_NAME%-container"
set "DOCKER_CLI_HINTS=false"

docker exec ^
--interactive ^
--tty ^
--workdir "/home/%USERNAME%" ^
--user "%USERNAME%" ^
"%CONTAINER_NAME%" zsh --login
