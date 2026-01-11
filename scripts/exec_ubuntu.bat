@echo off

set "DEV_USERNAME=kana"
set "IMAGE_NAME=dotfiles-ubuntu"
set "CONTAINER_NAME=%IMAGE_NAME%-container"
set "DOCKER_CLI_HINTS=false"

docker exec ^
--interactive ^
--tty ^
--user "%DEV_USERNAME%" ^
--workdir "/home/%DEV_USERNAME%" ^
"%CONTAINER_NAME%" zsh
