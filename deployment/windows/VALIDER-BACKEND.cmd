@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0backend\Pointage.Checks\Pointage.Checks.csproj" (
  echo Extraire tout le paquet avant de lancer ce fichier.
  pause
  exit /b 1
)
where dotnet.exe >nul 2>&1
if errorlevel 1 (
  echo SDK .NET absent du PATH. Fermer puis rouvrir la session apres installation.
  pause
  exit /b 1
)
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_NOLOGO=1"
set "ZENATA_VALIDATION_LOG=%~dp0validation-%RANDOM%-%RANDOM%.log"
echo Compilation et controles du backend SQL prepare.
echo Aucun lancement d'API, import ou appel a la base de donnees.
echo Journal : "%ZENATA_VALIDATION_LOG%"
pushd "%~dp0backend"
dotnet --version > "%ZENATA_VALIDATION_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [1/4] Compilation des controles et de l'API...
dotnet build Pointage.Checks -c Release --nologo >> "%ZENATA_VALIDATION_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [2/4] Compilation de l'outil de migration, sans l'executer...
dotnet build Pointage.Migration -c Release --nologo >> "%ZENATA_VALIDATION_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [3/4] Compilation de l'outil Admin, sans l'executer...
dotnet build Pointage.Admin -c Release --nologo >> "%ZENATA_VALIDATION_LOG%" 2>&1
if errorlevel 1 goto erreur
echo [4/4] Verification de syntaxe SQL et tests locaux des regles et comptes...
dotnet run --project Pointage.Checks -c Release --no-build >> "%ZENATA_VALIDATION_LOG%" 2>&1
if errorlevel 1 goto erreur
popd
echo.
echo VALIDATION BACKEND REUSSIE
echo L'application actuelle continue de fonctionner. Aucune bascule effectuee.
echo Journal : "%ZENATA_VALIDATION_LOG%"
pause
exit /b 0
:erreur
popd
echo.
echo VALIDATION BACKEND EN ECHEC
echo Consulter le journal : "%ZENATA_VALIDATION_LOG%"
echo Ne pas lancer manuellement l'importeur, l'outil Admin ou l'API.
echo Si NuGet est bloque, faire fournir les dependances par le circuit IT autorise.
pause
exit /b 1
