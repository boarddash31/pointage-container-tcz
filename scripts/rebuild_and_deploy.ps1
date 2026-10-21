$ErrorActionPreference = 'Stop'

$FlutterExe = 'E:\flutter_sdk_tcz\bin\flutter.bat'
$AppPath = 'E:\pointage_repo\app'
$defines = @(
  '--dart-define', 'SUPABASE_URL=https://iparzfqxopcvwqelxlad.supabase.co',
  '--dart-define', 'SUPABASE_PUBLISHABLE_KEY=sb_publishable_AgyGT1cfJz9gkXTpVrLsXg_B3VNWHGs',
  '--dart-define', 'AUTH_SITE_URL=https://pointage-tcz-test.netlify.app'
)

Write-Host "Building Flutter Web..."
Push-Location $AppPath
try {
  & $FlutterExe build web --release @defines
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
} finally {
  Pop-Location
}

# Copy _headers and _redirects
Copy-Item -LiteralPath "$AppPath\web\_headers" -Destination "$AppPath\build\web\_headers" -Force
Copy-Item -LiteralPath "$AppPath\web\_redirects" -Destination "$AppPath\build\web\_redirects" -Force

# Run deployment
& "$PSScriptRoot\deploy_netlify.ps1"
