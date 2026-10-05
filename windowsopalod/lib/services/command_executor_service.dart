import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../config/agent_config.dart';
import '../models/path_rule.dart';
import '../models/remote_command.dart';
import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';
import 'application_blocker_service.dart';
import 'desktop_lock_service.dart';
import 'dialog_service.dart';
import 'file_manager_service.dart';
import 'firestore_rest_client.dart';
import 'path_rule_store.dart';
import 'permission_state_service.dart';
import 'screenshot_service.dart';
import 'telegram_notifier_service.dart';
import 'windows_control_service.dart';

class CommandExecutorService {
  final String deviceId;
  final AgentConfig config;
  final JsonFileStore store;
  final FirestoreRestClient firestore;
  final PathRuleStore pathRules;
  final DialogService dialogs;
  final PermissionStateService permissions;
  final FileManagerService fileManager;
  final DesktopLockService desktopLock;
  final ApplicationBlockerService appBlocker;
  final ScreenshotService screenshotService;
  final TelegramNotifierService telegram;
  final WindowsControlService windowsControl;

  Timer? _timer;
  Timer? _scheduledTimer;
  Future<void> _commandSerial = Future<void>.value();
  bool _pollInProgress = false;
  bool _scheduledInProgress = false;

  CommandExecutorService({
    required this.deviceId,
    required this.config,
    required this.store,
    required this.firestore,
    required this.pathRules,
    required this.dialogs,
    required this.permissions,
    FileManagerService? fileManager,
    DesktopLockService? desktopLock,
    ApplicationBlockerService? appBlocker,
    ScreenshotService? screenshotService,
    TelegramNotifierService? telegram,
    WindowsControlService? windowsControl,
  })  : fileManager = fileManager ?? FileManagerService(),
        desktopLock = desktopLock ?? DesktopLockService(store: store),
        appBlocker = appBlocker ?? ApplicationBlockerService(store: store),
        screenshotService = screenshotService ??
            ScreenshotService(config: config, store: store),
        telegram =
            telegram ?? TelegramNotifierService(config: config, store: store),
        windowsControl = windowsControl ?? WindowsControlService();

  void start() {
    _timer?.cancel();
    _scheduledTimer?.cancel();

    stdout.writeln(
        'Command executor active: polling every ${config.pollCommandsEverySeconds}s.');

    _timer = Timer.periodic(
      Duration(seconds: config.pollCommandsEverySeconds),
      (_) => _tick(),
    );

    _scheduledTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _runScheduledCommands(),
    );

    _tick();
  }

  void stop() {
    _timer?.cancel();
    _scheduledTimer?.cancel();
  }

  Future<void> _tick() async {
    if (_pollInProgress) return;
    _pollInProgress = true;
    try {
      final commands = await firestore.getPendingCommands(deviceId);
      if (commands.isNotEmpty) {
        stdout.writeln(
            'COMMAND_POLL: received ${commands.length} pending command(s).');
      }

      final ordered = [...commands]..sort((a, b) {
          final ad = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return ad.compareTo(bd);
        });

      for (final command in ordered) {
        await _execute(command);
      }
    } catch (e, st) {
      stdout.writeln('COMMAND_POLL_ERROR=$e');
      await store.appendLog(
          'command_poll_error', e.toString(), {'stack': st.toString()});
    } finally {
      _pollInProgress = false;
    }
  }

  Future<T> _runOneCommandAtATime<T>(Future<T> Function() action) {
    final previous = _commandSerial.catchError((_) {});
    final completer = Completer<T>();
    _commandSerial = previous.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<void> _execute(RemoteCommand command) {
    return _runOneCommandAtATime(() => _executeCloudUnlocked(command));
  }

  Future<CommandExecutionResult> executeTelegramCommand({
    required String type,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    final command = RemoteCommand(
      id: 'telegram_${DateTime.now().millisecondsSinceEpoch}',
      type: type,
      status: 'telegram',
      payload: payload,
      createdBy: 'telegram',
      createdAt: DateTime.now(),
    );
    return _runOneCommandAtATime(() => _executeTelegramUnlocked(command));
  }

  Future<void> _executeCloudUnlocked(RemoteCommand command) async {
    if (_wasStopAllRequestedAfter(command.createdAt)) {
      final message = 'تم إلغاء الأمر لأن المستخدم طلب إيقاف وحذف كل الأوامر';
      await store.appendLog('command_cancelled_by_stop_all', message, {
        'type': command.type,
        'commandId': command.id,
      });
      try {
        await firestore.markCommandExecuted(
          deviceId,
          command.id,
          success: false,
          message: message,
        );
      } catch (_) {}
      return;
    }

    final receivedMessage = 'تم استلام الأمر على الكمبيوتر: ${command.type}';
    stdout.writeln(
        'COMMAND_RECEIVED id=${command.id} type=${command.type} payload=${jsonEncode(command.payload)}');

    await store.appendLog('command_received', receivedMessage, {
      'type': command.type,
      'commandId': command.id,
      'payload': command.payload,
      'createdBy': command.createdBy,
    });

    try {
      await firestore.markCommandReceived(
        deviceId,
        command.id,
        type: command.type,
        message: receivedMessage,
      );
      await _writeResponse(
          command, true, receivedMessage, {'status': 'received'},
          phase: 'received');
    } catch (e, st) {
      stdout.writeln('COMMAND_ACK_FIRESTORE_ERROR id=${command.id} error=$e');
      await store.appendLog('command_ack_error', e.toString(), {
        'commandId': command.id,
        'type': command.type,
        'stack': st.toString(),
      });
    }

    bool success = false;
    String message = '';
    Map<String, dynamic> responsePayload = <String, dynamic>{};

    try {
      final permissionId = _permissionForCommand(command.type);
      if (permissionId != null && !permissions.isAllowed(permissionId)) {
        success = false;
        message = permissions.unavailableOrDeniedMessage(permissionId);
        responsePayload = {
          'permissionId': permissionId,
          'permissionName': permissions.nameOf(permissionId),
          'permissionAvailable': permissions.isAvailable(permissionId),
          'permissionAllowed': permissions.isAllowed(permissionId),
        };
      } else {
        switch (command.type) {
          case 'check_connection':
            await firestore.setDocument('devices/$deviceId', {
              'lastCheckResponse': 'Online',
              'lastCheckedAt': DateTime.now().toIso8601String(),
              'status': 'online',
            });
            success = true;
            message = 'Online - الكمبيوتر متصل واستلم الأمر بنجاح';
            break;

          case 'close_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            final pid = _parseInt(command.payload['processId']);
            final result =
                await _closeApplication(target: target, processId: pid);
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'close_application_after_delay':
            final delayMinutes =
                _parseInt(command.payload['delayMinutes']) ?? 1;
            final executeAt =
                DateTime.now().add(Duration(minutes: delayMinutes));
            final scheduled = store.list('scheduledCommands');
            scheduled.add({
              'id': command.id,
              'type': 'close_application',
              'payload': command.payload,
              'executeAt': executeAt.toIso8601String(),
              'createdAt': DateTime.now().toIso8601String(),
            });
            await store.save();
            success = true;
            message =
                'تم استلام الأمر وجدولة إغلاق التطبيق بعد $delayMinutes دقيقة';
            responsePayload = {
              'executeAt': executeAt.toIso8601String(),
              'delayMinutes': delayMinutes
            };
            break;

          case 'lock_screen':
            await desktopLock.lockNow(reason: 'remote_command');
            success = true;
            message = 'تم قفل شاشة Windows';
            responsePayload = {'lockedAt': DateTime.now().toIso8601String()};
            break;

          case 'lock_for_duration':
            final minutes = _parseInt(command.payload['minutes'] ??
                    command.payload['durationMinutes']) ??
                30;
            final until = await desktopLock.lockFor(Duration(minutes: minutes));
            success = true;
            message =
                'تم قفل الكمبيوتر لمدة $minutes دقيقة. بعد انتهاء المدة يتوقف التطبيق عن إعادة القفل، لكن Windows يحتاج كلمة المرور للفتح.';
            responsePayload = {
              'minutes': minutes,
              'until': until.toIso8601String(),
            };
            break;

          case 'lock_after_delay':
            final minutes = _parseInt(command.payload['minutes'] ??
                    command.payload['delayMinutes']) ??
                30;
            final executeAt = DateTime.now().add(Duration(minutes: minutes));
            final scheduled = store.list('scheduledCommands');
            scheduled.add({
              'id': command.id,
              'type': 'lock_screen',
              'payload': command.payload,
              'executeAt': executeAt.toIso8601String(),
              'createdAt': DateTime.now().toIso8601String(),
            });
            await store.save();
            success = true;
            message = 'سيتم قفل الكمبيوتر بعد $minutes دقيقة';
            responsePayload = {
              'minutes': minutes,
              'executeAt': executeAt.toIso8601String(),
            };
            break;

          case 'clear_timed_lock':
            await desktopLock.clearTimedLock();
            success = true;
            message = 'تم إيقاف إعادة القفل المؤقتة';
            break;

          case 'cancel_scheduled_lock':
            final scheduled = store.list('scheduledCommands');
            final before = scheduled.length;
            scheduled.removeWhere(
                (item) => item is Map && item['type'] == 'lock_screen');
            await store.save();
            final removed = before - scheduled.length;
            success = true;
            message = removed == 0
                ? 'لا يوجد قفل مجدول لإلغائه'
                : 'تم إلغاء $removed أمر قفل مجدول';
            responsePayload = {'removed': removed};
            break;

          case 'shutdown_pc':
          case 'restart_pc':
          case 'logout_user':
            if (!config.enableDangerousPowerCommands) {
              success = false;
              message =
                  'تم استلام الأمر لكن أوامر الطاقة الحساسة مقفلة من config لحماية الكمبيوتر';
            } else {
              final result = await _runPowerCommand(command.type);
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'shutdown_after_delay':
          case 'restart_after_delay':
            if (!config.enableDangerousPowerCommands) {
              success = false;
              message =
                  'تم استلام الأمر لكن أوامر الطاقة الحساسة مقفلة من config لحماية الكمبيوتر';
              break;
            }
            final delayMinutes =
                _parseInt(command.payload['delayMinutes']) ?? 10;
            final executeAt =
                DateTime.now().add(Duration(minutes: delayMinutes));
            final scheduled = store.list('scheduledCommands');
            scheduled.add({
              'id': command.id,
              'type': command.type == 'shutdown_after_delay'
                  ? 'shutdown_pc'
                  : 'restart_pc',
              'payload': command.payload,
              'executeAt': executeAt.toIso8601String(),
              'createdAt': DateTime.now().toIso8601String(),
            });
            await store.save();
            success = true;
            message = 'تمت جدولة أمر الطاقة بعد $delayMinutes دقيقة';
            responsePayload = {
              'executeAt': executeAt.toIso8601String(),
              'delayMinutes': delayMinutes,
            };
            break;

          case 'cancel_scheduled_power_command':
            final scheduled = store.list('scheduledCommands');
            final before = scheduled.length;
            scheduled.removeWhere((item) =>
                item is Map &&
                (item['type'] == 'shutdown_pc' ||
                    item['type'] == 'restart_pc'));
            await store.save();
            final removed = before - scheduled.length;
            success = true;
            message = removed == 0
                ? 'لا يوجد أمر طاقة مجدول لإلغائه'
                : 'تم إلغاء $removed أمر طاقة مجدول';
            responsePayload = {'removed': removed};
            break;

          case 'wifi_on':
          case 'wifi_off':
          case 'bluetooth_on':
          case 'bluetooth_off':
            if (!config.enableWifiBluetoothCommands) {
              success = false;
              message =
                  'تم استلام الأمر لكن أوامر WiFi/Bluetooth مقفلة من config حالياً';
              responsePayload = {'configKey': 'enableWifiBluetoothCommands'};
            } else {
              final result = command.type.startsWith('wifi')
                  ? await windowsControl.setWifi(command.type == 'wifi_on')
                  : await windowsControl
                      .setBluetooth(command.type == 'bluetooth_on');
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'internet_off_permanent':
          case 'internet_on':
            if (!config.enableWifiBluetoothCommands) {
              success = false;
              message =
                  'تم استلام الأمر لكن أوامر الشبكة مقفلة من config حالياً';
              responsePayload = {'configKey': 'enableWifiBluetoothCommands'};
            } else {
              final result = await windowsControl
                  .setInternetAdapters(command.type == 'internet_on');
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'list_bluetooth_devices':
            final result = await windowsControl.listBluetoothDevices();
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'open_bluetooth_receive':
            final result = await windowsControl.openBluetoothReceive(
              savePath: command.payload['savePath']?.toString(),
            );
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'send_bluetooth_file':
            final path =
                (command.payload['path'] ?? command.payload['filePath'] ?? '')
                    .toString();
            if (path.trim().isEmpty) throw StateError('path مطلوب');
            final result = await windowsControl.sendBluetoothFile(
              path: path,
              deviceName: command.payload['deviceName']?.toString(),
            );
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'volume_up':
          case 'volume_down':
          case 'set_volume':
          case 'mute_volume':
          case 'unmute_volume':
            WindowsControlResult result;
            if (command.type == 'volume_up') {
              result = await windowsControl.volumeUp();
            } else if (command.type == 'volume_down') {
              result = await windowsControl.volumeDown();
            } else if (command.type == 'set_volume') {
              final volume = _parseInt(command.payload['volume']);
              if (volume == null) throw StateError('volume مطلوب');
              result = await windowsControl.setVolume(volume);
            } else {
              result =
                  await windowsControl.setMuted(command.type == 'mute_volume');
            }
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            if (success && responsePayload.containsKey('volume')) {
              await firestore.setDocument('devices/$deviceId', {
                'volume': responsePayload['volume'],
                'muted': responsePayload['muted'] == true,
                'lastVolumeChangedAt': DateTime.now().toIso8601String(),
              });
            }
            break;

          case 'show_pairing_qr':
            await _touchTriggerFile('show_qr_now.txt');
            success = true;
            message = 'تم طلب إظهار رمز الربط على الكمبيوتر';
            break;

          case 'show_permission_center':
            await _touchTriggerFile('show_permissions_now.txt');
            success = true;
            message = 'تم طلب فتح شاشة أذونات الكمبيوتر';
            break;

          case 'show_message':
            final text =
                (command.payload['message'] ?? command.payload['text'] ?? '')
                    .toString();
            if (text.trim().isEmpty) throw StateError('message مطلوب');
            final title = (command.payload['title'] ?? 'KIOM').toString();
            await dialogs.showInfo(title: title, message: text);
            success = true;
            message = 'تم عرض الرسالة على الكمبيوتر';
            responsePayload = {'title': title, 'message': text};
            break;

          case 'block_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('target مطلوب');
            await appBlocker.blockApp(
              target: target,
              appName: command.payload['appName']?.toString(),
              appPath: command.payload['appPath']?.toString(),
            );
            await _syncBlockedItemsBestEffort();
            await telegram.sendMessage(
              'KIOM: تم منع تطبيق\n'
              'التطبيق: ${command.payload['appName'] ?? target}\n'
              'الجهاز: $deviceId',
            );
            success = true;
            message = 'تم منع التطبيق وسيتم إغلاقه كلما فُتح';
            responsePayload = {
              'target': target,
              'blockedItems': appBlocker.cloudItems(),
            };
            break;

          case 'allow_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('target مطلوب');
            final durationSeconds =
                _parseInt(command.payload['durationSeconds']);
            final duration = durationSeconds == null || durationSeconds <= 0
                ? null
                : Duration(seconds: durationSeconds);
            await appBlocker.allowApp(target, duration: duration);
            await _syncBlockedItemsBestEffort();
            await telegram.sendMessage(
              duration == null
                  ? 'KIOM: تم رفع منع تطبيق\nالتطبيق: $target\nالجهاز: $deviceId'
                  : 'KIOM: تم السماح المؤقت لتطبيق\n'
                      'التطبيق: $target\n'
                      'المدة: ${duration.inMinutes} دقيقة\n'
                      'الجهاز: $deviceId',
            );
            success = true;
            message = duration == null
                ? 'تم إلغاء منع التطبيق'
                : 'تم السماح للتطبيق لمدة ${duration.inMinutes} دقيقة';
            responsePayload = {
              'target': target,
              'durationSeconds': durationSeconds,
              'blockedItems': appBlocker.cloudItems(),
            };
            break;

          case 'block_website':
            final target =
                (command.payload['domain'] ?? command.payload['target'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('domain مطلوب');
            await appBlocker.blockSite(
              target,
              lockType: (command.payload['lockType'] ?? 'blocked').toString(),
              password: command.payload['password']?.toString(),
              passwordHash: command.payload['passwordHash']?.toString(),
            );
            await _syncBlockedItemsBestEffort();
            await telegram.sendMessage(
              'KIOM: تم منع موقع\nالموقع: $target\nالجهاز: $deviceId',
            );
            success = true;
            message = 'تم منع الموقع على هذا الكمبيوتر';
            responsePayload = {
              'target': target,
              'blockedItems': appBlocker.cloudItems(),
            };
            break;

          case 'allow_website':
            final target =
                (command.payload['domain'] ?? command.payload['target'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('domain مطلوب');
            final durationSeconds =
                _parseInt(command.payload['durationSeconds']);
            final duration = durationSeconds == null || durationSeconds <= 0
                ? null
                : Duration(seconds: durationSeconds);
            await appBlocker.allowSite(target, duration: duration);
            await _syncBlockedItemsBestEffort();
            await telegram.sendMessage(
              duration == null
                  ? 'KIOM: تم رفع منع موقع\nالموقع: $target\nالجهاز: $deviceId'
                  : 'KIOM: تم السماح المؤقت لموقع\n'
                      'الموقع: $target\n'
                      'المدة: ${duration.inMinutes} دقيقة\n'
                      'الجهاز: $deviceId',
            );
            success = true;
            message = duration == null
                ? 'تم إلغاء منع الموقع'
                : 'تم السماح للموقع لمدة ${duration.inMinutes} دقيقة';
            responsePayload = {
              'target': target,
              'durationSeconds': durationSeconds,
              'blockedItems': appBlocker.cloudItems(),
            };
            break;

          case 'request_logs':
            final logs = _filterLogs(command.payload);
            await firestore.writeRequestedLogs(deviceId, logs);
            responsePayload = {
              'count': logs.length,
              'from': command.payload['from'],
              'to': command.payload['to'],
              'logType': command.payload['logType'] ?? 'all',
            };
            success = true;
            message = 'تم إرسال ${logs.length} سجل حسب الفترة المطلوبة';
            break;

          case 'add_path_rule':
          case 'update_path_rule':
            await _upsertPathRule(command.payload);
            success = true;
            message = 'تم استلام الأمر وحفظ قاعدة حماية المسار محلياً';
            break;

          case 'remove_path_rule':
            final id =
                (command.payload['id'] ?? command.payload['ruleId'] ?? '')
                    .toString();
            if (id.isEmpty) throw StateError('id مطلوب لحذف القاعدة');
            await pathRules.removeRule(id);
            success = true;
            message = 'تم حذف قاعدة حماية المسار';
            break;

          case 'approve_permission':
          case 'reject_permission':
            final result = await _applyPermissionAnswer(command);
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'approve_install':
          case 'reject_install':
            final result = await _applyInstallAnswer(command);
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'request_screenshot':
            final result =
                await screenshotService.captureAndSend(deviceName: deviceId);
            await firestore.createScreenshot(
              deviceId: deviceId,
              imageUrl: result.imageUrl,
              storagePath: result.localPath,
              payload: result.toMap(),
            );
            success = true;
            message = result.sentToTelegram
                ? 'تم التقاط الشاشة وإرسالها إلى Telegram'
                : 'تم التقاط الشاشة محلياً. أضف Telegram bot token/chat id لإرسالها للبوت.';
            responsePayload = result.toMap();
            break;

          case 'browse_path':
            final path = (command.payload['path'] ?? 'roots').toString();
            responsePayload = await fileManager.listPath(path);
            success = true;
            message = 'تم إرسال محتويات المسار';
            await store.appendLog(
                'path_opened',
                'تم طلب عرض محتويات مسار من الهاتف',
                {'path': responsePayload['path']});
            break;

          case 'open_path':
            final path = (command.payload['path'] ?? '').toString();
            if (path.isEmpty) throw StateError('path مطلوب');
            _ensurePathOperationAllowed(path, 'open');
            responsePayload = await fileManager.openPath(path);
            success = true;
            message = 'تم فتح المسار على الكمبيوتر';
            await store.appendLog(
                'path_opened_on_pc', 'تم فتح مسار من الهاتف', {'path': path});
            break;

          case 'rename_path':
            final path = (command.payload['path'] ?? '').toString();
            final newName = (command.payload['newName'] ?? '').toString();
            if (path.isEmpty || newName.isEmpty) {
              throw StateError('path و newName مطلوبان');
            }
            _ensurePathOperationAllowed(path, 'rename');
            responsePayload = await fileManager.renamePath(path, newName);
            success = true;
            message = 'تمت إعادة التسمية';
            await store.appendLog('path_renamed',
                'تمت إعادة تسمية مسار من الهاتف', responsePayload);
            break;

          case 'copy_path':
            final path = (command.payload['path'] ?? '').toString();
            final destination =
                (command.payload['destination'] ?? '').toString();
            if (path.isEmpty || destination.isEmpty) {
              throw StateError('path و destination مطلوبان');
            }
            _ensurePathOperationAllowed(path, 'copy');
            _ensurePathOperationAllowed(destination, 'paste');
            responsePayload = await fileManager.copyPath(path, destination);
            success = true;
            message = 'تم النسخ';
            await store.appendLog(
                'path_copied', 'تم نسخ مسار من الهاتف', responsePayload);
            break;

          case 'move_path':
            final path = (command.payload['path'] ?? '').toString();
            final destination =
                (command.payload['destination'] ?? '').toString();
            if (path.isEmpty || destination.isEmpty) {
              throw StateError('path و destination مطلوبان');
            }
            _ensurePathOperationAllowed(path, 'move');
            _ensurePathOperationAllowed(destination, 'paste');
            responsePayload = await fileManager.movePath(path, destination);
            success = true;
            message = 'تم النقل';
            await store.appendLog(
                'path_moved', 'تم نقل مسار من الهاتف', responsePayload);
            break;

          case 'delete_path':
            final path = (command.payload['path'] ?? '').toString();
            if (path.isEmpty) throw StateError('path مطلوب');
            final permanent = command.payload['permanent'] == true;
            _ensurePathOperationAllowed(path, 'delete');
            responsePayload =
                await fileManager.deletePath(path, permanent: permanent);
            success = true;
            message =
                permanent ? 'تم الحذف النهائي' : 'تم النقل إلى سلة المحذوفات';
            await store.appendLog(
                permanent ? 'path_deleted_permanently' : 'path_deleted',
                message,
                responsePayload);
            break;

          case 'hide_path':
          case 'unhide_path':
            final path = (command.payload['path'] ?? '').toString();
            if (path.isEmpty) throw StateError('path مطلوب');
            _ensurePathOperationAllowed(path, 'modify');
            responsePayload =
                await fileManager.setHidden(path, command.type == 'hide_path');
            success = true;
            message = command.type == 'hide_path'
                ? 'تم إخفاء المسار'
                : 'تم إظهار المسار';
            await store.appendLog(command.type, message, responsePayload);
            break;

          default:
            success = false;
            message =
                'تم استلام الأمر لكن نوع الأمر غير مدعوم حالياً: ${command.type}';
        }
      }
    } catch (e, st) {
      success = false;
      message = 'خطأ أثناء تنفيذ الأمر: $e';
      responsePayload = {'stack': st.toString()};
    }

    stdout.writeln(
        'COMMAND_RESULT id=${command.id} type=${command.type} success=$success message=$message');

    await store.appendLog('command_result', message, {
      'commandId': command.id,
      'type': command.type,
      'success': success,
      'payload': responsePayload,
    });

    try {
      await _writeResponse(command, success, message, responsePayload,
          phase: 'final');
      await firestore.markCommandExecuted(deviceId, command.id,
          success: success, message: message);
    } catch (e, st) {
      stdout.writeln('COMMAND_FINAL_FIRESTORE_ERROR id=${command.id} error=$e');
      await store.appendLog('command_final_response_error', e.toString(), {
        'commandId': command.id,
        'type': command.type,
        'stack': st.toString(),
      });
    }
  }

  Future<CommandExecutionResult> _executeTelegramUnlocked(
      RemoteCommand command) async {
    stdout.writeln(
        'TELEGRAM_COMMAND_RECEIVED type=${command.type} payload=${jsonEncode(command.payload)}');
    await store
        .appendLog('telegram_command_received', 'تم استلام أمر من Telegram', {
      'type': command.type,
      'payload': command.payload,
    });

    var success = false;
    var message = '';
    Map<String, dynamic> responsePayload = <String, dynamic>{};

    try {
      final permissionId = _permissionForCommand(command.type);
      if (permissionId != null && !permissions.isAllowed(permissionId)) {
        message = permissions.unavailableOrDeniedMessage(permissionId);
        responsePayload = {
          'permissionId': permissionId,
          'permissionName': permissions.nameOf(permissionId),
        };
      } else {
        switch (command.type) {
          case 'check_connection':
            success = true;
            message = 'Online - الكمبيوتر متصل واستلم أمر Telegram';
            responsePayload = {
              'deviceId': deviceId,
              'time': DateTime.now().toIso8601String(),
            };
            break;

          case 'request_screenshot':
            final result =
                await screenshotService.captureAndSend(deviceName: deviceId);
            success = true;
            message = result.sentToTelegram
                ? 'تم التقاط الشاشة وإرسالها هنا'
                : 'تم التقاط الشاشة محلياً: ${result.localPath}';
            responsePayload = result.toMap();
            break;

          case 'lock_screen':
            await desktopLock.lockNow(reason: 'telegram_command');
            success = true;
            message = 'تم قفل شاشة Windows';
            break;

          case 'lock_for_duration':
            final minutes = _parseInt(command.payload['minutes'] ??
                    command.payload['durationMinutes']) ??
                30;
            final until = await desktopLock.lockFor(Duration(minutes: minutes));
            success = true;
            message = 'تم قفل الكمبيوتر لمدة $minutes دقيقة';
            responsePayload = {'until': until.toIso8601String()};
            break;

          case 'clear_timed_lock':
          case 'cancel_scheduled_lock':
            await desktopLock.clearTimedLock();
            success = true;
            message = 'تم إيقاف القفل المؤقت';
            break;

          case 'shutdown_pc':
          case 'restart_pc':
          case 'logout_user':
            if (!config.enableDangerousPowerCommands) {
              message = 'أوامر الطاقة مقفلة من config لحماية الكمبيوتر';
            } else {
              final result = await _runPowerCommand(command.type);
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'wifi_on':
          case 'wifi_off':
          case 'bluetooth_on':
          case 'bluetooth_off':
            if (!config.enableWifiBluetoothCommands) {
              message = 'أوامر WiFi/Bluetooth مقفلة من config حالياً';
            } else {
              final result = command.type.startsWith('wifi')
                  ? await windowsControl.setWifi(command.type == 'wifi_on')
                  : await windowsControl
                      .setBluetooth(command.type == 'bluetooth_on');
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'internet_off_permanent':
          case 'internet_on':
            if (!config.enableWifiBluetoothCommands) {
              message = 'أوامر الشبكة مقفلة من config حالياً';
            } else {
              final result = await windowsControl
                  .setInternetAdapters(command.type == 'internet_on');
              success = result.success;
              message = result.message;
              responsePayload = result.payload;
            }
            break;

          case 'list_bluetooth_devices':
            final result = await windowsControl.listBluetoothDevices();
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'open_bluetooth_receive':
            final result = await windowsControl.openBluetoothReceive(
              savePath: command.payload['savePath']?.toString(),
            );
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'send_bluetooth_file':
            final path =
                (command.payload['path'] ?? command.payload['filePath'] ?? '')
                    .toString();
            if (path.trim().isEmpty) throw StateError('path مطلوب');
            final result = await windowsControl.sendBluetoothFile(
              path: path,
              deviceName: command.payload['deviceName']?.toString(),
            );
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'volume_up':
          case 'volume_down':
          case 'set_volume':
          case 'mute_volume':
          case 'unmute_volume':
            WindowsControlResult result;
            if (command.type == 'volume_up') {
              result = await windowsControl.volumeUp();
            } else if (command.type == 'volume_down') {
              result = await windowsControl.volumeDown();
            } else if (command.type == 'set_volume') {
              final volume = _parseInt(command.payload['volume']);
              if (volume == null) throw StateError('volume مطلوب');
              result = await windowsControl.setVolume(volume);
            } else {
              result =
                  await windowsControl.setMuted(command.type == 'mute_volume');
            }
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'close_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            final pid = _parseInt(command.payload['processId']);
            final result =
                await _closeApplication(target: target, processId: pid);
            success = result.success;
            message = result.message;
            responsePayload = result.payload;
            break;

          case 'block_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('target مطلوب');
            await appBlocker.blockApp(
              target: target,
              appName: command.payload['appName']?.toString(),
              appPath: command.payload['appPath']?.toString(),
            );
            success = true;
            message = 'تم منع التطبيق وسيتم إغلاقه كلما فُتح';
            responsePayload = {'target': target};
            break;

          case 'allow_application':
            final target =
                (command.payload['target'] ?? command.payload['appName'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('target مطلوب');
            final durationSeconds =
                _parseInt(command.payload['durationSeconds']);
            await appBlocker.allowApp(
              target,
              duration: durationSeconds == null || durationSeconds <= 0
                  ? null
                  : Duration(seconds: durationSeconds),
            );
            success = true;
            message = durationSeconds == null || durationSeconds <= 0
                ? 'تم رفع منع التطبيق'
                : 'تم السماح للتطبيق لمدة ${(durationSeconds / 60).round()} دقيقة';
            responsePayload = {'target': target};
            break;

          case 'block_website':
            final target =
                (command.payload['domain'] ?? command.payload['target'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('domain مطلوب');
            await appBlocker.blockSite(
              target,
              lockType: (command.payload['lockType'] ?? 'blocked').toString(),
              password: command.payload['password']?.toString(),
              passwordHash: command.payload['passwordHash']?.toString(),
            );
            success = true;
            message = 'تم منع الموقع على هذا الكمبيوتر';
            responsePayload = {'target': target};
            break;

          case 'allow_website':
            final target =
                (command.payload['domain'] ?? command.payload['target'] ?? '')
                    .toString();
            if (target.trim().isEmpty) throw StateError('domain مطلوب');
            final durationSeconds =
                _parseInt(command.payload['durationSeconds']);
            await appBlocker.allowSite(
              target,
              duration: durationSeconds == null || durationSeconds <= 0
                  ? null
                  : Duration(seconds: durationSeconds),
            );
            success = true;
            message = durationSeconds == null || durationSeconds <= 0
                ? 'تم رفع منع الموقع'
                : 'تم السماح للموقع لمدة ${(durationSeconds / 60).round()} دقيقة';
            responsePayload = {'target': target};
            break;

          case 'browse_path':
            final path = (command.payload['path'] ?? 'roots').toString();
            responsePayload = await fileManager.listPath(path);
            success = true;
            final items = (responsePayload['items'] as List?)?.length ?? 0;
            message = 'تم قراءة المسار. عدد العناصر: $items';
            break;

          case 'open_path':
            final path = (command.payload['path'] ?? '').toString();
            if (path.isEmpty) throw StateError('path مطلوب');
            _ensurePathOperationAllowed(path, 'open');
            responsePayload = await fileManager.openPath(path);
            success = true;
            message = 'تم فتح المسار على الكمبيوتر';
            break;

          case 'request_logs':
            final logs = _filterLogs(command.payload);
            success = true;
            message = 'تم تجهيز ${logs.length} سجل محلي';
            responsePayload = {'logs': logs.take(20).toList()};
            break;

          case 'show_pairing_qr':
            await _touchTriggerFile('show_qr_now.txt');
            success = true;
            message = 'تم طلب إظهار رمز الربط على الكمبيوتر';
            break;

          case 'show_permission_center':
            await _touchTriggerFile('show_permissions_now.txt');
            success = true;
            message = 'تم طلب فتح شاشة الأذونات على الكمبيوتر';
            break;

          case 'show_message':
            final text =
                (command.payload['message'] ?? command.payload['text'] ?? '')
                    .toString();
            if (text.trim().isEmpty) throw StateError('message مطلوب');
            final title = (command.payload['title'] ?? 'KIOM').toString();
            await dialogs.showInfo(title: title, message: text);
            success = true;
            message = 'تم عرض الرسالة على الكمبيوتر';
            responsePayload = {'title': title, 'message': text};
            break;

          case 'stop_all_commands':
            await stopAllLocalCommands(reason: 'telegram');
            success = true;
            message = 'تم إيقاف وحذف الأوامر المحلية المجدولة';
            break;

          default:
            message = 'نوع أمر Telegram غير مدعوم حالياً: ${command.type}';
        }
      }
    } catch (e, st) {
      message = 'خطأ أثناء تنفيذ أمر Telegram: $e';
      responsePayload = {'stack': st.toString()};
    }

    await store.appendLog('telegram_command_result', message, {
      'type': command.type,
      'success': success,
      'payload': responsePayload,
    });

    return CommandExecutionResult(
      success: success,
      message: message,
      payload: responsePayload,
    );
  }

  Future<void> _writeResponse(
    RemoteCommand command,
    bool success,
    String message,
    Map<String, dynamic> payload, {
    required String phase,
  }) async {
    final safePayload = <String, dynamic>{
      ...payload,
      'phase': phase,
      'agentState': phase,
      'deviceId': deviceId,
      'writtenAt': DateTime.now().toIso8601String(),
    };
    await firestore.writeResponse(
      deviceId,
      command.id,
      command.type,
      success,
      message,
      safePayload,
      phase,
    );
  }

  Future<void> _syncBlockedItemsBestEffort() async {
    try {
      await firestore.syncBlockedItems(deviceId, appBlocker.cloudItems());
    } catch (e, st) {
      await store.appendLog('blocked_items_sync_error', e.toString(), {
        'deviceId': deviceId,
        'stack': st.toString(),
      });
    }
  }

  void _ensurePathOperationAllowed(String path, String operation) {
    final rule = _matchingPathRule(path);
    if (rule == null) return;

    final blocked = switch (operation) {
      'open' => rule.blockOpen || rule.lockType == 'blocked',
      'delete' => rule.blockDelete || rule.lockType == 'blocked',
      'copy' => rule.blockCopy || rule.lockType == 'blocked',
      'move' => rule.blockMove || rule.lockType == 'blocked',
      'rename' => rule.blockRename || rule.lockType == 'blocked',
      'paste' =>
        rule.blockModify || rule.readOnly || rule.lockType == 'blocked',
      'modify' =>
        rule.blockModify || rule.readOnly || rule.lockType == 'blocked',
      _ => false,
    };

    if (blocked) {
      throw StateError(
        'العملية ممنوعة حسب قاعدة حماية المسار: $operation على ${rule.path}',
      );
    }
  }

  PathRule? _matchingPathRule(String path) {
    final normalized = path.replaceAll('/', r'\').toLowerCase();
    for (final rule in pathRules.getRules()) {
      final protected = rule.path.replaceAll('/', r'\').toLowerCase();
      final prefix = protected.endsWith(r'\') ? protected : '$protected\\';
      if (normalized == protected || normalized.startsWith(prefix)) {
        return rule;
      }
    }
    return null;
  }

  String? _permissionForCommand(String type) {
    switch (type) {
      case 'check_connection':
        return 'connection';
      case 'close_application':
      case 'close_application_after_delay':
      case 'block_application':
      case 'allow_application':
      case 'block_website':
      case 'allow_website':
        return 'closeApplication';
      case 'request_logs':
        return 'logs';
      case 'add_path_rule':
      case 'update_path_rule':
      case 'remove_path_rule':
        return 'pathGuard';
      case 'lock_screen':
      case 'lock_for_duration':
      case 'lock_after_delay':
      case 'clear_timed_lock':
      case 'cancel_scheduled_lock':
        return 'lockScreen';
      case 'shutdown_pc':
      case 'restart_pc':
      case 'logout_user':
      case 'shutdown_after_delay':
      case 'restart_after_delay':
      case 'cancel_scheduled_power_command':
        return 'powerCommands';
      case 'wifi_on':
      case 'wifi_off':
      case 'bluetooth_on':
      case 'bluetooth_off':
      case 'internet_off_permanent':
      case 'internet_on':
      case 'list_bluetooth_devices':
      case 'open_bluetooth_receive':
      case 'send_bluetooth_file':
        return 'wifiBluetooth';
      case 'volume_up':
      case 'volume_down':
      case 'set_volume':
      case 'mute_volume':
      case 'unmute_volume':
        return 'volumeControl';
      case 'request_screenshot':
        return 'screenshots';
      case 'approve_install':
      case 'reject_install':
        return 'installProtection';
      case 'show_pairing_qr':
      case 'show_permission_center':
      case 'show_message':
        return 'connection';
      case 'browse_path':
      case 'open_path':
      case 'rename_path':
      case 'copy_path':
      case 'move_path':
      case 'delete_path':
      case 'hide_path':
      case 'unhide_path':
        return 'fileManager';
      default:
        return null;
    }
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  Future<_CommandProcessResult> _closeApplication(
      {required String target, int? processId}) async {
    ProcessResult result;

    if (processId != null && processId > 0) {
      result = await SafeProcessRunner.run(
        'taskkill.exe',
        ['/PID', processId.toString(), '/F'],
        timeout: SafeProcessRunner.shortTimeout,
      );
      return _CommandProcessResult(
        success: result.exitCode == 0,
        message: result.exitCode == 0
            ? 'تم إغلاق التطبيق بالـ PID: $processId'
            : 'تعذر إغلاق التطبيق بالـ PID: $processId - ${_cleanProcessOutput(result)}',
        payload: {
          'exitCode': result.exitCode,
          'processId': processId,
          'stdout': result.stdout.toString(),
          'stderr': result.stderr.toString()
        },
      );
    }

    if (target.trim().isEmpty) throw StateError('لم يتم تحديد التطبيق');

    final normalized =
        target.toLowerCase().endsWith('.exe') ? target : '$target.exe';
    result = await SafeProcessRunner.run(
      'taskkill.exe',
      ['/IM', normalized, '/F'],
      timeout: SafeProcessRunner.shortTimeout,
    );

    return _CommandProcessResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم إغلاق التطبيق: $normalized'
          : 'تعذر إغلاق التطبيق: $normalized - ${_cleanProcessOutput(result)}',
      payload: {
        'exitCode': result.exitCode,
        'target': normalized,
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString()
      },
    );
  }

  Future<_CommandProcessResult> _runPowerCommand(String type) async {
    final result = await windowsControl.power(type);
    return _CommandProcessResult(
      success: result.success,
      message: result.message,
      payload: result.payload,
    );
  }

  String _cleanProcessOutput(ProcessResult result) {
    final out = result.stdout.toString().trim();
    final err = result.stderr.toString().trim();
    final text = [out, err].where((e) => e.isNotEmpty).join(' | ');
    return text.isEmpty ? 'Exit code ${result.exitCode}' : text;
  }

  Future<void> _upsertPathRule(Map<String, dynamic> payload) async {
    final id =
        (payload['id'] ?? payload['ruleId'] ?? const Uuid().v4()).toString();
    final path = (payload['path'] ?? '').toString();
    if (path.trim().isEmpty) throw StateError('path مطلوب');

    final lockType = (payload['lockType'] ?? 'blocked').toString();
    String? passwordHash = payload['passwordHash']?.toString();
    final plainPassword = payload['password']?.toString();

    if ((passwordHash == null || passwordHash.isEmpty) &&
        plainPassword != null &&
        plainPassword.isNotEmpty) {
      passwordHash = PathRule.hashPassword(plainPassword);
    }

    final now = DateTime.now();

    await pathRules.upsertRule(
      PathRule(
        id: id,
        path: path,
        lockType: lockType,
        passwordHash: passwordHash,
        blockOpen: payload['blockOpen'] != false,
        blockDelete: payload['blockDelete'] == true,
        blockCopy: payload['blockCopy'] == true,
        blockMove: payload['blockMove'] == true,
        blockRename: payload['blockRename'] == true,
        blockModify: payload['blockModify'] == true,
        readOnly: payload['readOnly'] == true,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> _touchTriggerFile(String fileName) async {
    final file = File('${store.dir.path}\\$fileName');
    await file.writeAsString(DateTime.now().toIso8601String(), flush: true);
  }

  List<Map<String, dynamic>> _filterLogs(Map<String, dynamic> payload) {
    final logType = (payload['logType'] ?? 'all').toString();
    final from = DateTime.tryParse((payload['from'] ?? '').toString()) ??
        DateTime.now().subtract(const Duration(days: 7));
    final to =
        DateTime.tryParse((payload['to'] ?? '').toString()) ?? DateTime.now();

    final logs = store
        .list('logs')
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .where((log) {
      final createdAt = DateTime.tryParse((log['createdAt'] ?? '').toString());
      if (createdAt == null) {
        return false;
      }
      if (createdAt.isBefore(from) || createdAt.isAfter(to)) {
        return false;
      }
      if (logType == 'all') {
        return true;
      }
      return _matchesLogType((log['type'] ?? '').toString(), logType);
    }).toList();

    logs.sort((a, b) {
      final ad = DateTime.tryParse((a['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bd = DateTime.tryParse((b['createdAt'] ?? '').toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bd.compareTo(ad);
    });

    return logs.take(300).toList().reversed.toList();
  }

  bool _matchesLogType(String type, String requested) {
    if (type == requested) return true;
    switch (requested) {
      case 'file_opened':
        return type == 'app_opened' ||
            type == 'path_opened' ||
            type == 'file_opened';
      case 'app_activity':
        return type == 'app_opened' ||
            type == 'app_closed' ||
            type == 'app_changed';
      case 'path_activity':
        return type == 'path_opened' ||
            type == 'path_closed' ||
            type == 'path_changed' ||
            type == 'path_guard' ||
            type == 'protected_path_attempt';
      case 'file_deleted':
        return type == 'file_deleted' || type == 'path_deleted';
      case 'protected_path_attempt':
        return type == 'path_guard' || type == 'protected_path_attempt';
      case 'install_attempt':
        return type == 'install_attempt' ||
            type == 'app_installed' ||
            type == 'app_uninstalled';
      case 'command':
        return type.startsWith('command_') || type == 'scheduled_command';
      case 'error':
        return type.contains('error');
      default:
        return false;
    }
  }

  Future<_CommandProcessResult> _applyPermissionAnswer(
      RemoteCommand command) async {
    final requestId = (command.payload['requestId'] ?? '').toString();
    if (requestId.isEmpty) throw StateError('requestId مطلوب');

    final approve = command.type == 'approve_permission';
    final docs =
        await firestore.listDocuments('permission_requests/$deviceId/items');
    Map<String, dynamic>? request;
    for (final doc in docs) {
      if (doc['id']?.toString() == requestId) {
        request = doc;
        break;
      }
    }

    if (request == null) {
      return _CommandProcessResult(
        success: false,
        message: 'تعذر العثور على طلب الإذن محلياً: $requestId',
        payload: {'requestId': requestId},
      );
    }

    if (!approve) {
      await store.appendLog(
          'permission_rejected', 'تم رفض طلب إذن من الهاتف', request);
      return _CommandProcessResult(
        success: true,
        message: 'تم تسجيل رفض طلب الإذن',
        payload: {'requestId': requestId, 'approved': false},
      );
    }

    final seconds = _parseInt(command.payload['durationSeconds']);
    final always = command.payload['always'] == true;
    final until = always
        ? DateTime.now().add(const Duration(days: 3650))
        : DateTime.now().add(Duration(
            seconds: seconds ?? config.defaultPasswordAllowMinutes * 60));

    final approvals = store.list('pathAccessApprovals');
    approvals
        .removeWhere((item) => item is Map && item['requestId'] == requestId);
    approvals.add({
      'requestId': requestId,
      'ruleId': request['ruleId'],
      'path': request['path'],
      'openedPath': request['openedPath'],
      'until': until.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.save();
    await store.appendLog(
        'permission_approved', 'تمت الموافقة على طلب إذن من الهاتف', {
      ...request,
      'until': until.toIso8601String(),
    });

    return _CommandProcessResult(
      success: true,
      message: 'تم السماح بالمسار حتى ${until.toIso8601String()}',
      payload: {
        'requestId': requestId,
        'approved': true,
        'until': until.toIso8601String()
      },
    );
  }

  Future<_CommandProcessResult> _applyInstallAnswer(
      RemoteCommand command) async {
    final requestId = (command.payload['requestId'] ?? '').toString();
    if (requestId.isEmpty) throw StateError('requestId مطلوب');

    final approve = command.type == 'approve_install';
    final docs =
        await firestore.listDocuments('install_requests/$deviceId/items');
    Map<String, dynamic>? request;
    for (final doc in docs) {
      if (doc['id']?.toString() == requestId) {
        request = doc;
        break;
      }
    }

    if (request == null) {
      return _CommandProcessResult(
        success: false,
        message: 'تعذر العثور على طلب التثبيت: $requestId',
        payload: {'requestId': requestId},
      );
    }

    if (!approve) {
      await store.appendLog(
        'install_rejected',
        'تم رفض طلب تثبيت من الهاتف',
        request,
      );
      return _CommandProcessResult(
        success: true,
        message: 'تم تسجيل رفض التثبيت',
        payload: {'requestId': requestId, 'approved': false},
      );
    }

    final seconds = _parseInt(command.payload['durationSeconds']);
    final always = command.payload['always'] == true;
    final until = always
        ? DateTime.now().add(const Duration(days: 3650))
        : DateTime.now().add(Duration(
            seconds: seconds ?? config.defaultPasswordAllowMinutes * 60));

    final approvals = store.list('installApprovals');
    approvals
        .removeWhere((item) => item is Map && item['requestId'] == requestId);
    approvals.add({
      'requestId': requestId,
      'fileName': (request['fileName'] ?? '').toString(),
      'filePath': (request['filePath'] ?? '').toString(),
      'until': until.toIso8601String(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.save();
    await store.appendLog('install_approved', 'تمت الموافقة على التثبيت', {
      ...request,
      'until': until.toIso8601String(),
    });

    return _CommandProcessResult(
      success: true,
      message:
          'تم السماح بالتثبيت حتى ${until.toIso8601String()}. أعد تشغيل المثبت إذا كان قد أُغلق.',
      payload: {
        'requestId': requestId,
        'approved': true,
        'fileName': request['fileName'],
        'filePath': request['filePath'],
        'until': until.toIso8601String(),
      },
    );
  }

  Future<void> stopAllLocalCommands({String reason = 'manual'}) async {
    await store.set(
        'stopAllCommandsRequestedAt', DateTime.now().toIso8601String());
    await store.set('scheduledCommands', <dynamic>[]);
    await store.appendLog('commands_stopped_locally',
        'تم إيقاف وحذف كل الأوامر المحلية والمجدولة', {
      'reason': reason,
    });
  }

  bool _wasStopAllRequestedAfter(DateTime? commandCreatedAt) {
    final stopAt = DateTime.tryParse(
        (store.get<String>('stopAllCommandsRequestedAt') ?? '').toString());
    if (stopAt == null || commandCreatedAt == null) return false;
    return !commandCreatedAt.isAfter(stopAt);
  }

  Future<void> _runScheduledCommands() {
    if (_scheduledInProgress) return Future<void>.value();
    _scheduledInProgress = true;
    return _runOneCommandAtATime(_runScheduledCommandsUnlocked);
  }

  Future<void> _runScheduledCommandsUnlocked() async {
    try {
      final list = store.list('scheduledCommands');
      if (list.isEmpty) return;

      final now = DateTime.now();
      final remaining = <dynamic>[];

      for (final item in list) {
        if (item is! Map) continue;
        final executeAt =
            DateTime.tryParse((item['executeAt'] ?? '').toString());
        if (executeAt == null || executeAt.isAfter(now)) {
          remaining.add(item);
          continue;
        }

        try {
          final payload = (item['payload'] is Map)
              ? (item['payload'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          final type = (item['type'] ?? '').toString();
          late final _CommandProcessResult result;
          if (type == 'close_application') {
            result = await _closeApplication(
              target:
                  (payload['target'] ?? payload['appName'] ?? '').toString(),
              processId: _parseInt(payload['processId']),
            );
          } else if (type == 'shutdown_pc' || type == 'restart_pc') {
            result = await _runPowerCommand(type);
          } else if (type == 'lock_screen') {
            await desktopLock.lockNow(reason: 'scheduled_lock');
            result = _CommandProcessResult(
              success: true,
              message: 'تم تنفيذ قفل مجدول',
              payload: {'lockedAt': DateTime.now().toIso8601String()},
            );
          } else {
            result = _CommandProcessResult(
              success: false,
              message: 'نوع أمر مجدول غير معروف: $type',
              payload: {'type': type},
            );
          }
          await store.appendLog('scheduled_command', result.message, {
            'id': item['id'],
            'type': type,
            'success': result.success,
            'payload': result.payload
          });
        } catch (e, st) {
          await store.appendLog('scheduled_command_error', e.toString(),
              {'id': item['id'], 'stack': st.toString()});
        }
      }

      await store.set('scheduledCommands', remaining);
    } finally {
      _scheduledInProgress = false;
    }
  }
}

class CommandExecutionResult {
  final bool success;
  final String message;
  final Map<String, dynamic> payload;

  const CommandExecutionResult({
    required this.success,
    required this.message,
    required this.payload,
  });
}

class _CommandProcessResult {
  final bool success;
  final String message;
  final Map<String, dynamic> payload;

  const _CommandProcessResult(
      {required this.success, required this.message, required this.payload});
}
