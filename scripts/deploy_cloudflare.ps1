$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# Helper to load .env variables
function Load-EnvFile($path) {
    if (Test-Path $path) {
        Get-Content $path | ForEach-Object {
            $line = $_.Trim()
            if ($line -and -not $line.StartsWith('#') -and $line.Contains('=')) {
                $idx = $line.IndexOf('=')
                $key = $line.Substring(0, $idx).Trim()
                $val = $line.Substring($idx + 1).Trim().Trim('"').Trim("'")
                if (-not [string]::IsNullOrEmpty($key) -and [string]::IsNullOrEmpty([System.Environment]::GetEnvironmentVariable($key))) {
                    [System.Environment]::SetEnvironmentVariable($key, $val, 'Process')
                }
            }
        }
    }
}

Load-EnvFile "$repoRoot\.env"
Load-EnvFile "$repoRoot\.env.local"

$accountId = $env:CLOUDFLARE_ACCOUNT_ID
$apiToken = $env:CLOUDFLARE_API_TOKEN
$projectName = if ($env:CLOUDFLARE_PROJECT_NAME) { $env:CLOUDFLARE_PROJECT_NAME } else { 'pointage-container-tcz' }

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "   CLOUDFLARE PAGES DEPLOYMENT HELPER     " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if (-not $accountId -or -not $apiToken) {
    Write-Host ""
    Write-Host "Identifiants Cloudflare manquants dans le fichier .env !" -ForegroundColor Yellow
    Write-Host "Pour deployer sur Cloudflare Pages, vous avez 2 methodes simples :"
    Write-Host ""
    Write-Host "METHODE 1 (Automatique via GitHub - Recommandee) :" -ForegroundColor Green
    Write-Host "  1. Ouvrez https://dash.cloudflare.com"
    Write-Host "  2. Allez dans 'Workers & Pages' > 'Create application' > 'Pages' > 'Connect to Git'"
    Write-Host "  3. Selectionnez votre repo 'boarddash31/pointage-container-tcz'"
    Write-Host "  4. Build command: (laisser vide)"
    Write-Host "  5. Build output directory: site"
    Write-Host "  6. Cliquez sur 'Save and Deploy' !"
    Write-Host ""
    Write-Host "METHODE 2 (Via GitHub Actions CI/CD) :" -ForegroundColor Green
    Write-Host "  1. Copiez votre Account ID & API Token dans .env"
    Write-Host "  2. Ajoutez-les dans GitHub > Settings > Secrets and variables > Actions"
    Write-Host "     - CLOUDFLARE_ACCOUNT_ID"
    Write-Host "     - CLOUDFLARE_API_TOKEN"
    Write-Host "  3. Chaque 'git push' declenchera le deploiment automatique !"
    Write-Host ""
    return
}

Write-Host "Verification du compte Cloudflare..."
$headers = @(
    "-H", "Authorization: Bearer $apiToken",
    "-H", "Content-Type: application/json"
)

$verify = curl.exe -k -s @headers "https://api.cloudflare.com/client/v4/user/tokens/verify"
$verifyObj = $verify | ConvertFrom-Json
if (-not $verifyObj.success) {
    Write-Host "Erreur Token Cloudflare : $($verifyObj.errors | ConvertTo-Json -Compress)" -ForegroundColor Red
    return
}

Write-Host "Token valide ! Verification du projet '$projectName'..." -ForegroundColor Green
$projectCheck = curl.exe -k -s @headers "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects/$projectName"
$projectObj = $projectCheck | ConvertFrom-Json

if (-not $projectObj.success) {
    Write-Host "Creation du projet Pages '$projectName'..." -ForegroundColor Yellow
    $createBody = @{
        name = $projectName
        production_branch = "main"
    } | ConvertTo-Json -Compress

    $createRes = curl.exe -k -s -X POST @headers -d $createBody "https://api.cloudflare.com/client/v4/accounts/$accountId/pages/projects"
    $createObj = $createRes | ConvertFrom-Json
    if ($createObj.success) {
        Write-Host "Projet cree avec succes !" -ForegroundColor Green
    } else {
        Write-Host "Avertissement creation : $($createObj.errors | ConvertTo-Json -Compress)" -ForegroundColor Yellow
    }
} else {
    Write-Host "Projet Pages trouve : $($projectObj.result.subdomain)" -ForegroundColor Green
}

$siteDirectory = Join-Path $repoRoot 'site'
if (-not (Test-Path (Join-Path $siteDirectory 'index.html'))) {
    throw "Web release missing at $siteDirectory. Run scripts/build_release.ps1 first."
}

Write-Host ""
Write-Host "Deploiement de la version web uniquement vers Cloudflare Pages..." -ForegroundColor Cyan
& npx.cmd --yes wrangler@4.151.3 pages deploy $siteDirectory --project-name $projectName --branch main
if ($LASTEXITCODE -ne 0) {
    throw 'Cloudflare Pages deployment failed.'
}
