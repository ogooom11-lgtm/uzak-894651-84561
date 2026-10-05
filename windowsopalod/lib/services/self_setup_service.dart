import 'dart:async';
import 'dart:io';

import '../config/self_setup_config.dart';

class SelfSetupService {
  static Future<bool> ensureInstalledOrLaunchInstaller() async {
    if (!SelfSetupConfig.autoLaunchInstallerOnStart) {
      return false;
    }

    if (!Platform.isWindows) {
      return false;
    }

    if (Platform.environment['KIOM_DISABLE_SELF_SETUP'] == '1') {
      stdout.writeln('SELF_SETUP: disabled by KIOM_DISABLE_SELF_SETUP=1');
      return false;
    }

    final installed = await isScheduledTaskInstalled();
    if (installed) {
      stdout.writeln('SELF_SETUP: scheduled task already installed.');
      return false;
    }

    final installer = await _findInstallerScript();
    if (installer == null) {
      stdout.writeln(
          'SELF_SETUP: installer script not found: tools\\install_kiom_agent.ps1');
      return false;
    }

    stdout.writeln('SELF_SETUP: scheduled task is missing.');
    stdout.writeln(
        'SELF_SETUP: opening PowerShell as Administrator to install KIOM Agent...');
    stdout.writeln('SELF_SETUP_INSTALLER=${installer.path}');

    await _launchElevatedPowerShell(installer.path);

    if (SelfSetupConfig.exitCurrentProcessAfterLaunchingInstaller) {
      stdout.writeln(
          'SELF_SETUP: installer was launched. Closing current process to avoid duplicates.');
      await Future<void>.delayed(const Duration(milliseconds: 700));
      exit(0);
    }

    return true;
  }

  static Future<bool> isScheduledTaskInstalled() async {
    final taskName =
        _escapePowerShellSingleQuoted(SelfSetupConfig.scheduledTaskName);

    final script = '''
\$task = Get-ScheduledTask -TaskName '$taskName' -ErrorAction SilentlyContinue
if (\$null -ne \$task) {
  Write-Output 'INSTALLED'
} else {
  Write-Output 'NOT_INSTALLED'
}
''';

    try {
      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-Command',
          script,
        ],
        runInShell: false,
      ).timeout(const Duration(seconds: 10));

      final output = result.stdout.toString().trim();
      return output.contains('INSTALLED');
    } catch (e) {
      stdout.writeln('SELF_SETUP: failed to check scheduled task: $e');
      return false;
    }
  }

  static Future<File?> _findInstallerScript() async {
    Directory current = Directory.current;

    for (var i = 0; i < 8; i++) {
      final candidate = File('${current.path}\\tools\\install_kiom_agent.ps1');
      if (await candidate.exists()) {
        return candidate;
      }

      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    final executableDir = File(Platform.resolvedExecutable).parent;
    current = executableDir;

    for (var i = 0; i < 8; i++) {
      final candidate = File('${current.path}\\tools\\install_kiom_agent.ps1');
      if (await candidate.exists()) {
        return candidate;
      }

      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }

    return null;
  }

  static Future<void> _launchElevatedPowerShell(String installerPath) async {
    final safeInstallerPath = _escapePowerShellSingleQuoted(installerPath);

    final script = '''
\$installerPath = '$safeInstallerPath'
Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-NoExit',
  '-File',
  \$installerPath
)
''';

    final result = await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      runInShell: false,
    );

    if (result.exitCode != 0) {
      final err = result.stderr.toString().trim();
      throw StateError('Failed to launch elevated installer. $err');
    }
  }

  static String _escapePowerShellSingleQuoted(String value) {
    return value.replaceAll("'", "''");
  }
}
