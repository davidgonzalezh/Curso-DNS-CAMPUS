@echo off
setlocal
chcp 65001 >nul
cd /d "%~dp0"
title Curso DNS CAMPUS - Diagnosticar

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnosticar-lab.ps1"

exit /b %ERRORLEVEL%
