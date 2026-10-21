$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$sourceDir = 'E:\pointage_repo\app\build\web'
$zipPath = 'E:\pointage_repo\site_deploy.zip'

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

$entryCount = $zip.Entries.Count
$zip.Dispose()

Write-Host "Archive created successfully with $entryCount entries."

$token = 'nfc_Cw3TmmPSkf4TXAKw8NUjiWqdjdoi73JT5cd5'
$siteId = '4f8fd024-ea53-4a85-83c0-faeac73a04f6'

Write-Host "Uploading to Netlify site $siteId..."
$result = curl.exe -s -X POST `
    -H "Content-Type: application/zip" `
    -H "Authorization: Bearer $token" `
    --data-binary "@$zipPath" `
    "https://api.netlify.com/api/v1/sites/$siteId/deploys"

$deployObj = $result | ConvertFrom-Json
$deployId = $deployObj.id
Write-Host "Deploy submitted: ID = $deployId, State = $($deployObj.state)"

# Poll until ready or error
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 3
    $check = curl.exe -s -H "Authorization: Bearer $token" "https://api.netlify.com/api/v1/sites/$siteId/deploys/$deployId"
    $checkObj = $check | ConvertFrom-Json
    Write-Host "Deploy status: $($checkObj.state)"
    if ($checkObj.state -eq 'ready') {
        Write-Host "DEPLOY READY!"
        Write-Host "SSL URL: $($checkObj.ssl_url)"
        Write-Host "Summary: $($checkObj.summary | ConvertTo-Json -Compress)"
        break
    }
    if ($checkObj.state -eq 'error') {
        throw "Deploy error: $($checkObj.error_message)"
    }
}
