#define MyAppName "Kiom PC Agent"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "Kiom"
#define MyAppExeName "windowsopalod.exe"

[Setup]
AppId={{8D4090A6-2A2D-4E31-9AF5-4B3F4B5F1111}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={autopf}\Kiom PC Agent
DefaultGroupName={#MyAppName}
OutputDir=installer_output
OutputBaseFilename=KiomPcAgent_Setup
Compression=lzma
SolidCompression=yes
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\scripts\register_startup_admin.ps1"""; Flags: runhidden waituntilterminated

[Icons]
Name: "{group}\Kiom PC Agent"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\Kiom PC Agent"; Filename: "{app}\{#MyAppExeName}"

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""Unregister-ScheduledTask -TaskName 'KiomPcAgent' -Confirm:$false -ErrorAction SilentlyContinue"""; Flags: runhidden waituntilterminated
