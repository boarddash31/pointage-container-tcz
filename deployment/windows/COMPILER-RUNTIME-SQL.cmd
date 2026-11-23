@echo off
setlocal
cd /d "%~dp0"
set "ZENATA_SQL_ROOT=%~dp0"
set "ZENATA_SQL_BUILD_LOG=%~dp0compilation-sql-%RANDOM%-%RANDOM%.log"
if not exist "%~dp0backend\Pointage.Setup\Pointage.Setup.csproj" (
 echo Extraire le paquet complet dans un nouveau dossier.
 pause
 exit /b 1
)
where dotnet.exe >nul 2>&1
if errorlevel 1 (
 echo SDK .NET10 requis : utiliser le serveur208 deja equipe.
 pause
 exit /b 1
)
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_NOLOGO=1"
echo Compilation du runtime SQL, des controles et des outils de transfert.
echo Aucun appel a la base, import, creation de compte ou lancement d'API.
echo Journal : "%ZENATA_SQL_BUILD_LOG%"
pushd "%~dp0backend"
dotnet --version > "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [1/5] Compilation et controles locaux...
dotnet build Pointage.Checks -c Release --nologo >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
dotnet run --project Pointage.Checks -c Release --no-build >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [2/5] Production de l'API executable...
dotnet publish Pointage.Api -c Release -r win-x64 --self-contained false --nologo -o "%ZENATA_SQL_ROOT%api" >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [3/5] Production de l'outil d'installation...
dotnet publish Pointage.Setup -c Release -r win-x64 --self-contained false --nologo -o "%ZENATA_SQL_ROOT%tools\setup" >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [4/5] Production de l'importeur et controle du transfert fictif...
dotnet publish Pointage.Migration -c Release -r win-x64 --self-contained false --nologo -o "%ZENATA_SQL_ROOT%tools\migration" >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
dotnet "%ZENATA_SQL_ROOT%tools\migration\Pointage.Migration.dll" --snapshot "%ZENATA_SQL_ROOT%TESTS-FICTIFS\snapshot-v5" --check --manifest v5 >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur
popd
echo [5/5] Controle des fichiers web et du runtime...
"%ZENATA_SQL_ROOT%node.exe" "%ZENATA_SQL_ROOT%verifier-runtime-sql.cjs" >> "%ZENATA_SQL_BUILD_LOG%" 2>&1
if errorlevel 1 goto erreur_apres_pop
echo.
echo RUNTIME SQL COMPILE ET PRET A CONFIGURER
echo API : "%ZENATA_SQL_ROOT%api\Pointage.Api.dll"
echo L'application actuelle et les bases n'ont pas ete modifiees.
echo Journal : "%ZENATA_SQL_BUILD_LOG%"
if not "%ZENATA_SQL_AUTOSTART%"=="1" pause
exit /b 0
:erreur
popd
:erreur_apres_pop
echo.
echo COMPILATION SQL EN ECHEC - Consulter "%ZENATA_SQL_BUILD_LOG%"
echo Les bases et l'application actuelle n'ont pas ete modifiees.
if not "%ZENATA_SQL_AUTOSTART%"=="1" pause
exit /b 1
