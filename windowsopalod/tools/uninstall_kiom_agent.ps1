param(
    [string]$InstallDir = "C:\Program Files\KIOM\PC Agent",
    [string]$TaskName = "KIOM PC Agent"
)

$ErrorActionPreference = "Stop"

function Assert-Admin {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        exit 0
    }
}

Assert-Admin

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

if (Test-Path $InstallDir) {
    Remove-Item $InstallDir -Recurse -Force
}

Write-Host "KIOM PC Agent uninstalled successfully."
