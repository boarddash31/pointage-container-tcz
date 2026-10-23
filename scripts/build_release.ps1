param(
  [string]$FlutterExe = 'E:\flutter_sdk_tcz\bin\flutter.bat',
  [string]$AppPath = 'E:\pointage_tcz'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$settingsFile = Join-Path $repo '.env.local'
if (-not (Test-Path -LiteralPath $settingsFile)) {
  throw 'Create ignored .env.local with SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.'
}
$settings = Get-Content -LiteralPath $settingsFile | ConvertFrom-StringData
if (-not $settings.SUPABASE_URL -or -not $settings.SUPABASE_PUBLISHABLE_KEY -or -not $settings.AUTH_SITE_URL) {
  throw 'Supabase URL, publishable key and public Auth site URL are required.'
}
if (-not (Test-Path -LiteralPath $FlutterExe) -or -not (Test-Path -LiteralPath $AppPath)) {
  throw 'Flutter SDK or app path unavailable.'
}

Push-Location -LiteralPath $AppPath
try {
  & $FlutterExe pub get
  if ($LASTEXITCODE -ne 0) { throw 'Flutter pub get failed' }
  & $FlutterExe analyze --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Flutter analyze failed' }
  & $FlutterExe test --no-pub
  if ($LASTEXITCODE -ne 0) { throw 'Flutter tests failed' }

  $defines = @(
    '--dart-define', "SUPABASE_URL=$($settings.SUPABASE_URL)",
    '--dart-define', "SUPABASE_PUBLISHABLE_KEY=$($settings.SUPABASE_PUBLISHABLE_KEY)",
    '--dart-define', "AUTH_SITE_URL=$($settings.AUTH_SITE_URL)"
  )
  & $FlutterExe build web --release --no-wasm-dry-run @defines
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }

  $web = Join-Path $AppPath 'build/web'
  $site = Join-Path $repo 'site'
  if (-not (Test-Path -LiteralPath (Join-Path $web 'index.html'))) {
    throw 'Flutter did not produce a web index.html.'
  }
  New-Item -ItemType Directory -Path $site -Force | Out-Null
  Copy-Item -Path (Join-Path $web '*') -Destination $site -Recurse -Force

  # The public site is web-only. Remove files left by older APK-enabled builds.
  $downloads = Join-Path $site 'downloads'
  foreach ($name in @('pointage-tcz.apk', 'SHA256SUMS.txt')) {
    $artifact = Join-Path $downloads $name
    if (Test-Path -LiteralPath $artifact -PathType Leaf) {
      Remove-Item -LiteralPath $artifact -Force
    }
  }

  [pscustomobject]@{ WebDirectory=$site; EntryPoint=(Join-Path $site 'index.html'); ApkPublished=$false }
} finally {
  Pop-Location
}
