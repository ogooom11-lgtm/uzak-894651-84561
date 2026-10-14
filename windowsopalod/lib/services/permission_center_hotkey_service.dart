import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';
import 'firestore_rest_client.dart';
import 'permission_state_service.dart';

class PermissionCenterHotkeyService {
  final String deviceId;
  final JsonFileStore store;
  final PermissionStateService permissions;
  final FirestoreRestClient firestore;

  Timer? _timer;
  DateTime? _holdStartedAt;
  bool _triggeredForHold = false;
  bool _printedHoldStarted = false;
  DateTime? _lastFileTriggerCheck;

  static const int _vkControl = 0x11;
  static const int _vkShift = 0x10;
  static const int _vkS = 0x53;
  static const int _vkT = 0x54;
  static const int _vkOemPlus = 0xBB;
  static const int _vkNumpadPlus = 0x6B;

  final int Function(int vKey) _getAsyncKeyState =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<Int16 Function(Int32), int Function(int)>(
              'GetAsyncKeyState');

  PermissionCenterHotkeyService({
    required this.deviceId,
    required this.store,
    required this.permissions,
    required this.firestore,
  });

  Future<void> start() async {
    await permissions.ensureInitialized();
    await _syncPermissionsToFirestore('startup');

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());

    final message =
        'Permission center active: hold Ctrl + Shift + S + T for 3 seconds. Optional: include +.';
    stdout.writeln(message);
    await store.appendLog('permission_center_start', message);
  }

  void stop() => _timer?.cancel();

  bool _isPressed(int virtualKey) =>
      (_getAsyncKeyState(virtualKey) & 0x8000) != 0;

  void _tick() {
    _checkFileTrigger();

    final mainCombo = _isPressed(_vkControl) &&
        _isPressed(_vkShift) &&
        _isPressed(_vkS) &&
        _isPressed(_vkT);

    final plusCombo =
        mainCombo && (_isPressed(_vkOemPlus) || _isPressed(_vkNumpadPlus));

    final pressed = mainCombo;

    if (!pressed) {
      _holdStartedAt = null;
      _triggeredForHold = false;
      _printedHoldStarted = false;
      return;
    }

    _holdStartedAt ??= DateTime.now();

    if (!_printedHoldStarted) {
      _printedHoldStarted = true;
      final combo = plusCombo ? 'Ctrl+Shift+++S+T' : 'Ctrl+Shift+S+T';
      stdout.writeln('PERMISSION_HOTKEY_HOLD_DETECTED: $combo');
      store.appendLog('permission_hotkey_hold_detected',
          'تم التقاط اختصار شاشة الأذونات', {'combo': combo});
    }

    final needed = const Duration(seconds: 3);
    final heldFor = DateTime.now().difference(_holdStartedAt!);

    if (heldFor >= needed && !_triggeredForHold) {
      _triggeredForHold = true;
      stdout
          .writeln('PERMISSION_HOTKEY_TRIGGERED: showing permission center...');
      showPermissionCenter();
    }
  }

  void _checkFileTrigger() {
    final now = DateTime.now();
    if (_lastFileTriggerCheck != null &&
        now.difference(_lastFileTriggerCheck!).inMilliseconds < 700) {
      return;
    }
    _lastFileTriggerCheck = now;

    final trigger = File('${store.dir.path}\\show_permissions_now.txt');
    if (!trigger.existsSync()) return;

    try {
      trigger.deleteSync();
    } catch (_) {}

    stdout.writeln(
        'PERMISSION_FILE_TRIGGER_DETECTED: showing permission center...');
    store.appendLog('permission_file_trigger',
        'تم طلب شاشة الأذونات عبر ملف show_permissions_now.txt');
    showPermissionCenter();
  }

  Future<void> showPermissionCenter() async {
    await permissions.allowAllAvailable();
    stdout.writeln('ALL_PERMISSIONS_AUTOMATICALLY_ALLOWED');
    await store.appendLog('permission_center_auto_allowed', 'تم تفعيل كافة الأذونات تلقائياً');
  }

  Future<void> _syncPermissionsToFirestore(String reason) async {
    try {
      await firestore.setDocument('devices/$deviceId', {
        'permissionState': permissions.toFirestoreMap(),
        'permissionStateUpdatedReason': reason,
      });
    } catch (e) {
      stdout.writeln('PERMISSION_SYNC_FIRESTORE_ERROR=$e');
      await store.appendLog(
          'permission_sync_firestore_error', e.toString(), {'reason': reason});
    }
  }
}
