@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0backend\Pointage.Setup\Pointage.Setup.csproj" (
 echo Copier ce correctif dans le dossier du runtime SQL complet deja compile.
 pause
 exit /b 1
)
set "ZENATA_ADMIN_BUILD_LOG=%~dp0compilation-admin-vide-%RANDOM%-%RANDOM%.log"
set "ZENATA_ADMIN_BUILD_OUTPUT=%~dp0tools\setup"
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
echo Mise a jour de l'outil de creation du premier Admin sans import.
echo Aucun appel a SQL Server ou Supabase. Aucun compte cree pendant la compilation.
echo Journal : "%ZENATA_ADMIN_BUILD_LOG%"
pushd "%~dp0backend"
dotnet publish Pointage.Setup -c Release -r win-x64 --self-contained false --nologo -o "%ZENATA_ADMIN_BUILD_OUTPUT%" > "%ZENATA_ADMIN_BUILD_LOG%" 2>&1
set "ZENATA_ADMIN_BUILD_EXIT=%ERRORLEVEL%"
popd
if not "%ZENATA_ADMIN_BUILD_EXIT%"=="0" (
 echo COMPILATION EN ECHEC. Consulter le journal indique.
 pause
 exit /b %ZENATA_ADMIN_BUILD_EXIT%
)
"%~dp0node.exe" "%~dp0verifier-runtime-sql.cjs" >> "%ZENATA_ADMIN_BUILD_LOG%" 2>&1
if errorlevel 1 (
 echo CONTROLE RUNTIME EN ECHEC. Consulter le journal indique.
 pause
 exit /b 1
)
echo INITIALISATION ADMIN SANS IMPORT PRETE.
echo Lancer CREER-PREMIER-ADMIN-SQL.cmd, puis CONFIGURER-RUNTIME-SQL.cmd.
pause
exit /b 0
