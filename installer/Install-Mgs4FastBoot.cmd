@echo off
setlocal
title MGS4 Fast Boot - Install
set "installer=%~dp0mods\FastBoot\Install-Mgs4FastBootLoader.ps1"
if not exist "%installer%" set "installer=%~dp0Install-Mgs4FastBootLoader.ps1"
where pwsh.exe >nul 2>nul
if %errorlevel% equ 0 (
  pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%installer%" -Action Install
) else (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%installer%" -Action Install
)
if errorlevel 1 goto failure
echo.
echo MGS4 Fast Boot was installed successfully.
echo Launch the game normally from Steam.
pause
exit /b 0

:failure
echo.
echo Installation failed. Read the error above.
pause
exit /b 1
