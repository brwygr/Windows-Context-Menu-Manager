@echo off
cd /d "%~dp0"
if exist "%~dp0MenuManager.exe" (
  start "" "%~dp0MenuManager.exe"
) else (
  "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -STA -ExecutionPolicy Bypass -File "%~dp0Launch.ps1"
  if errorlevel 1 pause
)
