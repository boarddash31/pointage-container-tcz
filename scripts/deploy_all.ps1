$ErrorActionPreference = 'Stop'

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   DEPLOIEMENT COMPLET (CLOUDFLARE + NETLIFY) " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# 1. Sync & verify site directory
$siteDir = "$repoRoot\site"
if (-not (Test-Path "$siteDir\index.html") -or -not (Test-Path "$siteDir\dashboard.html")) {
    Write-Host "Reconstruction des fichiers web..." -ForegroundColor Yellow
    & "$PSScriptRoot\build_local.ps1"
}

# 2. Deploiement Netlify
Write-Host ""
Write-Host "--- [1/2] DEPLOIEMENT NETLIFY ---" -ForegroundColor Magenta
try {
    & "$PSScriptRoot\deploy_netlify.ps1"
} catch {
    Write-Host "Avertissement Netlify: $_" -ForegroundColor Yellow
}

# 3. Deploiement Cloudflare
Write-Host ""
Write-Host "--- [2/2] DEPLOIEMENT CLOUDFLARE PAGES ---" -ForegroundColor Magenta
& "$PSScriptRoot\deploy_cloudflare.ps1"

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "Termine avec succes !" -ForegroundColor Green
Write-Host "Site Netlify: https://pointage-tcz-test.netlify.app" -ForegroundColor Cyan
Write-Host "Dashboard:    https://pointage-tcz-test.netlify.app/dashboard" -ForegroundColor Cyan
Write-Host "Domaine:      https://marsa.digital" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Green
