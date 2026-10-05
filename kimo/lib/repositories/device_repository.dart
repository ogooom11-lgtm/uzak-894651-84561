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

abstract class DeviceRepository {
  Stream<List<PcDevice>> watchDevices(String userId);
  Stream<List<OpenApp>> watchOpenApps(String deviceId);
  Stream<List<PathRule>> watchPathRules(String deviceId);
  Stream<List<PermissionRequest>> watchPermissionRequests(String deviceId);
  Stream<List<InstallRequest>> watchInstallRequests(String deviceId);
  Stream<List<InstalledApp>> watchInstalledApps(String deviceId);
  Stream<List<BlockedItem>> watchBlockedItems(String deviceId);
  Stream<List<ScreenshotItem>> watchScreenshots(String deviceId);
  Stream<List<LogEntry>> watchRequestedLogs(String deviceId);
  Stream<List<CommandResponse>> watchCommandResponses(String deviceId);

  Future<void> pairDeviceByQrPayload({
    required String userId,
    required String qrPayload,
  });

  Future<void> removeDevice({
    required String userId,
    required String deviceId,
  });

  Future<String> sendCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    Map<String, dynamic> payload = const {},
    DateTime? executeAt,
  });

  Future<CommandResponse?> waitForCommandResponse({
    required String deviceId,
    required String commandId,
    Duration timeout = const Duration(seconds: 10),
  });

  Future<RemoteFileListing> browsePath({
    required String userId,
    required String deviceId,
    required String path,
  });

  Future<CommandResponse?> runFileCommand({
    required String userId,
    required String deviceId,
    required CommandType type,
    required String path,
    Map<String, dynamic> payload,
  });

  Future<void> savePathRule({
    required String userId,
    required String deviceId,
    required PathRule rule,
  });

  Future<void> removePathRule({
    required String userId,
    required String deviceId,
    required String ruleId,
  });

  Future<void> answerPermission({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  });

  Future<void> answerInstall({
    required String userId,
    required String deviceId,
    required String requestId,
    required bool approve,
    Duration? duration,
    bool always = false,
  });

  Future<void> deleteScreenshot({
    required String deviceId,
    required ScreenshotItem screenshot,
  });

  Future<void> clearRequestedLogs(String deviceId);
  Future<void> clearCommandResponses(String deviceId);
}
