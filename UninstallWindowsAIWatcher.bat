@echo off
setlocal
title Remove Upgrade without AI watcher
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-WindowsAIWatcher.ps1" -Uninstall
echo.
pause
