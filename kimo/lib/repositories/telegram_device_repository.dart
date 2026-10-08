import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../config/app_environment.dart';
import '../core/command_type.dart';
import '../core/date_mapper.dart';
import '../models/blocked_item.dart';
import '../models/command_response.dart';
import '../models/device_notification.dart';
import '../models/install_request.dart';
import '../models/installed_app.dart';
import '../models/log_entry.dart';
import '../models/open_app.dart';
import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../models/permission_request.dart';
import '../models/remote_file_item.dart';
import '../models/screenshot_item.dart';
import '../services/local_linked_devices_store.dart';
import 'device_repository.dart';

class TelegramDeviceRepository implements DeviceRepository {
  TelegramDeviceRepository({
    LocalLinkedDevicesStore? store,
    String? botToken,
    String? chatId,
  })  : _store = store ?? LocalLinkedDevicesStore(),
        _botToken = botToken ?? AppEnvironment.defaultTelegramBotToken,
        _chatId = chatId ?? AppEnvironment.defaultTelegramChatId {
    _init();
  }

  final LocalLinkedDevicesStore _store;
  String _botToken;
  String _chatId;
  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  final Map<String, List<OpenApp>> _openApps = {};
  final Map<String, List<InstalledApp>> _installedApps = {};
  final Map<String, List<BlockedItem>> _blockedItems = {};
  final Map<String, List<PathRule>> _pathRules = {};
  final Map<String, List<PermissionRequest>> _permissionRequests = {};
  final Map<String, List<InstallRequest>> _installRequests = {};
  final Map<String, List<ScreenshotItem>> _screenshots = {};
  final Map<String, List<LogEntry>> _logs = {};
  final Map<String, List<DeviceNotification>> _notifications = {};
  final Map<String, List<CommandResponse>> _commandResponses = {};

  final StreamController<List<PcDevice>> _devicesController =
      StreamController<List<PcDevice>>.broadcast();
  final StreamController<String> _openAppsController =
      StreamController<String>.broadcast();
  final StreamController<String> _installedAppsController =
      StreamController<String>.broadcast();
  final StreamController<String> _blockedItemsController =
      StreamController<String>.broadcast();
  final StreamController<String> _pathRulesController =
      StreamController<String>.broadcast();
  final StreamController<String> _permissionRequestsController =
      StreamController<String>.broadcast();
  final StreamController<String> _installRequestsController =
      StreamController<String>.broadcast();
  final StreamController<String> _screenshotsController =
      StreamController<String>.broadcast();
  final StreamController<String> _logsController =
      StreamController<String>.broadcast();
  final StreamController<String> _notificationsController =
      StreamController<String>.broadcast();
  final StreamController<String> _commandResponsesController =
      StreamController<String>.broadcast();

  final Map<String, Completer<CommandResponse>> _pendingResponseCompleters = {};
  final Map<String, Completer<RemoteFileListing>> _pendingFileCompleters = {};

  Timer? _pollTimer;
  int? _lastUpdateOffset;
  bool _isPolling = false;

  String get botToken => _botToken;
  String get chatId => _chatId;

  Future<void> updateConfig({String? token, String? chat}) async {
    final prefs = await SharedPreferences.getInstance();
    if (token != null) {
      _botToken = token.trim();
      await prefs.setString('telegram_cloud_bot_token', _botToken);
    }
    if (chat != null) {
      _chatId = chat.trim();
      await prefs.setString('telegram_cloud_chat_id', _chatId);
    }
    _lastUpdateOffset = null;
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString('telegram_cloud_bot_token');
    final savedChat = prefs.getString('telegram_cloud_chat_id');
    if (savedToken != null && savedToken.trim().isNotEmpty) {
      _botToken = savedToken.trim();
    }
    if (savedChat != null && savedChat.trim().isNotEmpty) {
      _chatId = savedChat.trim();
    }

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollTelegram());
    _pollTelegram();
  }

  Future<void> _pollTelegram() async {
    if (_isPolling || _botToken.trim().isEmpty) return;
    _isPolling = true;
    try {
      final updates = await _getUpdates(offset: _lastUpdateOffset);
      for (final update in updates) {
        final updateId = (update['update_id'] as num?)?.toInt();
        if (updateId != null) {
          _lastUpdateOffset = updateId + 1;
        }
        await _processUpdate(update);
      }
    } catch (_) {
      // Ignore background transient network hiccups
    } finally {
      _isPolling = false;
    }
  }

  Future<List<Map<String, dynamic>>> _getUpdates({int? offset}) async {
    try {
      final uri = Uri.parse(
        'https://api.telegram.org/bot$_botToken/getUpdates'
        '${offset != null ? '?offset=$offset&timeout=5' : '?timeout=5'}',
      );
      final req = await _httpClient.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return const [];
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      if (decoded['ok'] == true && decoded['result'] is List) {
        return (decoded['result'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  Future<void> _processUpdate(Map<String, dynamic> update) async {
    final message = (update['message'] ?? update['channel_post']) as Map?;
    if (message == null) return;

    final chat = message['chat'] as Map?;
    final incomingChatId = (chat?['id'] ?? '').toString();
    if (_chatId.isEmpty && incomingChatId.isNotEmpty) {
      _chatId = incomingChatId;
    }

    final text = (message['text'] ?? message['caption'] ?? '').toString().trim();

    // 1. Photo / Screenshot message
    if (message.containsKey('photo') && message['photo'] is List) {
      final photos = (message['photo'] as List).whereType<Map>().toList();
      if (photos.isNotEmpty) {
        final largest = photos.last;
        final fileId = (largest['file_id'] ?? '').toString();
        final deviceId = _extractDeviceIdFromCaption(text) ?? 'primary_pc';
        final directUrl = await _getFileUrl(fileId);
        if (directUrl != null) {
          final screenshot = ScreenshotItem(
            id: fileId,
            deviceId: deviceId,
            imageUrl: directUrl,
            storagePath: fileId,
            createdAt: DateTime.now(),
          );
          _screenshots.putIfAbsent(deviceId, () => []).insert(0, screenshot);
          _screenshotsController.add(deviceId);
        }
      }
      return;
    }

    if (text.isEmpty) return;

    // 2. Structured KIOM Cloud Protocol Tags
    if (text.startsWith('#KIOM_STATE')) {
      final jsonStr = text.substring('#KIOM_STATE'.length).trim();
      await _handleStateMessage(jsonStr);
    } else if (text.startsWith('#KIOM_APPS')) {
      final jsonStr = text.substring('#KIOM_APPS'.length).trim();
      _handleAppsMessage(jsonStr);
    } else if (text.startsWith('#KIOM_INSTALLED')) {
      final jsonStr = text.substring('#KIOM_INSTALLED'.length).trim();
      _handleInstalledAppsMessage(jsonStr);
    } else if (text.startsWith('#KIOM_BLOCKED')) {
      final jsonStr = text.substring('#KIOM_BLOCKED'.length).trim();
      _handleBlockedItemsMessage(jsonStr);
    } else if (text.startsWith('#KIOM_RULES')) {
      final jsonStr = text.substring('#KIOM_RULES'.length).trim();
      _handlePathRulesMessage(jsonStr);
    } else if (text.startsWith('#KIOM_PERM')) {
      final jsonStr = text.substring('#KIOM_PERM'.length).trim();
      _handlePermissionRequestMessage(jsonStr);
    } else if (text.startsWith('#KIOM_INSTALL')) {
      final jsonStr = text.substring('#KIOM_INSTALL'.length).trim();
      _handleInstallRequestMessage(jsonStr);
    } else if (text.startsWith('#KIOM_RES')) {
      final jsonStr = text.substring('#KIOM_RES'.length).trim();
      _handleCommandResponseMessage(jsonStr);
    } else if (text.startsWith('#KIOM_FILE_RES')) {
      final jsonStr = text.substring('#KIOM_FILE_RES'.length).trim();
      _handleFileListingMessage(jsonStr);
    } else if (text.startsWith('#KIOM_LOG')) {
      final jsonStr = text.substring('#KIOM_LOG'.length).trim();
      _handleLogMessage(jsonStr);
    } else if (text.startsWith('#KIOM_NOTIF')) {
      final jsonStr = text.substring('#KIOM_NOTIF'.length).trim();
      _handleNotificationMessage(jsonStr);
    }
  }

  String? _extractDeviceIdFromCaption(String text) {
    final match = RegExp(r'deviceId[:=]\s*([A-Za-z0-9_\-]+)').firstMatch(text);
    return match?.group(1);
  }

  Future<String?> _getFileUrl(String fileId) async {
    try {
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/getFile?file_id=$fileId');
      final req = await _httpClient.getUrl(uri);
      final res = await req.close();
      if (res.statusCode != 200) return null;
      final body = await res.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final path = decoded['result']?['file_path']?.toString();
      if (path != null) {
        return 'https://api.telegram.org/file/bot$_botToken/$path';
      }
    } catch (_) {}
    return null;
  }

  Future<void> _handleStateMessage(String jsonStr) async {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? map['id'] ?? 'device').toString();
      final name = (map['name'] ?? map['computerName'] ?? 'كمبيوتر').toString();

      final device = PcDevice(
        id: deviceId,
        name: name,
        os: (map['os'] ?? 'Windows 11').toString(),
        appVersion: (map['appVersion'] ?? '1.0.0').toString(),
        createdAt: dateFromAny(map['createdAt']),
        linkedUserIds: [AppEnvironment.demoUserId],
        lastCheckResponse: map['lastCheckResponse']?.toString(),
        lastSeenAt: DateTime.now(),
        wifiStatus: map['wifiStatus']?.toString(),
        bluetoothStatus: map['bluetoothStatus']?.toString(),
        volume: int.tryParse('${map['volume'] ?? 0}') ?? 0,
        isMuted: map['isMuted'] == true,
        telegramChatId: _chatId,
        activeMode: map['activeMode']?.toString(),
        isEmergency: map['isEmergency'] == true,
        isPrivacy: map['isPrivacy'] == true,
        totalInstalledApps: int.tryParse('${map['totalInstalledApps'] ?? 0}') ?? 0,
        totalOpenApps: int.tryParse('${map['totalOpenApps'] ?? 0}') ?? 0,
      );

      await _store.upsertDevice(AppEnvironment.demoUserId, device);
      final all = await _store.loadDevices(AppEnvironment.demoUserId);
      _devicesController.add(all);
    } catch (_) {}
  }

  void _handleAppsMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final appsRaw = map['apps'] as List? ?? const [];
      final apps = appsRaw
          .whereType<Map>()
          .map((e) => OpenApp.fromMap(
              (e['processId'] ?? e['id'] ?? const Uuid().v4()).toString(),
              Map<String, dynamic>.from(e)))
          .toList();
      _openApps[deviceId] = apps;
      _openAppsController.add(deviceId);
    } catch (_) {}
  }

  void _handleInstalledAppsMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final appsRaw = map['apps'] as List? ?? const [];
      final apps = appsRaw
          .whereType<Map>()
          .map((e) => InstalledApp.fromMap(
              (e['id'] ?? e['name'] ?? const Uuid().v4()).toString(),
              Map<String, dynamic>.from(e)))
          .toList();
      _installedApps[deviceId] = apps;
      _installedAppsController.add(deviceId);
    } catch (_) {}
  }

  void _handleBlockedItemsMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final itemsRaw = map['items'] as List? ?? const [];
      final items = itemsRaw
          .whereType<Map>()
          .map((e) => BlockedItem.fromMap(
              (e['id'] ?? e['target'] ?? const Uuid().v4()).toString(),
              Map<String, dynamic>.from(e)))
          .toList();
      _blockedItems[deviceId] = items;
      _blockedItemsController.add(deviceId);
    } catch (_) {}
  }

  void _handlePathRulesMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final rulesRaw = map['rules'] as List? ?? const [];
      final rules = rulesRaw
          .whereType<Map>()
          .map((e) => PathRule.fromMap(
              (e['id'] ?? e['path'] ?? const Uuid().v4()).toString(),
              Map<String, dynamic>.from(e)))
          .toList();
      _pathRules[deviceId] = rules;
      _pathRulesController.add(deviceId);
    } catch (_) {}
  }

  void _handlePermissionRequestMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final id = (map['id'] ?? const Uuid().v4()).toString();
      final req = PermissionRequest.fromMap(id, map);
      final list = _permissionRequests.putIfAbsent(deviceId, () => []);
      list.removeWhere((e) => e.id == id);
      list.insert(0, req);
      _permissionRequestsController.add(deviceId);
    } catch (_) {}
  }

  void _handleInstallRequestMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final id = (map['id'] ?? const Uuid().v4()).toString();
      final req = InstallRequest.fromMap(id, map);
      final list = _installRequests.putIfAbsent(deviceId, () => []);
      list.removeWhere((e) => e.id == id);
      list.insert(0, req);
      _installRequestsController.add(deviceId);
    } catch (_) {}
  }

  void _handleCommandResponseMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final commandId = (map['commandId'] ?? map['id'] ?? '').toString();
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final res = CommandResponse.fromMap(
        (map['id'] ?? const Uuid().v4()).toString(),
        map,
      );

      final list = _commandResponses.putIfAbsent(deviceId, () => []);
      list.removeWhere((e) => e.commandId == commandId);
      list.insert(0, res);
      _commandResponsesController.add(deviceId);

      final completer = _pendingResponseCompleters.remove(commandId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(res);
      }
    } catch (_) {}
  }

  void _handleFileListingMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final requestId = (map['requestId'] ?? map['commandId'] ?? '').toString();
      final listing = RemoteFileListing.fromPayload(map);
      final completer = _pendingFileCompleters.remove(requestId);
      if (completer != null && !completer.isCompleted) {
        completer.complete(listing);
      }
    } catch (_) {}
  }

  void _handleLogMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final id = (map['id'] ?? const Uuid().v4()).toString();
      final entry = LogEntry.fromMap(id, map);
      final list = _logs.putIfAbsent(deviceId, () => []);
      list.insert(0, entry);
      if (list.length > 500) list.removeRange(500, list.length);
      _logsController.add(deviceId);
    } catch (_) {}
  }

  void _handleNotificationMessage(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? 'device').toString();
      final id = (map['id'] ?? const Uuid().v4()).toString();
      final notif = DeviceNotification.fromMap(id, map);
      final list = _notifications.putIfAbsent(deviceId, () => []);
      list.insert(0, notif);
      _notificationsController.add(deviceId);
    } catch (_) {}
  }

  Future<bool> _sendTelegramMessage(String text) async {
    if (_botToken.isEmpty || _chatId.isEmpty) return false;
    try {
      final uri = Uri.parse('https://api.telegram.org/bot$_botToken/sendMessage');
      final req = await _httpClient.postUrl(uri);
      req.headers.contentType = ContentType.json;
      final body = jsonEncode({
        'chat_id': _chatId,
        'text': text,
        'disable_web_page_preview': true,
      });
      req.write(body);
      final res = await req.close();
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<List<PcDevice>> watchDevices(String userId) async* {
    yield await _store.loadDevices(userId);
    yield* _store.watchDevices(userId);
  }

  @override
  Stream<List<OpenApp>> watchOpenApps(String deviceId) async* {
    yield _openApps[deviceId] ?? const [];
    await for (final id in _openAppsController.stream) {
      if (id == deviceId) yield _openApps[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<InstalledApp>> watchInstalledApps(String deviceId) async* {
    yield _installedApps[deviceId] ?? const [];
    await for (final id in _installedAppsController.stream) {
      if (id == deviceId) yield _installedApps[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<BlockedItem>> watchBlockedItems(String deviceId) async* {
    yield _blockedItems[deviceId] ?? const [];
    await for (final id in _blockedItemsController.stream) {
      if (id == deviceId) yield _blockedItems[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<PathRule>> watchPathRules(String deviceId) async* {
    yield _pathRules[deviceId] ?? const [];
    await for (final id in _pathRulesController.stream) {
      if (id == deviceId) yield _pathRules[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<PermissionRequest>> watchPermissionRequests(String deviceId) async* {
    yield _permissionRequests[deviceId] ?? const [];
    await for (final id in _permissionRequestsController.stream) {
      if (id == deviceId) yield _permissionRequests[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<InstallRequest>> watchInstallRequests(String deviceId) async* {
    yield _installRequests[deviceId] ?? const [];
    await for (final id in _installRequestsController.stream) {
      if (id == deviceId) yield _installRequests[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<ScreenshotItem>> watchScreenshots(String deviceId) async* {
    yield _screenshots[deviceId] ?? const [];
    await for (final id in _screenshotsController.stream) {
      if (id == deviceId) yield _screenshots[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<LogEntry>> watchRequestedLogs(String deviceId) async* {
    yield _logs[deviceId] ?? const [];
    await for (final id in _logsController.stream) {
      if (id == deviceId) yield _logs[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<DeviceNotification>> watchNotifications(String deviceId) async* {
    yield _notifications[deviceId] ?? const [];
    await for (final id in _notificationsController.stream) {
      if (id == deviceId) yield _notifications[deviceId] ?? const [];
    }
  }

  @override
  Stream<List<CommandResponse>> watchCommandResponses(String deviceId) async* {
    yield _commandResponses[deviceId] ?? const [];
    await for (final id in _commandResponsesController.stream) {
      if (id == deviceId) yield _commandResponses[deviceId] ?? const [];
    }
  }

  @override
  Future<void> markNotificationRead({
    required String deviceId,
    required String notificationId,
  }) async {
    final list = _notifications[deviceId];
    if (list != null) {
      final index = list.indexWhere((e) => e.id == notificationId);
      if (index >= 0) {
        final old = list[index];
        list[index] = DeviceNotification(
          id: old.id,
          title: old.title,
          message: old.message,
          type: old.type,
          severity: old.severity,
          read: true,
          createdAt: old.createdAt,
          payload: old.payload,
        );
        _notificationsController.add(deviceId);
      }
    }
  }

  @override
  Future<void> pairDeviceByQrPayload({
    required String userId,
    required String qrPayload,
  }) async {
    try {
      final map = jsonDecode(qrPayload) as Map<String, dynamic>;
      final deviceId = (map['deviceId'] ?? map['id'] ?? '').toString();
      if (deviceId.isEmpty) throw StateError('معرف الجهاز غير صالح');

      final device = PcDevice.fromMap(deviceId, map);
      await _store.upsertDevice(userId, device);

      if (map['telegramBotToken'] != null &&
          map['telegramBotToken'].toString().isNotEmpty) {
        await updateConfig(token: map['telegramBotToken'].toString());
      }
      if (map['telegramChatId'] != null &&
          map['telegramChatId'].toString().isNotEmpty) {
        await updateConfig(chat: map['telegramChatId'].toString());
      }

      await sendCommand(
        userId: userId,
        deviceId: deviceId,
        type: CommandType.checkConnection,
      );
    } catch (e) {
      throw StateError('فشل ربط الجهاز عبر رمز QR: $e');
    }
  }

  @override
  Future<void> removeDevice({
    required String userId,
    required String deviceId,
  }) async {
    await _store.removeDevice(userId, deviceId);
  }

  @override
  Future<String> sendCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    Map<String, dynamic> payload = const {},
    DateTime? executeAt,
  }) async {
    final commandId = const Uuid().v4();
    final envelope = {
      'id': commandId,
      'deviceId': deviceId,
      'type': type.wireName,
      'payload': payload,
      'userId': userId,
      if (executeAt != null) 'executeAt': executeAt.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    };

    final message = '#KIOM_CMD\n${jsonEncode(envelope)}';
    await _sendTelegramMessage(message);

    // Initial sent ack
    final ack = CommandResponse(
      id: const Uuid().v4(),
      commandId: commandId,
      deviceId: deviceId,
      commandType: type.wireName,
      phase: 'sent',
      success: true,
      message: 'تم إرسال الأمر عبر سحابة Telegram',
      createdAt: DateTime.now(),
    );
    _commandResponses.putIfAbsent(deviceId, () => []).insert(0, ack);
    _commandResponsesController.add(deviceId);

    return commandId;
  }

  @override
  Future<void> cancelCommand({
    required String deviceId,
    required String commandId,
  }) async {
    final body = jsonEncode({
      'id': const Uuid().v4(),
      'deviceId': deviceId,
      'type': 'cancel_scheduled_power_command',
      'payload': {'commandId': commandId},
      'createdAt': DateTime.now().toIso8601String(),
    });
    await _sendTelegramMessage('#KIOM_CMD\n$body');
  }

  @override
  Future<CommandResponse?> waitForCommandResponse({
    required String deviceId,
    required String commandId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final existingList = _commandResponses[deviceId];
    if (existingList != null) {
      for (final e in existingList) {
        if (e.commandId == commandId && e.isFinalPhase) {
          return e;
        }
      }
    }

    final completer = Completer<CommandResponse>();
    _pendingResponseCompleters[commandId] = completer;

    try {
      return await completer.future.timeout(timeout);
    } catch (_) {
      _pendingResponseCompleters.remove(commandId);
      return null;
    }
  }

  @override
  Future<RemoteFileListing> browsePath({
    required String userId,
    required String deviceId,
    required String path,
  }) async {
    final requestId = const Uuid().v4();
    final completer = Completer<RemoteFileListing>();
    _pendingFileCompleters[requestId] = completer;

    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.browsePath,
      payload: {'path': path, 'requestId': requestId},
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 12));
    } catch (_) {
      _pendingFileCompleters.remove(requestId);
      return RemoteFileListing(path: path, items: const []);
    }
  }

  @override
  Future<RemoteFileListing> searchFiles({
    required String userId,
    required String deviceId,
    required String query,
    String rootPath = 'home',
    int limit = 100,
  }) async {
    final requestId = const Uuid().v4();
    final completer = Completer<RemoteFileListing>();
    _pendingFileCompleters[requestId] = completer;

    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.searchFiles,
      payload: {
        'query': query,
        'rootPath': rootPath,
        'limit': limit,
        'requestId': requestId,
      },
    );

    try {
      return await completer.future.timeout(const Duration(seconds: 15));
    } catch (_) {
      _pendingFileCompleters.remove(requestId);
      return RemoteFileListing(path: rootPath, items: const []);
    }
  }

  @override
  Future<CommandResponse?> runFileCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    required String path,
    Map<String, dynamic> payload = const {},
  }) async {
    final combined = <String, dynamic>{'path': path, ...payload};
    final cmdId = await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: type,
      payload: combined,
    );
    return waitForCommandResponse(deviceId: deviceId, commandId: cmdId);
  }

  @override
  Future<void> savePathRule({
    required String userId,
    required String deviceId,
    required PathRule rule,
  }) async {
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.addPathRule,
      payload: rule.toMap(),
    );
  }

  @override
  Future<void> removePathRule({
    required String userId,
    required String deviceId,
    required String ruleId,
  }) async {
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.removePathRule,
      payload: {'ruleId': ruleId},
    );
  }

  @override
  Future<void> answerPermission({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  }) async {
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve ? CommandType.approvePermission : CommandType.rejectPermission,
      payload: {
        'requestId': requestId,
        'always': always,
        if (duration != null) 'durationSeconds': duration.inSeconds,
      },
    );
  }

  @override
  Future<void> answerInstall({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  }) async {
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve ? CommandType.approveInstall : CommandType.rejectInstall,
      payload: {
        'requestId': requestId,
        'always': always,
        if (duration != null) 'durationSeconds': duration.inSeconds,
      },
    );
  }

  @override
  Future<void> deleteScreenshot({
    required String deviceId,
    required ScreenshotItem screenshot,
  }) async {
    final list = _screenshots[deviceId];
    if (list != null) {
      list.removeWhere((e) => e.id == screenshot.id);
      _screenshotsController.add(deviceId);
    }
  }

  @override
  Future<void> clearRequestedLogs(String deviceId) async {
    _logs[deviceId]?.clear();
    _logsController.add(deviceId);
  }

  @override
  Future<void> clearCommandResponses(String deviceId) async {
    _commandResponses[deviceId]?.clear();
    _commandResponsesController.add(deviceId);
  }
}
