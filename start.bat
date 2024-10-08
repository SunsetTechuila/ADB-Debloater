@echo off

where pwsh >nul 2>&1
if %errorlevel% equ 0 (
  set "powershell=pwsh"
) else (
  set "powershell=powershell"
)

%powershell% -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0src\Debloater.ps1"
