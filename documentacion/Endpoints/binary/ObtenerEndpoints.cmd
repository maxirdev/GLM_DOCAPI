@echo off
chcp 65001 >nul
title Extraccion de endpoints APIGLM
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0GenerarListaEndpoints.ps1"
echo.
echo.
pause
