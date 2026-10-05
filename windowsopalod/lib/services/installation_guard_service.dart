import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'firestore_rest_client.dart';
import '../utils/json_file_store.dart';
import 'telegram_notifier_service.dart';

class InstallationGuardService {
  InstallationGuardService({
    required this.deviceId,
    required this.firestore,
    required this.store,
    this.telegram,
    this.interval = const Duration(seconds: 2),
  });

  final String deviceId;
  final FirestoreRestClient firestore;
  final JsonFileStore store;
  final TelegramNotifierService? telegram;
  final Duration interval;

  Timer? _timer;
  final Map<String, DateTime> _lastRequestAt = {};
  final Set<int> _recentKillAttempts = {};

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _scan());
    _scan();
  }

  void stop() => _timer?.cancel();

  Future<void> _scan() async {
    try {
      final installers = await _runningInstallers();
      if (installers.isEmpty) return;

      for (final installer in installers) {
        if (await _isApproved(installer)) continue;
        if (_recentlyRequested(installer)) continue;

        final requestId = _requestId(installer);
        await _createInstallRequest(requestId, installer);
        await _killInstaller(installer, requestId);
      }
    } catch (e) {
      await store.appendLog('install_guard_error', e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> _runningInstallers() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$items = Get-Process | ForEach-Object {
  [PSCustomObject]@{
    Id = $_.Id
    ProcessName = $_.ProcessName
    Path = $_.Path
    MainWindowTitle = $_.MainWindowTitle
    StartTime = if ($_.StartTime) { $_.StartTime.ToString('o') } else { '' }
  }
}
$items | ConvertTo-Json -Compress -Depth 3
''';

    final result = await Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      runInShell: false,
    );
    if (result.exitCode != 0) return [];

    final text = result.stdout.toString().trim();
    if (text.isEmpty) return [];
    final decoded = jsonDecode(text);
    final list = decoded is List ? decoded : [decoded];

    return list
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where(_looksLikeInstaller)
        .toList();
  }

  bool _looksLikeInstaller(Map<String, dynamic> process) {
    final id = (process['Id'] as num?)?.toInt() ?? 0;
    if (id <= 0 || id == pid) return false;

    final name = _exeName(process);
    if (name.isEmpty) return false;

    const safeSystemProcesses = {
      'trustedinstaller.exe',
      'tiworker.exe',
      'windowsopalod.exe',
      'kiom_pc_agent.exe',
      'explorer.exe',
      'powershell.exe',
      'pwsh.exe',
      'cmd.exe',
    };
    if (safeSystemProcesses.contains(name)) return false;

    final path = _path(process).toLowerCase();
    final title = (process['MainWindowTitle'] ?? '').toString().toLowerCase();
    final text = '$name $path $title';

    if (name == 'msiexec.exe' ||
        name == 'winget.exe' ||
        name == 'choco.exe' ||
        name == 'scoop.exe') {
      return true;
    }

    if (text.contains('setup') ||
        text.contains('installer') ||
        text.contains('install wizard') ||
        text.contains('installation') ||
        text.contains('تثبيت')) {
      return true;
    }

    return name.contains('setup') || name.contains('installer');
  }

  Future<bool> _isApproved(Map<String, dynamic> installer) async {
    final approvals = store.list('installApprovals');
    var changed = false;
    var allowed = false;
    final now = DateTime.now();
    final remaining = <dynamic>[];

    for (final item in approvals) {
      if (item is! Map) continue;
      final approval = item.cast<String, dynamic>();
      final until = DateTime.tryParse((approval['until'] ?? '').toString());
      if (until == null || until.isBefore(now)) {
        changed = true;
        continue;
      }
      remaining.add(approval);
      if (_approvalMatches(approval, installer)) {
        allowed = true;
      }
    }

    if (changed) {
      await store.set('installApprovals', remaining);
    }
    return allowed;
  }

  bool _approvalMatches(
    Map<String, dynamic> approval,
    Map<String, dynamic> installer,
  ) {
    final approvedPath = (approval['filePath'] ?? '').toString().toLowerCase();
    final approvedName = (approval['fileName'] ?? '').toString().toLowerCase();
    final path = _path(installer).toLowerCase();
    final name = _exeName(installer).toLowerCase();

    if (approvedPath.isNotEmpty && path == approvedPath) return true;
    if (approvedName.isNotEmpty && name == approvedName) return true;
    return approvedName.isNotEmpty &&
        (name.contains(approvedName) || approvedName.contains(name));
  }

  bool _recentlyRequested(Map<String, dynamic> installer) {
    final key = '${_exeName(installer)}|${_path(installer)}';
    final last = _lastRequestAt[key];
    final now = DateTime.now();
    _lastRequestAt[key] = now;
    return last != null && now.difference(last).inMinutes < 3;
  }

  Future<void> _createInstallRequest(
    String requestId,
    Map<String, dynamic> installer,
  ) async {
    final payload = {
      'deviceId': deviceId,
      'fileName': _exeName(installer),
      'filePath': _path(installer),
      'status': 'pending',
      'type': 'install_attempt',
      'processId': (installer['Id'] as num?)?.toInt() ?? 0,
      'windowTitle': (installer['MainWindowTitle'] ?? '').toString(),
      'details': installer,
      'createdAt': DateTime.now().toIso8601String(),
    };

    await firestore.createDocumentWithId(
      'install_requests/$deviceId/items',
      requestId,
      payload,
    );
    await store.appendLog(
      'install_attempt',
      'تم اكتشاف محاولة تثبيت وتحتاج موافقة الهاتف',
      payload,
    );
    await telegram?.sendMessage(
      'KIOM: محاولة تثبيت تحتاج موافقة\n'
      'الملف: ${payload['fileName']}\n'
      'المسار: ${payload['filePath']}\n'
      'الجهاز: $deviceId',
    );
  }

  Future<void> _killInstaller(
    Map<String, dynamic> installer,
    String requestId,
  ) async {
    final processId = (installer['Id'] as num?)?.toInt() ?? 0;
    if (processId <= 0 || _recentKillAttempts.contains(processId)) return;
    _recentKillAttempts.add(processId);

    final result = await Process.run(
      'taskkill.exe',
      ['/PID', processId.toString(), '/F'],
      runInShell: false,
    );
    await store.appendLog(
      result.exitCode == 0 ? 'install_blocked' : 'install_block_error',
      result.exitCode == 0
          ? 'تم إغلاق المثبت حتى تتم الموافقة من الهاتف'
          : 'تعذر إغلاق المثبت',
      {
        'requestId': requestId,
        'processId': processId,
        'fileName': _exeName(installer),
        'filePath': _path(installer),
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
      },
    );
  }

  String _requestId(Map<String, dynamic> installer) {
    final source = '${_exeName(installer)}_${_path(installer)}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    final safe = source.isEmpty
        ? 'installer'
        : source.substring(0, source.length > 80 ? 80 : source.length);
    return 'install_${DateTime.now().millisecondsSinceEpoch}_$safe';
  }

  String _exeName(Map<String, dynamic> process) {
    final raw = (process['ProcessName'] ?? '').toString().trim();
    if (raw.isEmpty) return '';
    return raw.toLowerCase().endsWith('.exe') ? raw : '$raw.exe';
  }

  String _path(Map<String, dynamic> process) {
    return (process['Path'] ?? '').toString().trim();
  }
}
