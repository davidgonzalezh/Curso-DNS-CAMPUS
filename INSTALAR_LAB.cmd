@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Curso DNS CAMPUS - Instalar

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0instalar-lab.ps1"

exit /b %ERRORLEVEL%
