@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Curso DNS CAMPUS - Detener

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0detener-lab.ps1"

exit /b %ERRORLEVEL%
