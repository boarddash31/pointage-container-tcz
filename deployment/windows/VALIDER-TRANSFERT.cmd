@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0TESTS-FICTIFS\snapshot-v5\snapshot.json" (
  echo Extraire tout le paquet dans un nouveau dossier avant de lancer ce fichier.
  pause
  exit /b 1
)
where dotnet.exe >nul 2>&1
if errorlevel 1 (
  echo SDK .NET requis : utiliser le serveur208 deja equipe.
  pause
  exit /b 1
)
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_NOLOGO=1"
set "ZENATA_TRANSFER_LOG=%~dp0transfert-validation-%RANDOM%-%RANDOM%.log"
echo Validation du nouvel outil de transfert sur des donnees FICTIVES uniquement.
echo Aucun appel SQL, export Supabase, import ou lancement d'API.
echo Journal : "%ZENATA_TRANSFER_LOG%"
pushd "%~dp0backend"
dotnet build Pointage.Migration -c Release --nologo > "%ZENATA_TRANSFER_LOG%" 2>&1
if errorlevel 1 goto erreur
dotnet run --project Pointage.Migration -c Release --no-build -- --snapshot "%~dp0TESTS-FICTIFS\snapshot-v5" --check --manifest v5 >> "%ZENATA_TRANSFER_LOG%" 2>&1
if errorlevel 1 goto erreur
popd
echo VALIDATION TRANSFERT V5 REUSSIE - AUCUNE CONNEXION BASE
echo La base reste en version4 tant que le script SQL separe n'est pas execute.
pause
exit /b 0
:erreur
popd
echo VALIDATION TRANSFERT EN ECHEC - Consulter "%ZENATA_TRANSFER_LOG%"
pause
exit /b 1
