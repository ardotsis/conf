@echo off

set "DEV_USERNAME=%~1"
set "IMAGE_NAME=dotfiles-debian"
set "CONTAINER_NAME=%IMAGE_NAME%-container"
set "DOCKER_CLI_HINTS=false"

docker exec ^
--interactive ^
--tty ^
--workdir "/home/%DEV_USERNAME%" ^
--user "%DEV_USERNAME%" ^
"%CONTAINER_NAME%" zsh --login
