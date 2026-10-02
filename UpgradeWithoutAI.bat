@echo off
setlocal
title Upgrade without AI
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Disable-WindowsAI.ps1"
echo.
pause
