import 'dart:convert';
import 'dart:io';

import '../config/self_setup_config.dart';
import '../utils/json_file_store.dart';

class StartupTaskService {
  StartupTaskService({
    required this.store,
    this.taskName = SelfSetupConfig.scheduledTaskName,
  });

  final JsonFileStore store;
  final String taskName;

  Future<bool> isInstalled() async {
    if (!Platform.isWindows) return false;
    try {
      final result =
          await Process.run('schtasks.exe', ['/Query', '/TN', taskName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> ensureInstalledPromptOnce() async {
    if (!SelfSetupConfig.autoLaunchInstallerOnStart || !Platform.isWindows) {
      return;
    }
    if (await isInstalled()) return;
    if (await _recentlyAttempted()) return;
    await requestInstallForAllUsers();
  }

  Future<void> requestInstallForAllUsers() async {
    await _markAttempted();

    final scriptFile = File('${store.dir.path}\\install_startup_task.ps1');
    await scriptFile.writeAsString(_buildInstallScript(), encoding: utf8);

    final safeScript = scriptFile.path.replaceAll("'", "''");
    final launcher = '''
Start-Process -FilePath 'powershell.exe' -Verb RunAs -WindowStyle Hidden -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-File',
  '$safeScript'
)
''';

    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', launcher],
      runInShell: false,
    );
    if (result.exitCode != 0) {
      throw StateError(
        'تعذر طلب صلاحية المسؤول لتثبيت التشغيل التلقائي: ${result.stderr}',
      );
    }
  }

  Future<bool> _recentlyAttempted() async {
    try {
      final file = File('${store.dir.path}\\startup_task_attempt.json');
      if (!await file.exists()) return false;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final attemptedAt =
          DateTime.tryParse(data['attemptedAt']?.toString() ?? '');
      if (attemptedAt == null) return false;
      return DateTime.now().difference(attemptedAt).inMinutes < 30;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAttempted() async {
    final file = File('${store.dir.path}\\startup_task_attempt.json');
    await file.writeAsString(
      jsonEncode({'attemptedAt': DateTime.now().toIso8601String()}),
      encoding: utf8,
      flush: true,
    );
  }

  String _buildInstallScript() {
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final name = taskName.replaceAll("'", "''");
    final workingDir =
        File(Platform.resolvedExecutable).parent.path.replaceAll("'", "''");
    return '''
\$ErrorActionPreference = 'Stop'
\$taskName = '$name'
\$exe = '$exe'
\$workingDir = '$workingDir'
\$logDir = Join-Path \$env:APPDATA 'KiomPcAgent'
New-Item -ItemType Directory -Force -Path \$logDir | Out-Null
\$log = Join-Path \$logDir 'startup_task_install.log'

function Write-KiomLog([string]\$message) {
  "[\$(Get-Date -Format o)] \$message" | Add-Content -LiteralPath \$log -Encoding UTF8
}

Write-KiomLog "Installing startup task for all interactive users. EXE=\$exe"

\$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not \$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Administrator permission is required.'
}

\$action = New-ScheduledTaskAction -Execute \$exe -Argument '--background' -WorkingDirectory \$workingDir
\$trigger = New-ScheduledTaskTrigger -AtLogOn
\$principal = New-ScheduledTaskPrincipal -GroupId 'BUILTIN\\Users' -RunLevel Highest
\$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 30)
Register-ScheduledTask -TaskName \$taskName -Action \$action -Trigger \$trigger -Principal \$principal -Settings \$settings -Force | Out-Null
Start-ScheduledTask -TaskName \$taskName
Write-KiomLog 'Startup task installed and started.'
''';
  }
}
