import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/agent_config.dart';
import '../models/path_rule.dart';
import '../utils/json_file_store.dart';
import 'dialog_service.dart';
import 'firestore_rest_client.dart';
import 'path_rule_store.dart';
import 'telegram_notifier_service.dart';

class PathGuardService {
  final String deviceId;
  final AgentConfig config;
  final JsonFileStore store;
  final PathRuleStore ruleStore;
  final DialogService dialogs;
  final FirestoreRestClient firestore;
  final TelegramNotifierService? telegram;

  Timer? _timer;
  final Map<String, DateTime> _allowedUntil = {};
  final Map<String, DateTime> _lastPromptAt = {};
  Map<int, String> _lastExplorerPaths = {};

  PathGuardService({
    required this.deviceId,
    required this.config,
    required this.store,
    required this.ruleStore,
    required this.dialogs,
    required this.firestore,
    this.telegram,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: config.scanExplorerEverySeconds),
      (_) => _scan(),
    );
    _scan();
  }

  void stop() => _timer?.cancel();

  Future<void> _scan() async {
    final rules = ruleStore.getRules();
    final windows = await _getExplorerWindows();
    await _writeExplorerPathLogs(windows);
    if (rules.isEmpty) return;

    for (final win in windows) {
      final path = (win['path'] ?? '').toString();
      final hwnd = (win['hwnd'] as num?)?.toInt() ?? 0;

      if (path.isEmpty || hwnd == 0) continue;

      for (final rule in rules) {
        if (!_isInside(path, rule.path)) {
          continue;
        }
        if (_isTemporarilyAllowed(rule.id) ||
            await _isApprovedByPhone(rule, path)) {
          continue;
        }
        if (_recentlyPrompted(rule.id, path)) {
          continue;
        }

        await _handleRule(rule, path, hwnd);
        break;
      }
    }
  }

  Future<void> _writeExplorerPathLogs(
      List<Map<String, dynamic>> windows) async {
    final current = <int, String>{};
    for (final win in windows) {
      final hwnd = (win['hwnd'] as num?)?.toInt() ?? 0;
      final path = (win['path'] ?? '').toString();
      if (hwnd == 0 || path.isEmpty) continue;
      current[hwnd] = path;
    }

    for (final entry in current.entries) {
      final previousPath = _lastExplorerPaths[entry.key];
      if (previousPath == null) {
        await store.appendLog('path_opened', 'تم فتح مسار في Explorer', {
          'path': entry.value,
          'hwnd': entry.key,
          'source': 'explorer',
        });
      } else if (previousPath != entry.value) {
        await store.appendLog('path_changed', 'تم تغيير مسار نافذة Explorer', {
          'oldPath': previousPath,
          'path': entry.value,
          'hwnd': entry.key,
          'source': 'explorer',
        });
      }
    }

    for (final entry in _lastExplorerPaths.entries) {
      if (!current.containsKey(entry.key)) {
        await store.appendLog('path_closed', 'تم إغلاق مسار في Explorer', {
          'path': entry.value,
          'hwnd': entry.key,
          'source': 'explorer',
        });
      }
    }

    _lastExplorerPaths = current;
  }

  bool _isInside(String openedPath, String protectedPath) {
    final a = openedPath.replaceAll('/', '\\').toLowerCase();
    final b = protectedPath.replaceAll('/', '\\').toLowerCase();

    return a == b || a.startsWith(b.endsWith('\\') ? b : '$b\\');
  }

  bool _isTemporarilyAllowed(String ruleId) {
    final until = _allowedUntil[ruleId];
    return until != null && until.isAfter(DateTime.now());
  }

  Future<bool> _isApprovedByPhone(PathRule rule, String openedPath) async {
    final approvals = store.list('pathAccessApprovals');
    var changed = false;
    var allowed = false;
    final now = DateTime.now();
    final remaining = <dynamic>[];

    for (final item in approvals) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final until = DateTime.tryParse((map['until'] ?? '').toString());
      if (until == null || until.isBefore(now)) {
        changed = true;
        continue;
      }

      remaining.add(map);
      final ruleId = (map['ruleId'] ?? '').toString();
      final approvedPath = (map['openedPath'] ?? map['path'] ?? '').toString();
      if (ruleId == rule.id &&
          (approvedPath.isEmpty || _isInside(openedPath, approvedPath))) {
        allowed = true;
      }
    }

    if (changed) {
      await store.set('pathAccessApprovals', remaining);
    }

    return allowed;
  }

  bool _recentlyPrompted(String ruleId, String path) {
    final key = '$ruleId::$path';
    final last = _lastPromptAt[key];

    if (last != null && DateTime.now().difference(last).inSeconds < 5) {
      return true;
    }

    _lastPromptAt[key] = DateTime.now();
    return false;
  }

  Future<void> _handleRule(PathRule rule, String openedPath, int hwnd) async {
    await store.appendLog(
      'path_guard',
      'محاولة فتح مسار محمي',
      {
        'path': openedPath,
        'ruleId': rule.id,
        'lockType': rule.lockType,
      },
    );
    await telegram?.sendMessage(
      'KIOM: محاولة فتح مسار محمي\n'
      'المسار: $openedPath\n'
      'نوع القفل: ${rule.lockType}\n'
      'الجهاز: $deviceId',
    );

    if (rule.lockType == 'blocked') {
      await dialogs.showWarning(
        title: 'KIOM Protection',
        message: 'ممنوع فتح هذا المجلد أو المسار:\n$openedPath',
      );

      await _closeExplorerWindow(hwnd);
      return;
    }

    if (rule.lockType == 'password') {
      final password = await dialogs.askPassword(
        title: 'KIOM Protection',
        message:
            'هذا المسار محمي. أدخل كلمة المرور للسماح مؤقتاً:\n$openedPath',
      );

      if (password != null && rule.verifyPassword(password)) {
        _allowedUntil[rule.id] = DateTime.now().add(
          Duration(minutes: config.defaultPasswordAllowMinutes),
        );

        await store.appendLog(
          'path_guard',
          'تم السماح بفتح المسار بكلمة مرور صحيحة',
          {
            'path': openedPath,
            'ruleId': rule.id,
          },
        );

        return;
      }

      await dialogs.showWarning(
        title: 'KIOM Protection',
        message: 'كلمة المرور غير صحيحة. سيتم إغلاق المسار.',
      );

      await _closeExplorerWindow(hwnd);
      return;
    }

    if (rule.lockType == 'permissionRequired') {
      await firestore.createPermissionRequest(
        deviceId: deviceId,
        path: rule.path,
        openedPath: openedPath,
        ruleId: rule.id,
      );
      await telegram?.sendMessage(
        'KIOM: طلب إذن فتح مسار\n'
        'المسار: $openedPath\n'
        'افتح تطبيق الهاتف للموافقة أو الرفض.',
      );

      await dialogs.showWarning(
        title: 'KIOM Protection',
        message: 'هذا المسار يحتاج موافقة من الهاتف قبل فتحه:\n$openedPath',
      );

      await _closeExplorerWindow(hwnd);
      return;
    }
  }

  Future<List<Map<String, dynamic>>> _getExplorerWindows() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$shell = New-Object -ComObject Shell.Application
$items = @()

foreach ($w in $shell.Windows()) {
  try {
    if ($w.FullName -like '*explorer.exe' -and $w.LocationURL -like 'file:*') {
      $items += [PSCustomObject]@{
        Hwnd = $w.HWND
        Url = $w.LocationURL
      }
    }
  } catch {}
}

$items | ConvertTo-Json -Compress -Depth 3
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

    final text = result.stdout.toString().trim();
    if (text.isEmpty) return [];

    try {
      final decoded = jsonDecode(text);
      final list = decoded is List ? decoded : [decoded];

      return list
          .whereType<Map>()
          .map((e) {
            final url = (e['Url'] ?? '').toString();
            String path = '';

            try {
              path = Uri.parse(url).toFilePath(windows: true);
            } catch (_) {}

            return {
              'hwnd': (e['Hwnd'] as num?)?.toInt() ?? 0,
              'path': path,
            };
          })
          .where((e) => (e['path'] ?? '').toString().isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _closeExplorerWindow(int hwnd) async {
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$shell = New-Object -ComObject Shell.Application

foreach (\$w in \$shell.Windows()) {
  try {
    if (\$w.HWND -eq $hwnd) {
      \$w.Quit()
    }
  } catch {}
}
''';

    await Process.run(
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
  }
}
