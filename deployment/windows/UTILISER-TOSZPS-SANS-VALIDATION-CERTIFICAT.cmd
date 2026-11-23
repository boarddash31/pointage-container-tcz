@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0tools\setup\Pointage.Setup.dll" (
 echo Lancer COMPILER-RUNTIME-SQL.cmd sur208 avant cette etape.
 pause
 exit /b 1
)
dotnet "%~dp0tools\setup\Pointage.Setup.dll" --preflight-existing-login-unverified "%~dp0."
set "ZENATA_SQL_STEP_EXIT=%ERRORLEVEL%"
pause
exit /b %ZENATA_SQL_STEP_EXIT%
