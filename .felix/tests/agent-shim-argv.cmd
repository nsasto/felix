@echo off
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0agent-shim-argv.ps1" --% %*
exit /b %ERRORLEVEL%