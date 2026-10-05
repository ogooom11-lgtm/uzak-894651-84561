import 'dart:async';
import '../config/agent_config.dart';
import '../utils/json_file_store.dart';
import 'firestore_rest_client.dart';
import 'process_monitor_service.dart';

class OpenAppsSyncService {
  final String deviceId;
  final AgentConfig config;
  final FirestoreRestClient firestore;
  final ProcessMonitorService monitor;
  final JsonFileStore store;
  Timer? _timer;
  String? _lastFingerprint;
  bool _syncInProgress = false;

  OpenAppsSyncService({
    required this.deviceId,
    required this.config,
    required this.firestore,
    required this.monitor,
    required this.store,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(seconds: config.syncOpenAppsEverySeconds), (_) => _sync());
    _sync();
  }

  void stop() => _timer?.cancel();

  Future<void> _sync() async {
    if (_syncInProgress) return;
    _syncInProgress = true;
    try {
      final apps = await monitor.getOpenApps();
      final appMaps = apps.map((e) => e.toMap()).toList();
      final fingerprint = _fingerprint(appMaps);
      final previous = store
          .list('lastOpenApps')
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

      _lastFingerprint ??= store.get<String>('lastOpenAppsFingerprint');

      if (fingerprint == _lastFingerprint) {
        return;
      }

      await _writeChangeLogs(previous, appMaps);
      await store.set('lastOpenApps', appMaps);
      await store.set('lastOpenAppsFingerprint', fingerprint);
      _lastFingerprint = fingerprint;

      await firestore.syncOpenApps(deviceId, apps);
      await firestore.setDocument('devices/$deviceId', {
        'lastOpenAppsChangedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await store.appendLog('open_apps_sync_error', e.toString());
    } finally {
      _syncInProgress = false;
    }
  }

  String _fingerprint(List<Map<String, dynamic>> apps) {
    final parts = apps.map((app) {
      return [
        app['processId'] ?? '',
        app['appName'] ?? '',
        app['appPath'] ?? '',
        app['title'] ?? '',
      ].join('|');
    }).toList()
      ..sort();
    return parts.join('\n');
  }

  Future<void> _writeChangeLogs(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> current,
  ) async {
    final previousById = {
      for (final item in previous) (item['processId'] ?? '').toString(): item
    };
    final currentById = {
      for (final item in current) (item['processId'] ?? '').toString(): item
    };

    for (final entry in currentById.entries) {
      if (!previousById.containsKey(entry.key)) {
        await store.appendLog('app_opened', 'تم فتح تطبيق أو نافذة', {
          'processId': entry.key,
          'appName': entry.value['appName'],
          'title': entry.value['title'],
          'path': entry.value['appPath'],
        });
      } else {
        final oldTitle = (previousById[entry.key]?['title'] ?? '').toString();
        final newTitle = (entry.value['title'] ?? '').toString();
        if (oldTitle != newTitle) {
          await store.appendLog('app_changed', 'تغير عنوان نافذة مفتوحة', {
            'processId': entry.key,
            'appName': entry.value['appName'],
            'oldTitle': oldTitle,
            'newTitle': newTitle,
            'path': entry.value['appPath'],
          });
        }
      }
    }

    for (final entry in previousById.entries) {
      if (!currentById.containsKey(entry.key)) {
        await store.appendLog('app_closed', 'تم إغلاق تطبيق أو نافذة', {
          'processId': entry.key,
          'appName': entry.value['appName'],
          'title': entry.value['title'],
          'path': entry.value['appPath'],
        });
      }
    }
  }
}
