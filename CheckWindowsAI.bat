@echo off
setlocal
title Check Windows AI settings
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Watch-WindowsAI.ps1" -Source Manual
echo.
pause
