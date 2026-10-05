import 'dart:async';
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/command_type.dart';
import '../models/blocked_item.dart';
import '../models/command_response.dart';
import '../models/install_request.dart';
import '../models/installed_app.dart';
import '../models/log_entry.dart';
import '../models/open_app.dart';
import '../models/path_rule.dart';
import '../models/pc_device.dart';
import '../models/permission_request.dart';
import '../models/remote_file_item.dart';
import '../models/screenshot_item.dart';
import 'device_repository.dart';

class MockDeviceRepository implements DeviceRepository {
  MockDeviceRepository() {
    _devices = [
      PcDevice(
        id: 'pc_demo_001',
        name: 'DESKTOP-AHMAD',
        os: 'Windows 11',
        appVersion: '1.0.0',
        createdAt: DateTime.now().subtract(const Duration(days: 7)),
        linkedUserIds: const ['local_demo_user'],
        lastCheckResponse: 'Online',
        lastSeenAt: DateTime.now(),
        wifiStatus: 'on',
        bluetoothStatus: 'off',
        volume: 65,
      ),
      PcDevice(
        id: 'pc_demo_002',
        name: 'LAPTOP-WORK',
        os: 'Windows 10',
        appVersion: '1.0.0',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        linkedUserIds: const ['local_demo_user'],
        lastCheckResponse: 'Offline',
        lastSeenAt: DateTime.now().subtract(const Duration(minutes: 45)),
        wifiStatus: 'unknown',
        bluetoothStatus: 'unknown',
        volume: 0,
      ),
    ];

    _openApps = [
      OpenApp(
        id: 'chrome_youtube_demo',
        processId: '4520',
        appName: 'Google Chrome',
        appPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        openedAt: DateTime.now().subtract(const Duration(minutes: 12)),
        status: 'running',
        iconKey: 'youtube',
        windowTitle: 'YouTube - Google Chrome',
        pageTitle: 'YouTube',
        url: 'https://www.youtube.com/',
        siteName: 'YouTube',
        browserName: 'Chrome',
        lastUpdated: DateTime.now(),
      ),
      OpenApp(
        id: 'chrome_gmail_demo',
        processId: '4520',
        appName: 'Google Chrome',
        appPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
        openedAt: DateTime.now().subtract(const Duration(minutes: 9)),
        status: 'running',
        iconKey: 'gmail',
        windowTitle: 'Inbox - Gmail - Google Chrome',
        pageTitle: 'Inbox - Gmail',
        url: 'https://mail.google.com/',
        siteName: 'Gmail',
        browserName: 'Chrome',
        lastUpdated: DateTime.now(),
      ),
      OpenApp(
        id: 'word_demo',
        processId: '6604',
        appName: 'Microsoft Word',
        appPath: r'C:\Program Files\Microsoft Office\root\Office16\WINWORD.EXE',
        openedAt: DateTime.now().subtract(const Duration(minutes: 31)),
        status: 'running',
        iconKey: 'word',
        lastUpdated: DateTime.now(),
      ),
      OpenApp(
        id: 'telegram_demo',
        processId: '9112',
        appName: 'Telegram',
        appPath:
            r'C:\Users\Ahmad\AppData\Roaming\Telegram Desktop\Telegram.exe',
        openedAt: DateTime.now().subtract(const Duration(hours: 1)),
        status: 'running',
        iconKey: 'telegram',
        lastUpdated: DateTime.now(),
      ),
    ];

    _rules = [
      PathRule(
        id: 'rule_demo_001',
        path: r'D:\Private',
        lockType: 'permission_required',
        blockOpen: true,
        blockDelete: true,
        blockCopy: true,
        blockMove: true,
        blockRename: true,
        blockModify: true,
        permissionEveryTime: true,
        createdAt: DateTime.now().subtract(const Duration(days: 2)),
        updatedAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ];

    _permissionRequests = [
      PermissionRequest(
        id: 'permission_demo_001',
        deviceId: 'pc_demo_001',
        type: 'path_access',
        title: 'طلب فتح مسار محمي',
        targetPath: r'D:\Private',
        status: 'pending',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        details: 'المستخدم يحاول فتح مجلد خاص.',
      ),
    ];

    _installRequests = [
      InstallRequest(
        id: 'install_demo_001',
        deviceId: 'pc_demo_001',
        fileName: 'setup.exe',
        filePath: r'C:\Users\Ahmad\Downloads\setup.exe',
        status: 'pending',
        createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
      ),
    ];

    _installedApps = [
      const InstalledApp(
        id: 'chrome',
        name: 'Google Chrome',
        publisher: 'Google LLC',
        version: '124.0',
        installLocation: r'C:\Program Files\Google\Chrome',
        iconKey: 'chrome',
      ),
      const InstalledApp(
        id: 'vscode',
        name: 'Visual Studio Code',
        publisher: 'Microsoft',
        version: '1.90',
        installLocation:
            r'C:\Users\Ahmad\AppData\Local\Programs\Microsoft VS Code',
        iconKey: 'vscode',
      ),
      const InstalledApp(
        id: 'telegram',
        name: 'Telegram Desktop',
        publisher: 'Telegram',
        version: '5.0',
        installLocation: r'C:\Users\Ahmad\AppData\Roaming\Telegram Desktop',
        iconKey: 'telegram',
      ),
    ];

    _blockedItems = [
      BlockedItem(
        id: 'chrome',
        type: 'app',
        target: 'chrome.exe',
        label: 'Google Chrome',
        createdAt: DateTime.now().subtract(const Duration(minutes: 20)),
      ),
      BlockedItem(
        id: 'youtube',
        type: 'site',
        target: 'youtube.com',
        label: 'YouTube',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    ];

    _screenshots = [
      ScreenshotItem(
        id: 'shot_demo_001',
        deviceId: 'pc_demo_001',
        imageUrl: 'https://placehold.co/900x520/png?text=Windows+Screenshot',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    ];

    _logs = [
      LogEntry(
        id: 'log_demo_001',
        type: 'command',
        message: 'تم تنفيذ أمر رفع الصوت إلى 65%',
        target: 'volume',
        createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
      ),
      LogEntry(
        id: 'log_demo_002',
        type: 'path',
        message: 'محاولة فتح مسار محمي',
        target: r'D:\Private',
        createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
      ),
    ];
  }

  final _uuid = const Uuid();
  final _devicesController = StreamController<List<PcDevice>>.broadcast();
  final _openAppsController = StreamController<List<OpenApp>>.broadcast();
  final _rulesController = StreamController<List<PathRule>>.broadcast();
  final _permissionController =
      StreamController<List<PermissionRequest>>.broadcast();
  final _installController = StreamController<List<InstallRequest>>.broadcast();
  final _installedAppsController =
      StreamController<List<InstalledApp>>.broadcast();
  final _blockedItemsController =
      StreamController<List<BlockedItem>>.broadcast();
  final _screenshotsController =
      StreamController<List<ScreenshotItem>>.broadcast();
  final _logsController = StreamController<List<LogEntry>>.broadcast();
  final _responsesController =
      StreamController<List<CommandResponse>>.broadcast();

  late List<PcDevice> _devices;
  late List<OpenApp> _openApps;
  late List<PathRule> _rules;
  late List<PermissionRequest> _permissionRequests;
  late List<InstallRequest> _installRequests;
  late List<InstalledApp> _installedApps;
  late List<BlockedItem> _blockedItems;
  late List<ScreenshotItem> _screenshots;
  late List<LogEntry> _logs;
  List<CommandResponse> _responses = [];

  Stream<List<T>> _withInitial<T>(
      List<T> value, StreamController<List<T>> controller) async* {
    yield List<T>.unmodifiable(value);
    yield* controller.stream;
  }

  @override
  Stream<List<PcDevice>> watchDevices(String userId) =>
      _withInitial(_devices, _devicesController);

  @override
  Stream<List<OpenApp>> watchOpenApps(String deviceId) =>
      _withInitial(_openApps, _openAppsController);

  @override
  Stream<List<PathRule>> watchPathRules(String deviceId) =>
      _withInitial(_rules, _rulesController);

  @override
  Stream<List<PermissionRequest>> watchPermissionRequests(String deviceId) =>
      _withInitial(_permissionRequests, _permissionController);

  @override
  Stream<List<InstallRequest>> watchInstallRequests(String deviceId) =>
      _withInitial(_installRequests, _installController);

  @override
  Stream<List<InstalledApp>> watchInstalledApps(String deviceId) =>
      _withInitial(_installedApps, _installedAppsController);

  @override
  Stream<List<BlockedItem>> watchBlockedItems(String deviceId) =>
      _withInitial(_blockedItems, _blockedItemsController);

  @override
  Stream<List<ScreenshotItem>> watchScreenshots(String deviceId) =>
      _withInitial(_screenshots, _screenshotsController);

  @override
  Stream<List<LogEntry>> watchRequestedLogs(String deviceId) =>
      _withInitial(_logs, _logsController);

  @override
  Stream<List<CommandResponse>> watchCommandResponses(String deviceId) =>
      _withInitial(_responses, _responsesController);

  @override
  Future<void> pairDeviceByQrPayload({
    required String userId,
    required String qrPayload,
  }) async {
    try {
      final decoded = jsonDecode(qrPayload) as Map<String, dynamic>;
      final id =
          decoded['deviceId']?.toString() ?? 'pc_${_uuid.v4().substring(0, 8)}';
      final name = decoded['name']?.toString() ?? 'جهاز جديد';
      _devices = [
        PcDevice(
          id: id,
          name: name,
          os: decoded['os']?.toString() ?? 'Windows',
          appVersion: '1.0.0',
          createdAt: DateTime.now(),
          linkedUserIds: [userId],
          lastCheckResponse: 'Paired in demo mode',
          lastSeenAt: DateTime.now(),
        ),
        ..._devices,
      ];
      _devicesController.add(List.unmodifiable(_devices));
    } catch (_) {
      throw Exception('رمز QR غير صالح. يجب أن يحتوي على JSON فيه deviceId.');
    }
  }

  @override
  Future<void> removeDevice({
    required String userId,
    required String deviceId,
  }) async {
    _devices = _devices.where((device) => device.id != deviceId).toList();
    _devicesController.add(List.unmodifiable(_devices));
  }

  @override
  Future<String> sendCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    Map<String, dynamic> payload = const {},
    DateTime? executeAt,
  }) async {
    final id = _uuid.v4();
    final log = LogEntry(
      id: id,
      type: 'command',
      message: 'تم إرسال أمر: ${type.arabicTitle}',
      target: payload['target']?.toString(),
      createdAt: DateTime.now(),
      payload: payload,
    );
    _logs = [log, ..._logs];
    _logsController.add(List.unmodifiable(_logs));

    final response = CommandResponse(
      id: 'response_$id',
      commandId: id,
      success: true,
      message: 'تم استلام الأمر في وضع التجربة: ${type.arabicTitle}',
      createdAt: DateTime.now(),
      phase: 'final',
      commandType: type.wireName,
      deviceId: deviceId,
      payload: payload,
    );
    _responses = [response, ..._responses];
    _responsesController.add(List.unmodifiable(_responses));

    if (type == CommandType.closeApplication && payload['processId'] != null) {
      _openApps = _openApps
          .where((app) => app.processId != payload['processId'].toString())
          .toList();
      _openAppsController.add(List.unmodifiable(_openApps));
    }
    return id;
  }

  @override
  Future<CommandResponse?> waitForCommandResponse({
    required String deviceId,
    required String commandId,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final existing = _responses.where((r) => r.commandId == commandId).toList();
    if (existing.isNotEmpty) return existing.first;
    return null;
  }

  @override
  Future<RemoteFileListing> browsePath({
    required String userId,
    required String deviceId,
    required String path,
  }) async {
    await sendCommand(
        userId: userId,
        deviceId: deviceId,
        type: CommandType.browsePath,
        payload: {'path': path});
    final now = DateTime.now();
    final normalized = path == 'roots' ? 'roots' : path;
    if (normalized == 'roots') {
      return RemoteFileListing(
        path: 'roots',
        items: [
          RemoteFileItem(
              name: 'Windows (C:)',
              path: r'C:\',
              type: 'drive',
              modifiedAt: now,
              iconKey: 'drive'),
          RemoteFileItem(
              name: 'Data (D:)',
              path: r'D:\',
              type: 'drive',
              modifiedAt: now,
              iconKey: 'drive'),
        ],
      );
    }
    return RemoteFileListing(
      path: normalized,
      parentPath: 'roots',
      items: [
        RemoteFileItem(
            name: 'Desktop',
            path: r'C:\Users\Ahmad\Desktop',
            type: 'directory',
            modifiedAt: now,
            iconKey: 'folder'),
        RemoteFileItem(
            name: 'report.pdf',
            path: r'C:\Users\Ahmad\Desktop\report.pdf',
            type: 'file',
            extension: 'pdf',
            size: 240000,
            modifiedAt: now),
        RemoteFileItem(
            name: 'setup.exe',
            path: r'C:\Users\Ahmad\Downloads\setup.exe',
            type: 'file',
            extension: 'exe',
            size: 5400000,
            modifiedAt: now),
      ],
    );
  }

  @override
  Future<RemoteFileListing> searchFiles({
    required String userId,
    required String deviceId,
    required String query,
    String rootPath = 'home',
    int limit = 100,
  }) async {
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: CommandType.searchFiles,
      payload: {'query': query, 'rootPath': rootPath, 'limit': limit},
    );
    final now = DateTime.now();
    final files = [
      RemoteFileItem(
        name: 'report.pdf',
        path: r'C:\Users\Ahmad\Desktop\report.pdf',
        type: 'file',
        extension: 'pdf',
        size: 240000,
        modifiedAt: now,
      ),
      RemoteFileItem(
        name: 'setup.exe',
        path: r'C:\Users\Ahmad\Downloads\setup.exe',
        type: 'file',
        extension: 'exe',
        size: 5400000,
        modifiedAt: now,
      ),
      RemoteFileItem(
        name: 'Projects',
        path: r'C:\Users\Ahmad\Documents\Projects',
        type: 'directory',
        modifiedAt: now,
        iconKey: 'folder',
      ),
    ];
    final lower = query.toLowerCase();
    return RemoteFileListing(
      path: 'search:$query',
      parentPath: rootPath,
      items: files
          .where((item) => item.name.toLowerCase().contains(lower))
          .take(limit)
          .toList(),
    );
  }

  @override
  Future<CommandResponse?> runFileCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    required String path,
    Map<String, dynamic> payload = const {},
  }) async {
    final commandId = await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: type,
      payload: {'path': path, ...payload},
    );
    return waitForCommandResponse(deviceId: deviceId, commandId: commandId);
  }

  @override
  Future<void> savePathRule({
    required String userId,
    required String deviceId,
    required PathRule rule,
  }) async {
    _rules = [rule, ..._rules.where((item) => item.id != rule.id)];
    _rulesController.add(List.unmodifiable(_rules));
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
    _rules = _rules.where((item) => item.id != ruleId).toList();
    _rulesController.add(List.unmodifiable(_rules));
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
    _permissionRequests =
        _permissionRequests.where((item) => item.id != requestId).toList();
    _permissionController.add(List.unmodifiable(_permissionRequests));
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve
          ? CommandType.approvePermission
          : CommandType.rejectPermission,
      payload: {
        'requestId': requestId,
        'durationSeconds': duration?.inSeconds,
        'always': always,
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
    _installRequests =
        _installRequests.where((item) => item.id != requestId).toList();
    _installController.add(List.unmodifiable(_installRequests));
    await sendCommand(
      userId: userId,
      deviceId: deviceId,
      type: approve ? CommandType.approveInstall : CommandType.rejectInstall,
      payload: {
        'requestId': requestId,
        'durationSeconds': duration?.inSeconds,
        'always': always,
      },
    );
  }

  @override
  Future<void> deleteScreenshot({
    required String deviceId,
    required ScreenshotItem screenshot,
  }) async {
    _screenshots =
        _screenshots.where((item) => item.id != screenshot.id).toList();
    _screenshotsController.add(List.unmodifiable(_screenshots));
  }

  @override
  Future<void> clearRequestedLogs(String deviceId) async {
    _logs = [];
    _logsController.add(List.unmodifiable(_logs));
  }

  @override
  Future<void> clearCommandResponses(String deviceId) async {
    _responses = [];
    _responsesController.add(List.unmodifiable(_responses));
  }
}
