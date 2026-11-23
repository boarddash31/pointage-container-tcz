@echo off
setlocal
cd /d "%~dp0"
if not exist "node.exe" (
  echo Runtime node.exe absent. Voir LIRE-MOI.txt.
  pause
  exit /b 1
)
if exist "%~dp0runtime.env" (
  "%~dp0node.exe" --env-file="%~dp0runtime.env" "%~dp0http-runtime.cjs"
) else (
  "%~dp0node.exe" "%~dp0http-runtime.cjs"
)
pause
