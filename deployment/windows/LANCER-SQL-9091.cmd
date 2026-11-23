@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0api\appsettings.Local.json" (
 echo Lancer DEMARRER-ZENATA.cmd pour preparer automatiquement la configuration SQL.
 pause
 exit /b 1
)
if not exist "%~dp0api\Pointage.Api.dll" (
 echo Lancer COMPILER-RUNTIME-SQL.cmd sur208 avant le premier demarrage.
 pause
 exit /b 1
)
if not exist "%~dp0logs" mkdir "%~dp0logs"
set "ZENATA_SQL_BACKEND_LOG=%~dp0logs\backend-%RANDOM%-%RANDOM%.log"
set "ASPNETCORE_URLS=http://127.0.0.1:19091"
set "ASPNETCORE_ENVIRONMENT=Production"
echo Demarrage SQL Server : http://172.17.18.208:9091/
echo Journal API : "%ZENATA_SQL_BACKEND_LOG%"
echo Garder cette console ouverte. Ctrl+C arrete l'API et le serveur web.
pushd "%~dp0api"
dotnet Pointage.Api.dll >> "%ZENATA_SQL_BACKEND_LOG%" 2>&1
set "ZENATA_SQL_EXIT=%ERRORLEVEL%"
popd
echo Arret du runtime. Consulter le journal si le demarrage a echoue.
if not "%ZENATA_SQL_AUTOSTART%"=="1" pause
exit /b %ZENATA_SQL_EXIT%
