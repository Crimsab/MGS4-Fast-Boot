@echo off
setlocal
title MGS4 Fast Boot 1.0.0 - Uninstall
where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mods\FastBoot\Install-Mgs4FastBootLoader.ps1" -Action Uninstall
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0mods\FastBoot\Install-Mgs4FastBootLoader.ps1" -Action Uninstall
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
