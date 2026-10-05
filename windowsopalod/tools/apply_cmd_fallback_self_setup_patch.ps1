$ErrorActionPreference = "Stop"

$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$agentApp = Join-Path $root "lib\core\agent_app.dart"

if (!(Test-Path $agentApp)) {
  Write-Host "[ERROR] Cannot find lib\core\agent_app.dart"
  exit 1
}

$text = Get-Content $agentApp -Raw -Encoding UTF8

$importLine = "import '../services/self_setup_cmd_fallback_service.dart';"
if ($text -notlike "*self_setup_cmd_fallback_service.dart*") {
  $text = $text -replace "((?:import\s+['""][^'""]+['""];\s*)+)", "`$1$importLine`r`n"
}

$call = "    await SelfSetupCmdFallbackService().ensureInstalled();"
if ($text -notlike "*SelfSetupCmdFallbackService().ensureInstalled()*") {
  $pattern = "(Future<void>\s+start\s*\(\)\s+async\s*\{\s*)"
  if ($text -match $pattern) {
    $text = [regex]::Replace($text, $pattern, "`$1`r`n$call`r`n", 1)
  } else {
    Write-Host "[ERROR] Could not find: Future<void> start() async {"
    Write-Host "Add this manually inside start():"
    Write-Host $call
    exit 1
  }
}

Set-Content $agentApp $text -Encoding UTF8

Write-Host "Done. CMD fallback self setup was injected into lib\core\agent_app.dart"
Write-Host "Now run:"
Write-Host "flutter clean"
Write-Host "flutter pub get"
Write-Host "flutter run -d windows"