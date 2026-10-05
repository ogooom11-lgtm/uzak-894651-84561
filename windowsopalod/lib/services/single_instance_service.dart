import 'dart:io';

import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';

class SingleInstanceService {
  SingleInstanceService({required this.store});

  final JsonFileStore store;

  Future<void> keepOnlyCurrentProcess() async {
    if (!Platform.isWindows) return;

    try {
      final currentPid = pid;
      final exePath = Platform.resolvedExecutable;
      final exeName = File(exePath).uri.pathSegments.last.toLowerCase();
      final lockFile = File('${store.dir.path}\\agent_instance.json');

      if (await lockFile.exists()) {
        final oldPid = int.tryParse(await lockFile.readAsString());
        if (oldPid != null && oldPid != currentPid) {
          await _killPid(oldPid);
        }
      }

      await _killSameExecutable(exePath, exeName, currentPid);
      await lockFile.writeAsString(currentPid.toString(), flush: true);
    } catch (e, st) {
      await store.appendLog('single_instance_error', e.toString(), {
        'stack': st.toString(),
      });
    }
  }

  Future<void> _killPid(int processId) async {
    await SafeProcessRunner.run(
      'taskkill.exe',
      ['/PID', processId.toString(), '/F'],
      runInShell: false,
      timeout: SafeProcessRunner.shortTimeout,
    );
  }

  Future<void> _killSameExecutable(
    String exePath,
    String exeName,
    int currentPid,
  ) async {
    final safePath = exePath.replaceAll("'", "''");
    final safeName = exeName.replaceAll("'", "''");
    final script = '''
\$currentPid = $currentPid
\$exePath = '$safePath'.ToLowerInvariant()
\$exeName = '$safeName'.ToLowerInvariant()
Get-CimInstance Win32_Process | Where-Object {
  \$_.ProcessId -ne \$currentPid -and (
    (\$_.ExecutablePath -and \$_.ExecutablePath.ToLowerInvariant() -eq \$exePath) -or
    (\$_.Name -and \$_.Name.ToLowerInvariant() -eq \$exeName)
  )
} | ForEach-Object {
  try { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue } catch {}
}
''';
    await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(seconds: 8),
    );
  }
}
