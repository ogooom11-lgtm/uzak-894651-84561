import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../utils/json_file_store.dart';
import 'firestore_rest_client.dart';

class InstalledAppsSyncService {
  InstalledAppsSyncService({
    required this.deviceId,
    required this.firestore,
    required this.store,
    this.interval = const Duration(minutes: 2),
  });

  final String deviceId;
  final FirestoreRestClient firestore;
  final JsonFileStore store;
  final Duration interval;

  Timer? _timer;
  String? _lastFingerprint;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _sync());
    _sync();
  }

  void stop() => _timer?.cancel();

  Future<void> _sync() async {
    try {
      final apps = await _readInstalledApps();
      final fingerprint = _fingerprint(apps);
      _lastFingerprint ??= store.get<String>('installedAppsFingerprint');
      if (fingerprint == _lastFingerprint) return;

      final previous = store
          .list('installedApps')
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
      await _logChanges(previous, apps);

      await store.set('installedApps', apps);
      await store.set('installedAppsFingerprint', fingerprint);
      _lastFingerprint = fingerprint;
      await firestore.syncInstalledApps(deviceId, apps);
      await firestore.setDocument('devices/$deviceId', {
        'lastInstalledAppsChangedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await store.appendLog('installed_apps_sync_error', e.toString());
    }
  }

  Future<List<Map<String, dynamic>>> _readInstalledApps() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$roots = @(
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

$items = foreach ($root in $roots) {
  Get-ItemProperty $root | Where-Object {
    $_.DisplayName -and $_.SystemComponent -ne 1
  } | ForEach-Object {
    [PSCustomObject]@{
      DisplayName = $_.DisplayName
      DisplayVersion = $_.DisplayVersion
      Publisher = $_.Publisher
      InstallDate = $_.InstallDate
      InstallLocation = $_.InstallLocation
      UninstallString = $_.UninstallString
    }
  }
}

$items | Sort-Object DisplayName -Unique | ConvertTo-Json -Compress -Depth 3
''';

    final result = await Process.run('powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script]);
    if (result.exitCode != 0) return [];
    final text = result.stdout.toString().trim();
    if (text.isEmpty) return [];

    final decoded = jsonDecode(text);
    final list = decoded is List ? decoded : [decoded];
    final now = DateTime.now().toIso8601String();
    return list
        .whereType<Map>()
        .map((item) {
          final name = (item['DisplayName'] ?? '').toString().trim();
          final publisher = (item['Publisher'] ?? '').toString().trim();
          final version = (item['DisplayVersion'] ?? '').toString().trim();
          final location = (item['InstallLocation'] ?? '').toString().trim();
          final id = _idFor('$name|$publisher|$version|$location');
          return {
            'id': id,
            'name': name,
            'publisher': publisher,
            'version': version,
            'installDate': (item['InstallDate'] ?? '').toString(),
            'installLocation': location,
            'uninstallString': (item['UninstallString'] ?? '').toString(),
            'iconKey': name.toLowerCase(),
            'status': 'installed',
            'lastSeenAt': now,
          };
        })
        .where((app) => app['name'].toString().isNotEmpty)
        .toList();
  }

  Future<void> _logChanges(List<Map<String, dynamic>> previous,
      List<Map<String, dynamic>> current) async {
    if (previous.isEmpty) return;

    final previousById = {
      for (final app in previous) app['id'].toString(): app
    };
    final currentById = {for (final app in current) app['id'].toString(): app};

    for (final entry in currentById.entries) {
      if (!previousById.containsKey(entry.key)) {
        await store.appendLog(
            'app_installed', 'تم تثبيت تطبيق جديد', entry.value);
        await firestore.createInstallChange(
          deviceId: deviceId,
          appName: entry.value['name'].toString(),
          changeType: 'installed',
          payload: entry.value,
        );
      }
    }

    for (final entry in previousById.entries) {
      if (!currentById.containsKey(entry.key)) {
        await store.appendLog(
            'app_uninstalled', 'تم إلغاء تثبيت تطبيق', entry.value);
        await firestore.createInstallChange(
          deviceId: deviceId,
          appName: entry.value['name'].toString(),
          changeType: 'uninstalled',
          payload: entry.value,
        );
      }
    }
  }

  String _fingerprint(List<Map<String, dynamic>> apps) {
    final parts = apps
        .map((app) => '${app['id']}|${app['name']}|${app['version']}')
        .toList()
      ..sort();
    return sha1.convert(utf8.encode(parts.join('\n'))).toString();
  }

  String _idFor(String value) {
    return sha1.convert(utf8.encode(value.toLowerCase())).toString();
  }
}
