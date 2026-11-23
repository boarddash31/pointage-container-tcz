@echo off
setlocal
cd /d "%~dp0"
set "ZENATA_SQL_AUTOSTART=1"
echo ZENATA - Demarrage automatique sur208
echo Fermer l'ancien lanceur avec Ctrl+C pour liberer le port9091.
where dotnet.exe >nul 2>&1
if errorlevel 1 (
 echo Le runtime et le SDK .NET10 sont requis sur208 pour le premier lancement.
 goto erreur
)
if not exist "%~dp0api\Pointage.Api.dll" goto compiler
if not exist "%~dp0tools\setup\Pointage.Setup.dll" goto compiler
if not exist "%~dp0RUNTIME-COMPILE.json" goto compiler
goto preparer
:compiler
echo Premier lancement : compilation automatique. Patienter pendant cette etape.
call "%~dp0COMPILER-RUNTIME-SQL.cmd"
if errorlevel 1 goto erreur
:preparer
dotnet "%~dp0tools\setup\Pointage.Setup.dll" --prepare "%~dp0."
if errorlevel 1 goto erreur
call "%~dp0LANCER-SQL-9091.cmd"
if errorlevel 1 goto erreur
pause
exit /b 0
:erreur
echo Demarrage non termine. Conserver le message et le journal indiques.
pause
exit /b 1
