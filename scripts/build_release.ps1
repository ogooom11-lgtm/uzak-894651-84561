$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host 'Running flutter pub get...' -ForegroundColor Cyan
flutter pub get

Write-Host 'Building Windows release...' -ForegroundColor Cyan
flutter build windows --release

$Out = Join-Path $Root 'build\windows\x64\runner\Release'
$ConfigSource = Join-Path $Root 'config\firebase_config.json'
$ConfigOutDir = Join-Path $Out 'config'
$ConfigTarget = Join-Path $ConfigOutDir 'firebase_config.json'

if (-not (Test-Path -LiteralPath $Out)) {
  throw "Release folder not found: $Out"
}

if (-not (Test-Path -LiteralPath $ConfigSource)) {
  throw "Missing config file: $ConfigSource`nCreate it from config\firebase_config.example.json first."
}

New-Item -ItemType Directory -Force -Path $ConfigOutDir | Out-Null
Copy-Item -LiteralPath $ConfigSource -Destination $ConfigTarget -Force

$ScriptsTarget = Join-Path $Out 'scripts'
New-Item -ItemType Directory -Force -Path $ScriptsTarget | Out-Null
Copy-Item -LiteralPath (Join-Path $Root 'scripts\register_startup_admin.ps1') -Destination $ScriptsTarget -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'Build completed successfully.' -ForegroundColor Green
Write-Host "Release folder: $Out" -ForegroundColor Yellow
Write-Host "Copied config to: $ConfigTarget" -ForegroundColor Yellow
Write-Host 'Important: run/copy the whole Release folder, not the exe alone.' -ForegroundColor Magenta
