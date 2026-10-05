param(
    [string]$InstallDir = "C:\Program Files\KIOM\PC Agent",
    [string]$TaskName = "KIOM PC Agent",
    [switch]$NoBuild
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "KIOM: requesting Administrator permission..."
        $args = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        if ($NoBuild) { $args += " -NoBuild" }
        Start-Process powershell.exe -Verb RunAs -ArgumentList $args
        exit 0
    }
}

function Write-KiomLog([string]$Message) {
    $logDir = "C:\ProgramData\KIOM\Logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -Path (Join-Path $logDir "install.log") -Value $line -Encoding UTF8
    Write-Host $Message
}

Assert-Admin

$ScriptDir = Split-Path -Parent $PSCommandPath
$ProjectRoot = Split-Path -Parent $ScriptDir
Set-Location $ProjectRoot

Write-KiomLog "Starting KIOM PC Agent installation..."
Write-KiomLog "Project root: $ProjectRoot"

$ReleaseDir = Join-Path $ProjectRoot "build\windows\x64\runner\Release"

if (-not $NoBuild) {
    if (Test-Path (Join-Path $ProjectRoot "pubspec.yaml")) {
        Write-KiomLog "Building Flutter Windows release..."
        flutter build windows
    } else {
        Write-KiomLog "pubspec.yaml not found. Skipping build."
    }
}

if (-not (Test-Path $ReleaseDir)) {
    throw "Release folder not found: $ReleaseDir. Run flutter build windows first, or run this installer from the Flutter project root."
}

Write-KiomLog "Creating install directory: $InstallDir"
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

Write-KiomLog "Copying release files..."
Copy-Item -Path "$ReleaseDir\*" -Destination $InstallDir -Recurse -Force

if (Test-Path "$ProjectRoot\config") {
    Write-KiomLog "Copying config folder..."
    New-Item -ItemType Directory -Force -Path "$InstallDir\config" | Out-Null
    Copy-Item -Path "$ProjectRoot\config\*" -Destination "$InstallDir\config" -Recurse -Force
}

$ExeCandidates = Get-ChildItem -Path $InstallDir -Filter "*.exe" -File | Where-Object { $_.Name -notlike "*unins*" }
$ExePath = ($ExeCandidates | Where-Object { $_.Name -eq "kiom_pc_agent.exe" } | Select-Object -First 1).FullName
if (-not $ExePath) { $ExePath = ($ExeCandidates | Select-Object -First 1).FullName }
if (-not $ExePath -or -not (Test-Path $ExePath)) {
    throw "Could not find KIOM Agent exe in $InstallDir"
}

Write-KiomLog "Agent exe: $ExePath"

Write-KiomLog "Creating scheduled task: $TaskName"
$Action = New-ScheduledTaskAction -Execute $ExePath -Argument "--background" -WorkingDirectory $InstallDir
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -MultipleInstances IgnoreNew

$UserId = "$env:USERDOMAIN\$env:USERNAME"
$Principal = New-ScheduledTaskPrincipal `
    -UserId $UserId `
    -LogonType Interactive `
    -RunLevel Highest

$Task = New-ScheduledTask `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Principal $Principal

Register-ScheduledTask -TaskName $TaskName -InputObject $Task -Force | Out-Null

Write-KiomLog "Starting scheduled task..."
Start-ScheduledTask -TaskName $TaskName

Write-KiomLog "KIOM PC Agent installed successfully. It will start at Windows logon with highest privileges."
Write-Host ""
Write-Host "Done. Install path: $InstallDir"
Write-Host "Scheduled task: $TaskName"
Write-Host "Logs: C:\ProgramData\KIOM\Logs\install.log"
