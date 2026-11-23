@echo off
setlocal
cd /d "%~dp0"
if not exist "%~dp0node.exe" (
 echo Placer ces fichiers installateur dans le dossier du runtime ZENATA sur208.
 pause
 exit /b 1
)
"%~dp0node.exe" "%~dp0installer-connecteur-smtp.cjs"
set "ZENATA_SMTP_INSTALL_EXIT=%ERRORLEVEL%"
pause
exit /b %ZENATA_SMTP_INSTALL_EXIT%
