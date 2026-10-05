$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$AgentAppPath = Join-Path $ProjectRoot 'lib\core\agent_app.dart'

if (-not (Test-Path $AgentAppPath)) {
  throw "agent_app.dart not found: $AgentAppPath"
}

$text = Get-Content $AgentAppPath -Raw

if ($text -notmatch "self_setup_service\.dart") {
  $text = "import '../services/self_setup_service.dart';`r`n" + $text
  Write-Host 'Added SelfSetupService import.'
} else {
  Write-Host 'SelfSetupService import already exists.'
}

if ($text -notmatch "SelfSetupService\.ensureInstalledOrLaunchInstaller") {
  $pattern = "(Future\s*<\s*void\s*>\s+start\s*\(\s*\)\s*async\s*\{)"
  if ($text -match $pattern) {
    $replacement = "`$1`r`n    await SelfSetupService.ensureInstalledOrLaunchInstaller();"
    $text = [regex]::Replace($text, $pattern, $replacement, 1)
    Write-Host 'Inserted self setup call into start().' 
  } else {
    throw 'Could not find: Future<void> start() async { in lib\core\agent_app.dart. Add this line manually near the start of KiomPcAgentApp.start(): await SelfSetupService.ensureInstalledOrLaunchInstaller();'
  }
} else {
  Write-Host 'Self setup call already exists.'
}

Set-Content -Path $AgentAppPath -Value $text -Encoding UTF8
Write-Host 'Done.'
