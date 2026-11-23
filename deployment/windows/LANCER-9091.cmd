@echo off
setlocal
cd /d "%~dp0"
set "HOST=172.17.18.208"
set "PORT=9091"
if not exist "%~dp0node.exe" (
  echo Copier ce lanceur dans le dossier du runtime contenant node.exe et http-runtime.cjs.
  pause
  exit /b 1
)
if exist "%~dp0runtime.env" (
  "%~dp0node.exe" --env-file="%~dp0runtime.env" "%~dp0http-runtime.cjs"
) else (
  "%~dp0node.exe" "%~dp0http-runtime.cjs"
)
pause
