@echo off

@REM Batch arguments
set "INSTALL_SCRIPT_PARAMS=%~1"
set "FLAG=%~2"

@REM Docker run configurations
set "REPO_DIR=%~dp0.."
set "DOCKERFILE=%REPO_DIR%\tests\Dockerfile.debian"
set "IMAGE_NAME=conf"
set "IMAGE_TAG=latest"
set "IMAGE=%IMAGE_NAME%:%IMAGE_TAG%"
set "CONTAINER_NAME=%IMAGE_NAME%-container"
set "DOTFILES_VOLUME_DIR=/app"

@REM Docker configurations
set "DOCKER_CLI_HINTS=false"

if "%FLAG%"=="--cleanup" (
  echo Cleaning up running containers created from '%IMAGE%'...
  for /f "tokens=*" %%i in ('docker ps -aq --filter "ancestor=%IMAGE%"') do (
    docker rm -f %%i
  )
  for /f "tokens=*" %%i in ('docker ps -aq --filter "name=%CONTAINER_NAME%"') do (
    docker rm -f %%i
  )
)

if "%FLAG%"=="--build" (
  docker build --no-cache -f "%DOCKERFILE%" -t "%IMAGE%" "%REPO_DIR%"
  
  echo Cleaning up dangling images...
  for /f "tokens=*" %%i in ('docker images -f "dangling=true" -q') do (
    docker rmi -f %%i
  )
  echo Cleaning up build history...
  docker buildx history rm --all
)

docker run ^
--rm ^
--interactive ^
--tty ^
--hostname=somehost ^
--mount type=bind,source="%REPO_DIR%",target="%DOTFILES_VOLUME_DIR%" ^
--env INSTALL_SCRIPT_PARAMS="%INSTALL_SCRIPT_PARAMS%" ^
--env DOTFILES_VOLUME_DIR="%DOTFILES_VOLUME_DIR%" ^
--name "%CONTAINER_NAME%" "%IMAGE%"
