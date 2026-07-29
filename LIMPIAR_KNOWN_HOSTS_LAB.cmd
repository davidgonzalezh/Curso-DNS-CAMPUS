@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Curso DNS CAMPUS - Limpiar known_hosts

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0limpiar-known-hosts-lab.ps1"

exit /b %ERRORLEVEL%
