@echo off
chcp 65001 >nul
title Desinstallation GuildScribe
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fichiers\Install-Kit.ps1" -Uninstall
echo.
pause
