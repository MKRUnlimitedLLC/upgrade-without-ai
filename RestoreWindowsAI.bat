@echo off
setlocal
title Restore Windows AI settings
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Restore-WindowsAI.ps1"
echo.
pause
