import 'dart:convert';
import 'dart:io';

import '../config/agent_config.dart';
import '../services/application_blocker_service.dart';
import '../services/command_executor_service.dart';
import '../services/connectivity_notifier_service.dart';
import '../services/desktop_lock_service.dart';
import '../services/device_identity_service.dart';
import '../services/dialog_service.dart';
import '../services/firestore_rest_client.dart';
import '../services/hotkey_pairing_qr_service.dart';
import '../services/installed_apps_sync_service.dart';
import '../services/installation_guard_service.dart';
import '../services/local_logs_center_hotkey_service.dart';
import '../services/open_apps_sync_service.dart';
import '../services/path_guard_service.dart';
import '../services/path_rule_store.dart';
import '../services/permission_center_hotkey_service.dart';
import '../services/permission_state_service.dart';
import '../services/process_monitor_service.dart';
import '../services/single_instance_service.dart';
import '../services/startup_registration_service.dart';
import '../services/startup_task_service.dart';
import '../services/telegram_cloud_database_service.dart';
import '../services/telegram_command_service.dart';
import '../services/telegram_notifier_service.dart';
import '../utils/json_file_store.dart';

class KiomPcAgentApp {
  HotkeyPairingQrService? _qrHotkey;
  PermissionCenterHotkeyService? _permissionCenter;
  LocalLogsCenterHotkeyService? _logsCenter;
  OpenAppsSyncService? _openAppsSync;
  InstalledAppsSyncService? _installedAppsSync;
  InstallationGuardService? _installationGuard;
  DesktopLockService? _desktopLock;
  ApplicationBlockerService? _appBlocker;
  ConnectivityNotifierService? _connectivityNotifier;
  CommandExecutorService? _commandExecutor;
  TelegramCommandService? _telegramCommands;
  TelegramCloudDatabaseService? _telegramCloudDb;
  PathGuardService? _pathGuard;

  TelegramCloudDatabaseService? get telegramCloudDb => _telegramCloudDb;

  Future<void> start() async {
    final config = await AgentConfig.load();
    final store = await JsonFileStore.open();
    final identity = DeviceIdentityService(store, config);
    final device = await identity.getOrCreateDevice();
    final deviceId = device['deviceId'].toString();
    final firestore = FirestoreRestClient(config, store: store);
    final pathRuleStore = PathRuleStore(store);
    final permissions = PermissionStateService(store);
    final telegram = TelegramNotifierService(config: config, store: store);

    await SingleInstanceService(store: store).keepOnlyCurrentProcess();
    await StartupTaskService(store: store).ensureInstalledPromptOnce();

    await permissions.ensureInitialized();
    await permissions.refreshDirectWindowsAvailability();

    stdout.writeln('KIOM PC Agent started. DeviceId=$deviceId');

    await store.appendLog('agent_start', 'تشغيل KIOM PC Agent', {
      'deviceId': deviceId,
    });
    await _notifyOnlineOnce(
      store: store,
      telegram: telegram,
      deviceId: deviceId,
      deviceName: device['name'].toString(),
    );
    _connectivityNotifier = ConnectivityNotifierService(
      deviceId: deviceId,
      deviceName: device['name'].toString(),
      store: store,
      telegram: telegram,
    )..start();

    var wasRegistered = false;
    try {
      wasRegistered = await firestore.documentExists('devices/$deviceId');
    } catch (e) {
      await store.appendLog(
          'device_exists_check_error', e.toString(), {'deviceId': deviceId});
    }

    try {
      if (!wasRegistered) {
        await firestore.registerDevice(
          deviceId: deviceId,
          name: device['name'].toString(),
          os: device['os'].toString(),
          windowsUser: device['windowsUser'].toString(),
          appVersion: device['appVersion'].toString(),
        );

        await store.appendLog('device_registered',
            'تم تسجيل الكمبيوتر في Firestore', {'deviceId': deviceId});
      } else {
        await firestore.setDocument('devices/$deviceId', {
          'name': device['name'].toString(),
          'os': device['os'].toString(),
          'windowsUser': device['windowsUser'].toString(),
          'appVersion': device['appVersion'].toString(),
          'linkedUserIds': [config.demoUserId],
          'lastAgentStartedAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      await store.appendLog('device_register_or_update_error', e.toString(), {
        'deviceId': deviceId,
      });
    }

    try {
      await firestore.setDocument('devices/$deviceId', {
        'permissionState': permissions.toFirestoreMap(),
        'legacyHelperRemoved': true,
        'nativeControlMode': 'direct_windows',
        'nativeControlUpdatedAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      await store.appendLog('permission_state_cloud_error', e.toString(), {
        'deviceId': deviceId,
      });
    }

    if (config.enableStartupRegistrationFromCode &&
        permissions.isAllowed('startupRegistration')) {
      try {
        await StartupRegistrationService().registerCurrentExecutable();
      } catch (e) {
        await store.appendLog('startup_registration_error', e.toString());
      }
    }

    if (config.autoCreatePairingToken) {
      try {
        final payload = await identity.createPairingPayload();
        await firestore.createPairingToken(
          token: payload['pairingToken'].toString(),
          deviceId: deviceId,
          securityKey: payload['securityKey'].toString(),
          expiresAt: DateTime.parse(payload['expiresAt'].toString()),
        );
        final filePath = '${store.dir.path}\\pairing_payload.json';
        await store.appendLog(
            'pairing_token', 'تم إنشاء Token ربط', {'file': filePath});
        stdout.writeln('PAIRING_PAYLOAD_FILE=$filePath');
        stdout.writeln(const JsonEncoder.withIndent('  ').convert(payload));
      } catch (e) {
        await store.appendLog('pairing_token_error', e.toString());
      }
    }

    _qrHotkey = HotkeyPairingQrService(
      deviceId: deviceId,
      store: store,
      identity: identity,
      firestore: firestore,
    )..start();

    _permissionCenter = PermissionCenterHotkeyService(
      deviceId: deviceId,
      store: store,
      permissions: permissions,
      firestore: firestore,
    );
    await _permissionCenter!.start();

    _logsCenter = LocalLogsCenterHotkeyService(
      store: store,
      deviceId: deviceId,
      firestore: firestore,
    )..start();

    _openAppsSync = OpenAppsSyncService(
      deviceId: deviceId,
      config: config,
      firestore: firestore,
      monitor: ProcessMonitorService(),
      store: store,
    )..start();

    _desktopLock = DesktopLockService(store: store)..start();
    _appBlocker = ApplicationBlockerService(
      store: store,
      telegram: telegram,
    )..start();
    try {
      await firestore.syncBlockedItems(deviceId, _appBlocker!.cloudItems());
    } catch (e) {
      await store.appendLog('blocked_items_sync_error', e.toString(), {
        'deviceId': deviceId,
      });
    }

    if (permissions.isAllowed('installedApps')) {
      _installedAppsSync = InstalledAppsSyncService(
        deviceId: deviceId,
        firestore: firestore,
        store: store,
      )..start();
    }

    if (permissions.isAllowed('installProtection')) {
      _installationGuard = InstallationGuardService(
        deviceId: deviceId,
        firestore: firestore,
        store: store,
        telegram: telegram,
      )..start();
    }

    _commandExecutor = CommandExecutorService(
      deviceId: deviceId,
      config: config,
      store: store,
      firestore: firestore,
      pathRules: pathRuleStore,
      dialogs: DialogService(),
      permissions: permissions,
      desktopLock: _desktopLock,
      appBlocker: _appBlocker,
      telegram: telegram,
    )..start();

    _telegramCommands = TelegramCommandService(
      deviceId: deviceId,
      deviceName: device['name'].toString(),
      store: store,
      telegram: telegram,
      executor: _commandExecutor!,
    )..start();

    _telegramCloudDb = TelegramCloudDatabaseService(
      deviceId: deviceId,
      deviceName: device['name'].toString(),
      config: config,
      store: store,
      telegram: telegram,
      executor: _commandExecutor!,
      appBlocker: _appBlocker!,
      pathRuleStore: pathRuleStore,
    )..start();

    _pathGuard = PathGuardService(
      deviceId: deviceId,
      config: config,
      store: store,
      ruleStore: pathRuleStore,
      dialogs: DialogService(),
      firestore: firestore,
      telegram: telegram,
    )..start();
  }

  Future<void> _notifyOnlineOnce({
    required JsonFileStore store,
    required TelegramNotifierService telegram,
    required String deviceId,
    required String deviceName,
  }) async {
    if (!telegram.isConfigured) return;
    final now = DateTime.now();
    final last = DateTime.tryParse(
      (store.get<String>('lastTelegramOnlineAt') ?? '').toString(),
    );
    if (last != null && now.difference(last).inMinutes < 10) return;

    final sent = await telegram.sendMessage(
      'KIOM: الآن متصل\nالجهاز: $deviceName\nالمعرف: $deviceId',
    );
    if (sent) {
      await store.set('lastTelegramOnlineAt', now.toIso8601String());
    }
  }

  void stop() {
    _qrHotkey?.stop();
    _permissionCenter?.stop();
    _logsCenter?.stop();
    _openAppsSync?.stop();
    _installedAppsSync?.stop();
    _installationGuard?.stop();
    _desktopLock?.stop();
    _appBlocker?.stop();
    _connectivityNotifier?.stop();
    _commandExecutor?.stop();
    _telegramCommands?.stop();
    _telegramCloudDb?.stop();
    _pathGuard?.stop();
  }
}
