@echo off
setlocal DisableDelayedExpansion
set "Repositorio=%~dp0"
if "%Repositorio:~-1%"=="\" set "Repositorio=%Repositorio:~0,-1%"
set "PowerShell=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PowerShell%" (
    echo No se encontro Windows PowerShell 5.1.
    endlocal & exit /b 1	
)
set "Puerto=8123"
set "UrlPanel=http://127.0.0.1:%Puerto%/"
"%PowerShell%" -NoProfile -Command "$ErrorActionPreference='Stop'; try { $r=Invoke-WebRequest -UseBasicParsing -Uri '%UrlPanel%api/estado' -TimeoutSec 2; if($r.StatusCode -eq 200 -and $r.Content -match '\"ok\":true'){ exit 0 } } catch {}; exit 1"
if "%ERRORLEVEL%"=="0" (
    echo.
    echo El panel web ya se encuentra ejecutando en:
    echo %UrlPanel%
    start "" "%UrlPanel%"
    pause
    endlocal & exit /b 0
)
"%PowerShell%" -NoProfile -ExecutionPolicy Bypass -File "%Repositorio%\binary\ServidorPanelWeb.ps1" -RepositoryRoot "%Repositorio%"
set "CodigoSalida=%ERRORLEVEL%"
if not "%CodigoSalida%"=="0" (
    echo.
    echo El panel web no pudo iniciar. Codigo de salida: %CodigoSalida%
    echo Revise el mensaje anterior para conocer la causa.
    pause
)
endlocal & exit /b %CodigoSalida%
