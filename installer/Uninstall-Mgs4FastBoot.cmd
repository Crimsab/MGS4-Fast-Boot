@echo off
setlocal
title MGS4 Fast Boot - Uninstall
set "installer=%~dp0mods\FastBoot\Install-Mgs4FastBootLoader.ps1"
if not exist "%installer%" set "installer=%~dp0Install-Mgs4FastBootLoader.ps1"
where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%installer%" -Action Uninstall
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%installer%" -Action Uninstall
)
if errorlevel 1 goto failure
echo.
echo MGS4 Fast Boot was removed successfully.
pause
exit /b 0

:failure
echo.
echo Uninstallation failed. Read the error above.
pause
exit /b 1
