$ErrorActionPreference = 'Stop'

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter is not on PATH. Install Flutter and reopen PowerShell.'
}
if (-not (Test-Path 'pubspec.yaml')) {
  throw 'Run this script from the LedgerLens project root (the folder containing pubspec.yaml).'
}

$manifest = 'android/app/src/main/AndroidManifest.xml'
$tempManifest = Join-Path $env:TEMP 'ledgerlens-AndroidManifest.xml'
$haveManifest = Test-Path $manifest
if ($haveManifest) { Copy-Item $manifest $tempManifest -Force }
if (Test-Path 'android') { Remove-Item 'android' -Recurse -Force }

flutter create --platforms=android --org com.ledgerlens --project-name ledgerlens .
if ($LASTEXITCODE -ne 0) { throw 'flutter create failed.' }

# Remove the default widget test if flutter create added it (it references MyApp).
if ((Test-Path 'test/widget_test.dart') -and ((Get-Content 'test/widget_test.dart' -Raw) -match 'MyApp')) {
  Remove-Item 'test/widget_test.dart' -Force
}

# 1. Restore the LedgerLens manifest.
if ($haveManifest) {
  Copy-Item $tempManifest $manifest -Force
  Remove-Item $tempManifest -Force
}

# 2. minSdk 23.
foreach ($gradle in @('android/app/build.gradle.kts', 'android/app/build.gradle')) {
  if (Test-Path $gradle) {
    $content = Get-Content $gradle -Raw
    $content = $content -replace 'minSdk = flutter\.minSdkVersion', 'minSdk = maxOf(flutter.minSdkVersion, 23)'
    $content = $content -replace 'minSdkVersion flutter\.minSdkVersion', 'minSdkVersion 23'
    Set-Content -Path $gradle -Value $content -Encoding utf8
  }
}

# 3. local_auth needs a FragmentActivity.
$main = Get-ChildItem 'android/app/src/main' -Recurse -Filter 'MainActivity.kt' | Select-Object -First 1
if ($main) {
  $package = (Get-Content $main.FullName | Where-Object { $_ -match '^package ' } | Select-Object -First 1)
  $kotlin = "$package`n`nimport io.flutter.embedding.android.FlutterFragmentActivity`n`nclass MainActivity : FlutterFragmentActivity()`n"
  Set-Content -Path $main.FullName -Value $kotlin -Encoding utf8
}

# 4. AppCompat launch/normal themes for local_auth dialogs.
Get-ChildItem 'android/app/src/main/res' -Recurse -Filter 'styles.xml' | ForEach-Object {
  $text = Get-Content $_.FullName -Raw
  $text = $text -replace '@android:style/Theme\.Light\.NoTitleBar', 'Theme.AppCompat.Light.NoActionBar'
  $text = $text -replace '@android:style/Theme\.Black\.NoTitleBar', 'Theme.AppCompat.NoActionBar'
  Set-Content -Path $_.FullName -Value $text -Encoding utf8
}

# 5. Release signing (needs Python 3; skipped otherwise).
if (Get-Command python -ErrorAction SilentlyContinue) { python scripts/patch_signing.py }

Write-Host 'Android scaffold generated and patched.' -ForegroundColor Green
Write-Host 'Next: flutter pub get; dart run build_runner build --delete-conflicting-outputs; flutter analyze; flutter test'
