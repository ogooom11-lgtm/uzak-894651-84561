import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/agent_config.dart';
import '../models/open_app_info.dart';
import '../models/path_rule.dart';
import '../utils/json_file_store.dart';
import 'application_blocker_service.dart';
import 'command_executor_service.dart';
import 'path_rule_store.dart';
import 'telegram_notifier_service.dart';
import 'windows_control_service.dart';

class TelegramCloudDatabaseService {
  TelegramCloudDatabaseService({
    required this.deviceId,
    required this.deviceName,
    required this.config,
    required this.store,
    required this.telegram,
    required this.executor,
    required this.appBlocker,
    required this.pathRuleStore,
    WindowsControlService? windowsControl,
    this.heartbeatInterval = const Duration(seconds: 4),
  }) : windowsControl = windowsControl ?? WindowsControlService();

  final String deviceId;
  final String deviceName;
  final AgentConfig config;
  final JsonFileStore store;
  final TelegramNotifierService telegram;
  final CommandExecutorService executor;
  final ApplicationBlockerService appBlocker;
  final PathRuleStore pathRuleStore;
  final WindowsControlService windowsControl;
  final Duration heartbeatInterval;

  Timer? _heartbeatTimer;
  Timer? _syncTimer;
  bool _isHeartbeatRunning = false;
  bool _isSyncRunning = false;

  void start() {
    if (!telegram.hasBotToken) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _publishHeartbeat());

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) => _syncCollections());

    _publishHeartbeat();
    _syncCollections();
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _syncTimer?.cancel();
  }

  Future<void> _publishHeartbeat() async {
    if (_isHeartbeatRunning || !telegram.isConfigured) return;
    _isHeartbeatRunning = true;
    try {
      final health = await windowsControl.systemHealth();
      final healthMap = health.payload;
      final openApps = store.list('open_apps');
      final installedApps = store.list('installed_apps');

      final volume = store.get<int>('currentVolume') ?? 50;
      final isMuted = store.get<bool>('isMuted') ?? false;
      final activeMode = store.get<String>('activeMode') ?? 'normal';
      final isEmergency = store.get<bool>('isEmergency') ?? false;
      final isPrivacy = store.get<bool>('isPrivacy') ?? false;

      final statePayload = {
        'deviceId': deviceId,
        'name': deviceName,
        'os': 'Windows',
        'appVersion': config.appVersion,
        'lastSeenAt': DateTime.now().toIso8601String(),
        'volume': volume,
        'isMuted': isMuted,
        'activeMode': activeMode,
        'isEmergency': isEmergency,
        'isPrivacy': isPrivacy,
        'totalOpenApps': openApps.length,
        'totalInstalledApps': installedApps.length,
        'wifiStatus': 'connected',
        'bluetoothStatus': 'ready',
        'health': healthMap,
      };

      final body = jsonEncode(statePayload);
      await telegram.sendMessage(
        '#KIOM_STATE\n$body',
        parseMode: '',
      );
    } catch (_) {
    } finally {
      _isHeartbeatRunning = false;
    }
  }

  Future<void> _syncCollections() async {
    if (_isSyncRunning || !telegram.isConfigured) return;
    _isSyncRunning = true;
    try {
      // 1. Sync Open Apps
      final openApps = store.list('open_apps');
      if (openApps.isNotEmpty) {
        final payload = jsonEncode({
          'deviceId': deviceId,
          'apps': openApps.take(40).toList(),
        });
        await telegram.sendMessage(
          '#KIOM_APPS\n$payload',
          parseMode: '',
        );
      }

      // 2. Sync Blocked Items
      final blocked = appBlocker.cloudItems();
      final blockedPayload = jsonEncode({
        'deviceId': deviceId,
        'items': blocked,
      });
      await telegram.sendMessage(
        '#KIOM_BLOCKED\n$blockedPayload',
        parseMode: '',
      );

      // 3. Sync Path Rules
      final rules = pathRuleStore.getRules().map((r) => r.toJson()).toList();
      final rulesPayload = jsonEncode({
        'deviceId': deviceId,
        'rules': rules,
      });
      await telegram.sendMessage(
        '#KIOM_RULES\n$rulesPayload',
        parseMode: '',
      );
    } catch (_) {
    } finally {
      _isSyncRunning = false;
    }
  }

  Future<void> publishPermissionRequest({
    required String requestId,
    required String title,
    required String targetPath,
    required String type,
    String? details,
  }) async {
    final payload = jsonEncode({
      'id': requestId,
      'deviceId': deviceId,
      'title': title,
      'targetPath': targetPath,
      'type': type,
      'details': details,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await telegram.sendMessage(
      '#KIOM_PERM\n$payload',
      parseMode: '',
    );
  }

  Future<void> publishInstallRequest({
    required String requestId,
    required String fileName,
    required String filePath,
  }) async {
    final payload = jsonEncode({
      'id': requestId,
      'deviceId': deviceId,
      'fileName': fileName,
      'filePath': filePath,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    });

    await telegram.sendMessage(
      '#KIOM_INSTALL\n$payload',
      parseMode: '',
    );
  }

  Future<void> publishCommandResponse({
    required String commandId,
    required String commandType,
    required bool success,
    required String message,
    Map<String, dynamic> payload = const {},
  }) async {
    final res = jsonEncode({
      'id': commandId,
      'commandId': commandId,
      'deviceId': deviceId,
      'type': commandType,
      'success': success,
      'message': message,
      'phase': 'final',
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    });

    await telegram.sendMessage(
      '#KIOM_RES\n$res',
      parseMode: '',
    );

    if (commandType == 'browse_path' || commandType == 'search_files') {
      final fileRes = jsonEncode({
        'commandId': commandId,
        'requestId': payload['requestId'] ?? commandId,
        'path': payload['path'] ?? 'roots',
        'items': payload['items'] ?? const [],
      });
      await telegram.sendMessage(
        '#KIOM_FILE_RES\n$fileRes',
        parseMode: '',
      );
    }
  }
}
