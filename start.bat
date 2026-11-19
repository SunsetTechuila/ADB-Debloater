@echo off
setlocal

set "powershell=powershell.exe"
for %%I in (pwsh.exe) do if not "%%~$PATH:I"=="" set "powershell=%%~$PATH:I"

"%powershell%" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\Debloater.ps1"
