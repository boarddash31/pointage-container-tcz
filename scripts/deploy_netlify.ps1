$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

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

$token = if ($env:NETLIFY_AUTH_TOKEN) { $env:NETLIFY_AUTH_TOKEN } else { 'nfc_Cw3TmmPSkf4TXAKw8NUjiWqdjdoi73JT5cd5' }
$siteId = if ($env:NETLIFY_SITE_ID) { $env:NETLIFY_SITE_ID } else { '4f8fd024-ea53-4a85-83c0-faeac73a04f6' }

$sourceDir = "$repoRoot\site"
if (-not (Test-Path "$sourceDir\index.html")) {
    $sourceDir = "$repoRoot\app\build\web"
}
$zipPath = "$repoRoot\site_deploy.zip"

if (Test-Path $zipPath) {
    Remove-Item -Force $zipPath
}

Write-Host "Creating archive from $sourceDir with POSIX forward slashes..."
$zip = [System.IO.Compression.ZipFile]::Open($zipPath, [System.IO.Compression.ZipArchiveMode]::Create)

$files = Get-ChildItem -Path $sourceDir -Recurse -File
$baseLen = $sourceDir.TrimEnd('\').Length + 1

foreach ($file in $files) {
    $relPath = $file.FullName.Substring($baseLen).Replace('\', '/')
    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $zip,
        $file.FullName,
        $relPath,
        [System.IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
}

$zip.Dispose()
$entryCount = $files.Count
Write-Host "Archive created successfully with $entryCount files."

Write-Host "Uploading to Netlify site $siteId..."
$responseFile = "$repoRoot\deploy_resp.json"
if (Test-Path $responseFile) { Remove-Item -Force $responseFile }
curl.exe -k -s -S --output "$responseFile" `
    -H "Content-Type: application/zip" `
    -H "Authorization: Bearer $token" `
    --data-binary "@$zipPath" `
    "https://api.netlify.com/api/v1/sites/$siteId/deploys"

if (-not (Test-Path $responseFile)) {
    throw "Netlify API failed to produce response file"
}
$result = Get-Content -Raw -Path $responseFile
Remove-Item -Force $responseFile -ErrorAction SilentlyContinue

$deployObj = $result | ConvertFrom-Json
if (-not $deployObj.id) {
    throw "Netlify API error: $result"
}
$deployId = $deployObj.id
Write-Host "Deploy submitted: ID = $deployId, State = $($deployObj.state)"

# Poll until ready or error
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 3
    $check = curl.exe -k -s -H "Authorization: Bearer $token" "https://api.netlify.com/api/v1/sites/$siteId/deploys/$deployId"
    $checkObj = $check | ConvertFrom-Json
    Write-Host "Deploy status: $($checkObj.state)"
    if ($checkObj.state -eq 'ready') {
        Write-Host ">>> NETLIFY DEPLOY READY!" -ForegroundColor Green
        Write-Host "SSL URL: $($checkObj.ssl_url)" -ForegroundColor Cyan
        break
    }
    if ($checkObj.state -eq 'error') {
        throw "Deploy error: $($checkObj.error_message)"
    }
}
