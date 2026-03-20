@echo off
setlocal
echo __AGENT_SHIM__=1
echo __AGENT_CWD__=%CD%
echo __AGENT_ENV__=%FELIX_AGENT_TEST%
echo __AGENT_PROMPT_LEN__=0
echo __AGENT_ARGS__=%*
echo **Task Completed:** Smoke test agent invocation
echo ^<promise^>ALL_COMPLETE^</promise^>
exit /b 0