@echo off
setlocal
cd /d "%~dp0"
set "DOTNET_CLI_TELEMETRY_OPTOUT=1"
set "DOTNET_NOLOGO=1"
echo MODE DIAGNOSTIC : chiffrement actif mais identite du serveur NON VERIFIEE.
echo Lecture seule. Ce lanceur ne configure pas l'API de production.
if not exist "backend\Pointage.ConnectionCheck\Pointage.ConnectionCheck.csproj" (
  echo Extraire entierement le paquet avant de lancer ce fichier.
  pause
  exit /b 1
)
pushd "%~dp0backend"
dotnet build Pointage.ConnectionCheck -c Release --nologo
if errorlevel 1 goto erreur
dotnet run --project Pointage.ConnectionCheck -c Release --no-build -- --allow-unverified-server-for-diagnostic
if errorlevel 1 goto erreur
popd
pause
exit /b 0
:erreur
popd
echo Diagnostic en echec. Conserver le message affiche, jamais le mot de passe.
pause
exit /b 1
