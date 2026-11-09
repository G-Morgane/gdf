@echo off
chcp 65001 >nul
title Installation GuildScribe
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0fichiers\Install-Kit.ps1"
if errorlevel 1 echo. & echo L installation a echoue : lis le message ci-dessus.
echo.
pause
