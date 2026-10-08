import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config/agent_config.dart';
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
  Timer? _relayPollTimer;
  HttpServer? _localServer;
  final HttpClient _httpClient = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  bool _isHeartbeatRunning = false;
  bool _isSyncRunning = false;
  bool _isRelayPolling = false;
  int _lastRelaySince = 0;

  void start() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _publishHeartbeat());

    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 8), (_) => _syncCollections());

    _relayPollTimer?.cancel();
    _relayPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollRelayCommands());

    _startLocalHttpServer();

    _publishHeartbeat();
    _syncCollections();
  }

  void stop() {
    _heartbeatTimer?.cancel();
    _syncTimer?.cancel();
    _relayPollTimer?.cancel();
    _localServer?.close(force: true);
  }

  Future<void> _startLocalHttpServer() async {
    try {
      _localServer = await HttpServer.bind(InternetAddress.anyIPv4, 8946);
      _localServer!.listen((request) async {
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = 200;
          await request.response.close();
          return;
        }

        if (request.uri.path == '/status' || request.uri.path == '/state') {
          final state = await _buildStateMap();
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(state));
          await request.response.close();
          return;
        }

        if (request.uri.path == '/command' && request.method == 'POST') {
          final content = await utf8.decoder.bind(request).join();
          try {
            final envelope = jsonDecode(content) as Map<String, dynamic>;
            final type = (envelope['type'] ?? '').toString();
            final payload = envelope['payload'] is Map
                ? Map<String, dynamic>.from(envelope['payload'] as Map)
                : <String, dynamic>{};
            final result = await executor.executeTelegramCommand(
              type: type,
              payload: payload,
            );
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'success': result.success,
              'message': result.message,
              'payload': result.payload,
            }));
          } catch (e) {
            request.response.statusCode = 400;
            request.response.write(jsonEncode({'error': e.toString()}));
          }
          await request.response.close();
          return;
        }

        request.response.statusCode = 404;
        await request.response.close();
      });
    } catch (_) {
      // Port in use or firewall constraint
    }
  }

  Future<Map<String, dynamic>> _buildStateMap() async {
    final health = await windowsControl.systemHealth();
    final healthMap = health.payload;
    final openApps = store.list('open_apps');
    final installedApps = store.list('installed_apps');

    final volume = store.get<int>('currentVolume') ?? 50;
    final isMuted = store.get<bool>('isMuted') ?? false;
    final activeMode = store.get<String>('activeMode') ?? 'normal';
    final isEmergency = store.get<bool>('isEmergency') ?? false;
    final isPrivacy = store.get<bool>('isPrivacy') ?? false;

    return {
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
      'openApps': openApps.take(40).toList(),
      'blockedItems': appBlocker.cloudItems(),
      'rules': pathRuleStore.getRules().map((r) => r.toJson()).toList(),
    };
  }

  Future<void> _publishToRelay(String topic, Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse('https://ntfy.sh/$topic');
      final req = await _httpClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(data));
      final res = await req.close();
      await res.drain();
    } catch (_) {}
  }

  Future<void> _pollRelayCommands() async {
    if (_isRelayPolling) return;
    _isRelayPolling = true;
    try {
      final sinceParam = _lastRelaySince > 0 ? '?since=$_lastRelaySince' : '?since=10s';
      final uri = Uri.parse('https://ntfy.sh/kiom_cmd_$deviceId/json$sinceParam');
      final req = await _httpClient.getUrl(uri);
      final res = await req.close();
      if (res.statusCode == 200) {
        final lines = await res.transform(utf8.decoder).transform(const LineSplitter()).toList();
        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final msg = jsonDecode(line) as Map<String, dynamic>;
            final time = (msg['time'] as num?)?.toInt();
            if (time != null && time > _lastRelaySince) {
              _lastRelaySince = time;
            }
            if (msg['event'] == 'message' && msg['message'] != null) {
              final raw = msg['message'].toString();
              final envelope = jsonDecode(raw) as Map<String, dynamic>;
              final type = (envelope['type'] ?? '').toString();
              final commandId = (envelope['id'] ?? '').toString();
              final payload = envelope['payload'] is Map
                  ? Map<String, dynamic>.from(envelope['payload'] as Map)
                  : <String, dynamic>{};
              final result = await executor.executeTelegramCommand(type: type, payload: payload);
              await publishCommandResponse(
                commandId: commandId,
                commandType: type,
                success: result.success,
                message: result.message,
                payload: result.payload,
              );
            }
          } catch (_) {}
        }
      }
    } catch (_) {
    } finally {
      _isRelayPolling = false;
    }
  }

  Future<void> _publishHeartbeat() async {
    if (_isHeartbeatRunning) return;
    _isHeartbeatRunning = true;
    try {
      final statePayload = await _buildStateMap();
      final body = jsonEncode(statePayload);

      // 1. Publish to Telegram
      if (telegram.isConfigured) {
        await telegram.sendMessage(
          '#KIOM_STATE\n$body',
          parseMode: '',
        );
      }

      // 2. Publish to Realtime Cloud Relay
      await _publishToRelay('kiom_state_$deviceId', statePayload);
    } catch (_) {
    } finally {
      _isHeartbeatRunning = false;
    }
  }

  Future<void> _syncCollections() async {
    if (_isSyncRunning) return;
    _isSyncRunning = true;
    try {
      // 1. Sync Open Apps
      final openApps = store.list('open_apps');
      if (openApps.isNotEmpty) {
        final payload = jsonEncode({
          'deviceId': deviceId,
          'apps': openApps.take(40).toList(),
        });
        if (telegram.isConfigured) {
          await telegram.sendMessage(
            '#KIOM_APPS\n$payload',
            parseMode: '',
          );
        }
        await _publishToRelay('kiom_apps_$deviceId', {
          'deviceId': deviceId,
          'apps': openApps.take(40).toList(),
        });
      }

      // 2. Sync Blocked Items
      final blocked = appBlocker.cloudItems();
      final blockedPayload = jsonEncode({
        'deviceId': deviceId,
        'items': blocked,
      });
      if (telegram.isConfigured) {
        await telegram.sendMessage(
          '#KIOM_BLOCKED\n$blockedPayload',
          parseMode: '',
        );
      }
      await _publishToRelay('kiom_blocked_$deviceId', {
        'deviceId': deviceId,
        'items': blocked,
      });

      // 3. Sync Path Rules
      final rules = pathRuleStore.getRules().map((r) => r.toJson()).toList();
      final rulesPayload = jsonEncode({
        'deviceId': deviceId,
        'rules': rules,
      });
      if (telegram.isConfigured) {
        await telegram.sendMessage(
          '#KIOM_RULES\n$rulesPayload',
          parseMode: '',
        );
      }
      await _publishToRelay('kiom_rules_$deviceId', {
        'deviceId': deviceId,
        'rules': rules,
      });
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
    final payload = {
      'id': requestId,
      'deviceId': deviceId,
      'title': title,
      'targetPath': targetPath,
      'type': type,
      'details': details,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (telegram.isConfigured) {
      await telegram.sendMessage(
        '#KIOM_PERM\n${jsonEncode(payload)}',
        parseMode: '',
      );
    }
    await _publishToRelay('kiom_perm_$deviceId', payload);
  }

  Future<void> publishInstallRequest({
    required String requestId,
    required String fileName,
    required String filePath,
  }) async {
    final payload = {
      'id': requestId,
      'deviceId': deviceId,
      'fileName': fileName,
      'filePath': filePath,
      'status': 'pending',
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (telegram.isConfigured) {
      await telegram.sendMessage(
        '#KIOM_INSTALL\n${jsonEncode(payload)}',
        parseMode: '',
      );
    }
    await _publishToRelay('kiom_install_$deviceId', payload);
  }

  Future<void> publishCommandResponse({
    required String commandId,
    required String commandType,
    required bool success,
    required String message,
    Map<String, dynamic> payload = const {},
  }) async {
    final res = {
      'id': commandId,
      'commandId': commandId,
      'deviceId': deviceId,
      'type': commandType,
      'success': success,
      'message': message,
      'phase': 'final',
      'payload': payload,
      'createdAt': DateTime.now().toIso8601String(),
    };

    if (telegram.isConfigured) {
      await telegram.sendMessage(
        '#KIOM_RES\n${jsonEncode(res)}',
        parseMode: '',
      );
    }
    await _publishToRelay('kiom_res_$deviceId', res);

    if (commandType == 'browse_path' || commandType == 'search_files') {
      final fileRes = {
        'commandId': commandId,
        'requestId': payload['requestId'] ?? commandId,
        'path': payload['path'] ?? 'roots',
        'items': payload['items'] ?? const [],
      };
      if (telegram.isConfigured) {
        await telegram.sendMessage(
          '#KIOM_FILE_RES\n${jsonEncode(fileRes)}',
          parseMode: '',
        );
      }
      await _publishToRelay('kiom_file_res_$deviceId', fileRes);
    }
  }
}
