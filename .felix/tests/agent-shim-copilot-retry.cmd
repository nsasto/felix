@echo off
setlocal
echo %* | findstr /C:"gpt-5.4" >nul
if not errorlevel 1 (
  >&2 echo Error: Model "gpt-5.4" from --model flag is not available.
  exit /b 1
)
echo __AGENT_ARGS__=%*
echo __COPILOT_MODEL_FALLBACK__=1
exit /b 0