import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/open_app_info.dart';
import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';
import 'process_monitor_service.dart';
import 'telegram_notifier_service.dart';

class ApplicationBlockerService {
  ApplicationBlockerService({
    required this.store,
    ProcessMonitorService? monitor,
    this.telegram,
  }) : monitor = monitor ?? ProcessMonitorService();

  final JsonFileStore store;
  final ProcessMonitorService monitor;
  final TelegramNotifierService? telegram;

  Timer? _timer;
  bool _tickInProgress = false;
  final Map<int, DateTime> _recentKillAttempts = {};
  String? _lastHostsFingerprint;
  String? _lastFailedHostsFingerprint;
  DateTime? _lastHostsWriteFailureAt;
  DateTime? _lastHostsPermissionNoticeAt;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick();
  }

  void stop() => _timer?.cancel();

  Future<void> _tick() async {
    if (_tickInProgress) return;
    _tickInProgress = true;
    try {
      await enforceBlockedApps();
      await _rewriteHostsFile();
    } finally {
      _tickInProgress = false;
    }
  }

  List<Map<String, dynamic>> blockedApps() {
    return store
        .list('blockedApps')
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => (item['target'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> blockedSites() {
    return store
        .list('blockedSites')
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => (item['domain'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> cloudItems() {
    return [
      for (final item in blockedApps())
        {
          'id': _safeId('app_${item['target']}'),
          'type': 'app',
          'target': item['target'],
          'label': item['appName'] ?? item['target'],
          'appPath': item['appPath'] ?? '',
          'allowedUntil': item['allowedUntil'],
          'createdAt': item['createdAt'] ?? DateTime.now().toIso8601String(),
        },
      for (final item in blockedSites())
        {
          'id': _safeId('site_${item['domain']}'),
          'type': 'site',
          'target': item['domain'],
          'label': item['domain'],
          'lockType': item['lockType'] ?? 'blocked',
          'allowedUntil': item['allowedUntil'],
          'createdAt': item['createdAt'] ?? DateTime.now().toIso8601String(),
        },
    ];
  }

  Future<void> blockApp({
    required String target,
    String? appName,
    String? appPath,
  }) async {
    final normalized = _normalizeTarget(target);
    final blocked = blockedApps()
      ..removeWhere((item) => _isSameAppRule(item, normalized, appPath));
    blocked.add({
      'target': normalized,
      'appName': appName ?? target,
      'appPath': appPath ?? '',
      'allowedUntil': null,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.set('blockedApps', blocked);
    await store.appendLog('app_blocked', 'تم منع تطبيق من الهاتف', {
      'target': normalized,
      'appName': appName,
      'appPath': appPath,
    });
    await enforceBlockedApps();
  }

  Future<void> allowApp(String target, {Duration? duration}) async {
    final normalized = _normalizeTarget(target);
    final blocked = blockedApps();
    if (duration == null) {
      blocked.removeWhere((item) => _isSameAppRule(item, normalized, null));
    } else {
      final until = DateTime.now().add(duration).toIso8601String();
      for (final item in blocked) {
        if (_isSameAppRule(item, normalized, null)) {
          item['allowedUntil'] = until;
        }
      }
    }
    await store.set('blockedApps', blocked);
    await store.appendLog(
      duration == null ? 'app_allowed' : 'app_allowed_temporarily',
      duration == null
          ? 'تم إلغاء منع تطبيق من الهاتف'
          : 'تم السماح المؤقت لتطبيق ممنوع',
      {
        'target': normalized,
        'durationSeconds': duration?.inSeconds,
      },
    );
  }

  Future<void> blockSite(
    String domain, {
    String lockType = 'blocked',
    String? password,
    String? passwordHash,
  }) async {
    final normalized = _normalizeDomain(domain);
    if (normalized.isEmpty) throw StateError('domain غير صالح');
    final effectivePasswordHash =
        passwordHash?.trim().isNotEmpty == true ? passwordHash!.trim() : null;
    final blocked = blockedSites()
      ..removeWhere((item) => item['domain'] == normalized);
    blocked.add({
      'domain': normalized,
      'lockType': lockType,
      if (effectivePasswordHash != null)
        'passwordHash': effectivePasswordHash
      else if (password != null && password.isNotEmpty)
        'passwordHash': sha256.convert(utf8.encode(password)).toString(),
      'allowedUntil': null,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.set('blockedSites', blocked);
    await _rewriteHostsFile();
    await store.appendLog('site_blocked', 'تم منع موقع من الهاتف', {
      'domain': normalized,
      'lockType': lockType,
    });
  }

  Future<void> allowSite(String domain, {Duration? duration}) async {
    final normalized = _normalizeDomain(domain);
    if (normalized.isEmpty) throw StateError('domain غير صالح');
    final blocked = blockedSites();
    if (duration == null) {
      blocked.removeWhere((item) => item['domain'] == normalized);
    } else {
      final until = DateTime.now().add(duration).toIso8601String();
      for (final item in blocked) {
        if (item['domain'] == normalized) {
          item['allowedUntil'] = until;
        }
      }
    }
    await store.set('blockedSites', blocked);
    await _rewriteHostsFile();
    await store.appendLog(
        duration == null ? 'site_allowed' : 'site_allowed_temporarily',
        duration == null
            ? 'تم إلغاء منع موقع من الهاتف'
            : 'تم السماح المؤقت لموقع ممنوع',
        {
          'domain': normalized,
          'durationSeconds': duration?.inSeconds,
        });
  }

  Future<void> enforceBlockedApps() async {
    final rules = blockedApps();
    if (rules.isEmpty) return;

    final apps = await monitor.getOpenApps();
    for (final app in apps) {
      final rule = _matchingRule(app, rules);
      if (rule == null) continue;
      if (_isTemporarilyAllowed(rule)) continue;
      if (_recentlyTried(app.processId)) continue;

      final result = await SafeProcessRunner.run(
        'taskkill.exe',
        ['/PID', app.processId.toString(), '/F'],
        timeout: SafeProcessRunner.shortTimeout,
      );
      await store.appendLog(
        result.exitCode == 0 ? 'blocked_app_closed' : 'blocked_app_close_error',
        result.exitCode == 0
            ? 'تم إغلاق تطبيق ممنوع تلقائياً'
            : 'تعذر إغلاق تطبيق ممنوع',
        {
          'processId': app.processId,
          'appName': app.appName,
          'appPath': app.appPath,
          'title': app.title,
          'rule': rule,
          'exitCode': result.exitCode,
          'stdout': result.stdout.toString(),
          'stderr': result.stderr.toString(),
        },
      );
      if (result.exitCode == 0) {
        await telegram?.sendMessage(
          'KIOM: تم إغلاق تطبيق ممنوع\n'
          'التطبيق: ${app.appName}\n'
          'العنوان: ${app.title}\n'
          'الجهاز: ${Platform.localHostname}',
        );
      }
    }
  }

  bool _isTemporarilyAllowed(Map<String, dynamic> rule) {
    final until = DateTime.tryParse((rule['allowedUntil'] ?? '').toString());
    return until != null && until.isAfter(DateTime.now());
  }

  Map<String, dynamic>? _matchingRule(
    OpenAppInfo app,
    List<Map<String, dynamic>> rules,
  ) {
    final appName = _normalizeTarget(app.appName);
    final processName = _normalizeTarget(app.appName.replaceAll('.exe', ''));
    final appPath = app.appPath.toLowerCase();

    for (final rule in rules) {
      final target = _normalizeTarget(rule['target'].toString());
      final rulePath = (rule['appPath'] ?? '').toString().toLowerCase();
      final targetBase = target.replaceAll('.exe', '');
      final appBase = appName.replaceAll('.exe', '');
      if (target == appName || target == processName) {
        return rule;
      }
      if (targetBase.contains(appBase) || appBase.contains(targetBase)) {
        return rule;
      }
      if (rulePath.isNotEmpty &&
          (appPath == rulePath || appPath.startsWith(rulePath))) {
        return rule;
      }
      if (appPath.isNotEmpty && appPath.endsWith('\\$target')) return rule;
      if (appPath.isNotEmpty && appPath.endsWith('\\$target.exe')) return rule;
    }
    return null;
  }

  bool _recentlyTried(int processId) {
    final now = DateTime.now();
    _recentKillAttempts.removeWhere(
      (_, at) => now.difference(at).inSeconds > 30,
    );
    final last = _recentKillAttempts[processId];
    _recentKillAttempts[processId] = now;
    return last != null && now.difference(last).inSeconds < 3;
  }

  bool _isSameAppRule(
    Map<String, dynamic> item,
    String normalizedTarget,
    String? appPath,
  ) {
    final target = _normalizeTarget(item['target'].toString());
    final targetBase = target.replaceAll('.exe', '');
    final requestedBase = normalizedTarget.replaceAll('.exe', '');
    if (target == normalizedTarget ||
        targetBase.contains(requestedBase) ||
        requestedBase.contains(targetBase)) {
      return true;
    }

    final rulePath = (item['appPath'] ?? '').toString().toLowerCase();
    final requestedPath = (appPath ?? '').toLowerCase();
    return rulePath.isNotEmpty &&
        requestedPath.isNotEmpty &&
        (rulePath == requestedPath ||
            rulePath.startsWith(requestedPath) ||
            requestedPath.startsWith(rulePath));
  }

  String _normalizeTarget(String value) {
    var text = value.trim().toLowerCase().replaceAll('/', r'\');
    if (text.contains(r'\')) {
      text = text.split(r'\').last;
    }
    if (!text.endsWith('.exe')) {
      text = '$text.exe';
    }
    return text;
  }

  String _normalizeDomain(String value) {
    var text = value.trim().toLowerCase();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      text = Uri.tryParse(text)?.host ?? text;
    }
    text = text.replaceAll(RegExp(r'^www\.'), '');
    text = text.split('/').first;
    text = text.split(':').first;
    return text;
  }

  String _safeId(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isEmpty
        ? 'item'
        : safe.substring(0, safe.length > 90 ? 90 : safe.length);
  }

  Future<void> _rewriteHostsFile() async {
    final hosts = File(r'C:\Windows\System32\drivers\etc\hosts');
    const start = '# KIOM_BLOCK_START';
    const end = '# KIOM_BLOCK_END';
    final activeDomains = blockedSites()
        .where((item) => !_isTemporarilyAllowed(item))
        .map((item) => item['domain'].toString())
        .where((domain) => domain.trim().isNotEmpty)
        .toSet();
    final fingerprint = (activeDomains.toList()..sort()).join('|');
    if (fingerprint == _lastHostsFingerprint) return;
    final lastFailureAt = _lastHostsWriteFailureAt;
    if (fingerprint == _lastFailedHostsFingerprint &&
        lastFailureAt != null &&
        DateTime.now().difference(lastFailureAt).inSeconds < 30) {
      return;
    }

    final generated = <String>[
      start,
      for (final domain in activeDomains) ...[
        '0.0.0.0 $domain',
        '0.0.0.0 www.$domain',
      ],
      end,
    ].join('\r\n');

    try {
      final original = await hosts.readAsString();
      final cleaned = original
          .replaceAll(
            RegExp('$start[\\s\\S]*?$end\\r?\\n?', multiLine: true),
            '',
          )
          .trimRight();
      await hosts.writeAsString('$cleaned\r\n$generated\r\n');
      await SafeProcessRunner.run(
        'ipconfig.exe',
        ['/flushdns'],
        timeout: SafeProcessRunner.shortTimeout,
      );
      _lastHostsFingerprint = fingerprint;
      _lastFailedHostsFingerprint = null;
      _lastHostsWriteFailureAt = null;
    } catch (e) {
      final now = DateTime.now();
      final previousFailureAt = _lastHostsWriteFailureAt;
      _lastFailedHostsFingerprint = fingerprint;
      _lastHostsWriteFailureAt = now;

      if (previousFailureAt == null ||
          now.difference(previousFailureAt).inMinutes >= 10) {
        await store.appendLog(
          'site_block_hosts_error',
          'تعذر تعديل ملف hosts. شغل التطبيق كمسؤول.',
          {
            'error': e.toString(),
            'domains': activeDomains.toList(),
          },
        );
      }

      if (_lastHostsPermissionNoticeAt == null ||
          now.difference(_lastHostsPermissionNoticeAt!).inHours >= 6) {
        _lastHostsPermissionNoticeAt = now;
        await telegram?.sendMessage(
          'KIOM: تعذر تطبيق منع المواقع لأن ملف hosts يحتاج صلاحية مسؤول.\n'
          'المواقع: ${activeDomains.join(', ')}',
        );
      }
    }
  }
}
