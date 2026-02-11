@echo off

set "OS=%~1"
set "USERNAME=%~2"

set "IMAGE_NAME=conf-%OS%"
set "CONTAINER_NAME=%IMAGE_NAME%-container"

set "DOCKER_CLI_HINTS=false"

docker exec ^
--interactive ^
--tty ^
--workdir "/home/%USERNAME%" ^
--user "%USERNAME%" ^
"%CONTAINER_NAME%" zsh --login
