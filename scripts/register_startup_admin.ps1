# يسجل KIOM PC Agent ليعمل مع دخول Windows بصلاحية عالية.
# شغله Run as Administrator بعد نجاح build_release.ps1.
$ErrorActionPreference = 'Stop'

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'ERROR: شغل هذا الملف Run as Administrator' -ForegroundColor Red
  exit 1
}

$ScriptDir = $PSScriptRoot
$Parent = Split-Path -Parent $ScriptDir
$ProjectRoot = Split-Path -Parent $ScriptDir

$Candidate1 = Join-Path $Parent 'windowsopalod.exe'
$Candidate2 = Join-Path $ProjectRoot 'build\windows\x64\runner\Release\windowsopalod.exe'

if (Test-Path -LiteralPath $Candidate1) {
  $ExePath = $Candidate1
} elseif (Test-Path -LiteralPath $Candidate2) {
  $ExePath = $Candidate2
} else {
  throw "EXE not found. Checked:`n$Candidate1`n$Candidate2"
}

$WorkingDir = Split-Path -Parent $ExePath
$TaskName = 'KiomPcAgent'

try { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue } catch {}
try { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue } catch {}

$Action = New-ScheduledTaskAction -Execute $ExePath -WorkingDirectory $WorkingDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$PrincipalTask = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $PrincipalTask -Settings $Settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host 'KiomPcAgent registered and started with highest privileges.' -ForegroundColor Green
Write-Host ('EXE: ' + $ExePath)
