@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Curso DNS CAMPUS - Desinstalar

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0desinstalar-lab.ps1"

exit /b %ERRORLEVEL%
