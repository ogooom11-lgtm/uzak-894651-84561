import 'dart:async';
import 'dart:io';

import '../config/agent_config.dart';
import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';

class SelfDefenseFileProtectionService {
  SelfDefenseFileProtectionService({
    required this.deviceId,
    required this.config,
    required this.store,
  });

  final String deviceId;
  final AgentConfig config;
  final JsonFileStore store;

  Timer? _watchdogTimer;
  bool _isProtectionActive = true;

  bool get isProtectionActive => _isProtectionActive;

  Future<void> start() async {
    final enabled = store.get<bool>('self_defense_protection_enabled') ?? true;
    _isProtectionActive = enabled;

    if (enabled) {
      await enforceFileProtection();
    }

    // Periodic self-healing watchdog every 5 minutes to ensure files remain locked and protected
    _watchdogTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (_isProtectionActive) {
        await enforceFileProtection();
      }
    });
  }

  void stop() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// Get list of all critical agent directories and file paths
  List<String> getProtectedPaths() {
    final paths = <String>{};

    try {
      // 1. AppData KiomPcAgent folder
      final appData = Platform.environment['APPDATA'] ?? '';
      if (appData.isNotEmpty) {
        paths.add('$appData\\KiomPcAgent');
      }

      // 2. LocalAppData KiomPcAgent folder
      final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';
      if (localAppData.isNotEmpty) {
        paths.add('$localAppData\\KiomPcAgent');
      }

      // 3. Current running Executable Directory
      final exePath = Platform.resolvedExecutable;
      if (exePath.isNotEmpty) {
        final exeDir = File(exePath).parent.path;
        if (!exeDir.toLowerCase().contains('windows') &&
            !exeDir.toLowerCase().contains('system32')) {
          paths.add(exeDir);
        }
      }

      // 4. Store directory
      paths.add(store.dir.path);
    } catch (_) {}

    return paths.where((p) => p.trim().isNotEmpty && Directory(p).existsSync()).toList();
  }

  /// Enforce Windows NTFS Deny Delete ACLs and System attributes
  /// so files CANNOT be deleted even when the application process is closed.
  Future<Map<String, dynamic>> enforceFileProtection() async {
    if (!Platform.isWindows) {
      return {'success': false, 'message': 'File protection requires Windows OS'};
    }

    final protectedPaths = getProtectedPaths();
    final results = <String, bool>{};

    for (final folderPath in protectedPaths) {
      try {
        final escaped = folderPath.replaceAll("'", "''");

        // PowerShell script to apply NTFS Deny Delete permissions and System attributes
        final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$targetDir = '$escaped'

if (Test-Path \$targetDir) {
    # 1. Take initial ownership and grant System/Admin full control
    takeown.exe /F "\$targetDir" /R /D Y | Out-Null
    icacls.exe "\$targetDir" /grant:r "NT AUTHORITY\\SYSTEM":(OI)(CI)(F) "BUILTIN\\Administrators":(OI)(CI)(F) /T /C /Q | Out-Null
    
    # 2. Add Deny-Delete rules for standard Users and Everyone (Blocks Delete, Delete Subfolders/Files, Change Permissions)
    icacls.exe "\$targetDir" /deny "BUILTIN\\Users":(OI)(CI)(DE,DC,WDAC,WO) /T /C /Q | Out-Null
    icacls.exe "\$targetDir" /deny "Everyone":(OI)(CI)(DE,DC,WDAC,WO) /T /C /Q | Out-Null

    # 3. Mark all critical files as System + Read-Only
    attrib.exe +S +R "\$targetDir\\*.*" /S /D | Out-Null
}
''';

        final res = await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 15));
        results[folderPath] = res.exitCode == 0;
      } catch (e) {
        results[folderPath] = false;
      }
    }

    // Register persistent Windows Task Scheduler Self-Healing Watchdog
    await _registerPersistentWatchdogTask();

    _isProtectionActive = true;
    await store.set('self_defense_protection_enabled', true);
    await store.appendLog('self_defense_enforced', 'تم تعزيز حماية ملفات التطبيق ضد الحذف والتعديل', {
      'protectedPaths': protectedPaths,
      'results': results,
    });

    return {
      'success': true,
      'message': 'تم تفعيل حماية ملفات التطبيق من الحذف بنجاح (حتى لو أُغلق البرنامج)',
      'protectedPaths': protectedPaths,
      'status': 'protected',
    };
  }

  /// Temporarily unlock files if maintenance/update is requested
  Future<Map<String, dynamic>> unlockFileProtection() async {
    if (!Platform.isWindows) {
      return {'success': false, 'message': 'Requires Windows OS'};
    }

    final protectedPaths = getProtectedPaths();
    for (final folderPath in protectedPaths) {
      try {
        final escaped = folderPath.replaceAll("'", "''");
        final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$targetDir = '$escaped'

if (Test-Path \$targetDir) {
    icacls.exe "\$targetDir" /remove:d "BUILTIN\\Users" /T /C /Q | Out-Null
    icacls.exe "\$targetDir" /remove:d "Everyone" /T /C /Q | Out-Null
    attrib.exe -S -R "\$targetDir\\*.*" /S /D | Out-Null
}
''';
        await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 15));
      } catch (_) {}
    }

    _isProtectionActive = false;
    await store.set('self_defense_protection_enabled', false);
    await store.appendLog('self_defense_unlocked', 'تم إلغاء قفل ملفات التطبيق مؤقتاً', {
      'paths': protectedPaths,
    });

    return {
      'success': true,
      'message': 'تم إلغاء قفل ملفات التطبيق مؤقتاً بنجاح',
      'status': 'unlocked',
    };
  }

  /// Register highest-privilege Windows scheduled task that continuously watches and protects files
  Future<void> _registerPersistentWatchdogTask() async {
    try {
      final exePath = Platform.resolvedExecutable;
      if (exePath.isEmpty || !File(exePath).existsSync()) return;

      final escapedExe = exePath.replaceAll('/', '\\');
      final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$taskName = "KiomAgentSelfDefenseWatchdog"
\$exePath = "$escapedExe"

# Create / Update scheduled task running at system startup with highest run level
schtasks.exe /Create /TN "\$taskName" /TR "`"\$exePath`" --background-service" /SC ONSTART /RL HIGHEST /F | Out-Null
schtasks.exe /Change /TN "\$taskName" /RL HIGHEST | Out-Null
''';
      await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 10));
    } catch (_) {}
  }

  Map<String, dynamic> getStatusReport() {
    return {
      'protectionActive': _isProtectionActive,
      'protectedPaths': getProtectedPaths(),
      'watchdogActive': _watchdogTimer != null && _watchdogTimer!.isActive,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }
}
