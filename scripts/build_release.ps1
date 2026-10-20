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
if (-not (Test-Path -LiteralPath (Join-Path $repo 'app/android/key.properties'))) {
  throw 'A release signing configuration is required at app/android/key.properties.'
}
$settings = Get-Content -LiteralPath $settingsFile | ConvertFrom-StringData
if (-not $settings.SUPABASE_URL -or -not $settings.SUPABASE_PUBLISHABLE_KEY) {
  throw 'Supabase URL and publishable key are required.'
}
if (-not (Test-Path -LiteralPath $FlutterExe) -or -not (Test-Path -LiteralPath $AppPath)) {
  throw 'Flutter SDK or app path unavailable.'
}
if (Test-Path -LiteralPath 'E:\android_sdk_tcz') {
  $env:ANDROID_SDK_ROOT = 'E:\android_sdk_tcz'
  $env:ANDROID_HOME = 'E:\android_sdk_tcz'
}
if (Test-Path -LiteralPath 'E:\jdk_tcz') { $env:JAVA_HOME = 'E:\jdk_tcz' }

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
    '--dart-define', "SUPABASE_PUBLISHABLE_KEY=$($settings.SUPABASE_PUBLISHABLE_KEY)"
  )
  & $FlutterExe build apk --release @defines
  if ($LASTEXITCODE -ne 0) { throw 'Signed APK build failed' }
  & $FlutterExe build web --release @defines
  if ($LASTEXITCODE -ne 0) { throw 'Flutter web build failed' }
  $apk = Join-Path $AppPath 'build/app/outputs/flutter-apk/app-release.apk'
  $downloads = Join-Path $AppPath 'build/web/downloads'
  New-Item -ItemType Directory -Path $downloads -Force | Out-Null
  $publishedApk = Join-Path $downloads 'pointage-tcz.apk'
  Copy-Item -LiteralPath $apk -Destination $publishedApk -Force
  $hash = (Get-FileHash -LiteralPath $publishedApk -Algorithm SHA256).Hash.ToLowerInvariant()
  Set-Content -LiteralPath (Join-Path $downloads 'SHA256SUMS.txt') -Value "$hash  pointage-tcz.apk" -Encoding ascii
  $site = Join-Path $repo 'site'
  New-Item -ItemType Directory -Path $site -Force | Out-Null
  Copy-Item -Path (Join-Path $AppPath 'build/web/*') -Destination $site -Recurse -Force
  [pscustomobject]@{ WebDirectory=$site; Apk=(Join-Path $site 'downloads/pointage-tcz.apk'); Sha256=$hash }
} finally {
  Pop-Location
}
