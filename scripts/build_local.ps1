$ErrorActionPreference = 'Stop'

$FlutterExe = 'E:\flutter_sdk_tcz\bin\flutter.bat'
$AppPath = 'E:\pointage_repo\app'
$defines = @(
  '--dart-define', 'SUPABASE_URL=https://iparzfqxopcvwqelxlad.supabase.co',
  '--dart-define', 'SUPABASE_PUBLISHABLE_KEY=sb_publishable_AgyGT1cfJz9gkXTpVrLsXg_B3VNWHGs',
  '--dart-define', 'AUTH_SITE_URL=http://localhost:8085'
)

Write-Host "Building Flutter Web for Local Server..."
Push-Location $AppPath
try {
  & $FlutterExe build web --release @defines
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
} finally {
  Pop-Location
}

# Copy _headers and _redirects
if (Test-Path "$AppPath\web\_headers") {
  Copy-Item -LiteralPath "$AppPath\web\_headers" -Destination "$AppPath\build\web\_headers" -Force
}
if (Test-Path "$AppPath\web\_redirects") {
  Copy-Item -LiteralPath "$AppPath\web\_redirects" -Destination "$AppPath\build\web\_redirects" -Force
}

# Sync to site/ for local server (http://localhost:8085)
$SiteDir = 'E:\pointage_repo\site'
if (-not (Test-Path $SiteDir)) { New-Item -ItemType Directory -Path $SiteDir -Force | Out-Null }
Copy-Item -Path "$AppPath\build\web\*" -Destination $SiteDir -Recurse -Force
Write-Host "Successfully built and synced to $SiteDir (http://localhost:8085)"
