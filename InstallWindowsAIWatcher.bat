@echo off
setlocal
title Install Upgrade without AI watcher
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-WindowsAIWatcher.ps1"
echo.
pause
