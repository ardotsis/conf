@echo off
set "HOSTNAME=%~1"

if "%HOSTNAME%"=="" (
  echo Usage: .\%~nx0 ^<Hostname^>
  exit /b 1
)

ssh-keygen.exe -t ed25519 -b 4096 -f "%USERPROFILE%\.ssh\%HOSTNAME%" -N "insecure"
