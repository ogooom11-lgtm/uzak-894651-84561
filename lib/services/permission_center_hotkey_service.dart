import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../utils/json_file_store.dart';
import 'firestore_rest_client.dart';
import 'permission_state_service.dart';
import 'startup_task_service.dart';

class PermissionCenterHotkeyService {
  final String deviceId;
  final JsonFileStore store;
  final PermissionStateService permissions;
  final FirestoreRestClient firestore;

  Timer? _timer;
  DateTime? _holdStartedAt;
  bool _triggeredForHold = false;
  bool _printedHoldStarted = false;
  bool _isShowing = false;
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
    if (_isShowing) return;
    _isShowing = true;

    try {
      await permissions.ensureInitialized();

      final stateFile = File('${store.dir.path}\\permission_center_state.json');
      final outputFile =
          File('${store.dir.path}\\permission_center_result.json');
      final scriptFile = File('${store.dir.path}\\show_permission_center.ps1');

      if (await outputFile.exists()) {
        try {
          await outputFile.delete();
        } catch (_) {}
      }

      final state = {
        'deviceId': deviceId,
        'generatedAt': DateTime.now().toIso8601String(),
        'permissions': permissions.list(),
      };

      await stateFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(state));
      await scriptFile.writeAsString(_powerShellScript);

      stdout.writeln('PERMISSION_CENTER_OPENING');
      await store.appendLog('permission_center_open', 'فتح شاشة أذونات KIOM',
          {'stateFile': stateFile.path});

      final result = await Process.run(
        'powershell.exe',
        [
          '-NoProfile',
          '-Sta',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          scriptFile.path,
          stateFile.path,
          outputFile.path,
        ],
        runInShell: false,
      );

      if (result.exitCode != 0) {
        final message = 'تعذر فتح شاشة الأذونات: ${result.stderr}';
        stdout.writeln('PERMISSION_CENTER_ERROR: $message');
        await store.appendLog('permission_center_error', message, {
          'stdout': result.stdout.toString(),
          'stderr': result.stderr.toString(),
          'exitCode': result.exitCode,
        });
        return;
      }

      if (!await outputFile.exists()) {
        stdout.writeln('PERMISSION_CENTER_CANCELLED');
        await store.appendLog(
            'permission_center_cancelled', 'تم إغلاق شاشة الأذونات بدون حفظ');
        return;
      }

      final decoded =
          jsonDecode(await outputFile.readAsString()) as Map<String, dynamic>;
      final action = (decoded['action'] ?? '').toString();
      final values = <String, bool>{};

      if (action == 'allowAll') {
        await permissions.allowAllAvailable();
      } else if (action == 'denyAll') {
        await permissions.denyAll();
      } else if (action == 'installStartupTask') {
        await StartupTaskService(store: store).requestInstallForAllUsers();
      } else if (action == 'save') {
        final rawValues =
            (decoded['permissions'] as Map?)?.cast<String, dynamic>() ??
                const <String, dynamic>{};
        for (final entry in rawValues.entries) {
          values[entry.key] = entry.value == true;
        }
        await permissions.applyAllowMap(values);
      } else {
        return;
      }

      await _syncPermissionsToFirestore(action);

      final allowed = permissions
          .list()
          .where((e) => e['allowed'] == true)
          .map((e) => e['id'])
          .toList();
      final unavailable = permissions
          .list()
          .where((e) => e['available'] != true)
          .map((e) => e['id'])
          .toList();

      stdout.writeln(
          'PERMISSION_CENTER_SAVED action=$action allowed=${allowed.join(',')} unavailable=${unavailable.join(',')}');
      await store
          .appendLog('permission_center_saved', 'تم حفظ إعدادات الأذونات', {
        'action': action,
        'allowed': allowed,
        'unavailable': unavailable,
      });

      await firestore.writeResponse(
        deviceId,
        'permission_center_${DateTime.now().millisecondsSinceEpoch}',
        'permission_center',
        true,
        'تم تحديث أذونات تطبيق الكمبيوتر. المسموح الآن: ${allowed.length}. غير المتاح حالياً: ${unavailable.length}.',
        {
          'action': action,
          'allowed': allowed,
          'unavailable': unavailable,
        },
        'final',
      );
    } catch (e, st) {
      stdout.writeln('PERMISSION_CENTER_EXCEPTION: $e');
      await store.appendLog('permission_center_exception', e.toString(),
          {'stack': st.toString()});
    } finally {
      _isShowing = false;
    }
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

  static const String _powerShellScript = r'''
param(
  [string]$StatePath,
  [string]$OutputPath
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$state = Get-Content -Raw -LiteralPath $StatePath | ConvertFrom-Json
$permissions = @($state.permissions)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'KIOM - أذونات التحكم في Windows'
$form.Size = New-Object System.Drawing.Size(780,620)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes
$form.RightToLeftLayout = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'شاشة أذونات KIOM PC Agent'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(20,16)
$form.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'فعّل الأذونات المطلوبة. التحكم يتم مباشرة من التطبيق عندما يعمل كمسؤول.'
$subtitle.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(20,50)
$form.Controls.Add($subtitle)

$panel = New-Object System.Windows.Forms.Panel
$panel.Location = New-Object System.Drawing.Point(20,82)
$panel.Size = New-Object System.Drawing.Size(725,405)
$panel.AutoScroll = $true
$panel.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$form.Controls.Add($panel)

$checkboxes = @{}
$y = 12

foreach ($p in $permissions) {
  $available = [bool]$p.available
  $allowed = [bool]$p.allowed
  $name = [string]$p.name
  $description = [string]$p.description
  $reason = [string]$p.reason
  $id = [string]$p.id

  $box = New-Object System.Windows.Forms.CheckBox
  $box.Text = "● $name"
  $box.Checked = ($available -and $allowed)
  $box.Enabled = $available
  $box.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
  $box.Location = New-Object System.Drawing.Point(15,$y)
  $box.Size = New-Object System.Drawing.Size(675,24)
  $panel.Controls.Add($box)
  $checkboxes[$id] = $box

  $desc = New-Object System.Windows.Forms.Label
  $desc.Text = $description
  $desc.Font = New-Object System.Drawing.Font('Segoe UI', 8)
  $desc.Location = New-Object System.Drawing.Point(38,($y + 25))
  $desc.Size = New-Object System.Drawing.Size(650,20)
  $panel.Controls.Add($desc)

  $status = New-Object System.Windows.Forms.Label
  if ($available) {
    $status.Text = 'الحالة: متاح الآن'
    $status.ForeColor = [System.Drawing.Color]::DarkGreen
  } else {
    $status.Text = "الحالة: غير متاح حالياً - $reason"
    $status.ForeColor = [System.Drawing.Color]::DarkRed
  }
  $status.Font = New-Object System.Drawing.Font('Segoe UI', 8)
  $status.Location = New-Object System.Drawing.Point(38,($y + 45))
  $status.Size = New-Object System.Drawing.Size(650,20)
  $panel.Controls.Add($status)

  $line = New-Object System.Windows.Forms.Label
  $line.BorderStyle = [System.Windows.Forms.BorderStyle]::Fixed3D
  $line.Location = New-Object System.Drawing.Point(15,($y + 72))
  $line.Size = New-Object System.Drawing.Size(675,2)
  $panel.Controls.Add($line)

  $y += 86
}

$note = New-Object System.Windows.Forms.Label
$note.Text = 'ملاحظة: زر "السماح للكل" يسمح فقط بالأذونات المتاحة في هذه النسخة. بعض الحماية العميقة تحتاج تشغيل التطبيق كمسؤول وصلاحيات Windows كافية.'
$note.Location = New-Object System.Drawing.Point(20,498)
$note.Size = New-Object System.Drawing.Size(725,35)
$note.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$form.Controls.Add($note)

$allowAllButton = New-Object System.Windows.Forms.Button
$allowAllButton.Text = 'السماح للكل المتاح'
$allowAllButton.Location = New-Object System.Drawing.Point(20,540)
$allowAllButton.Size = New-Object System.Drawing.Size(160,32)
$form.Controls.Add($allowAllButton)

$denyAllButton = New-Object System.Windows.Forms.Button
$denyAllButton.Text = 'عدم السماح للكل'
$denyAllButton.Location = New-Object System.Drawing.Point(190,540)
$denyAllButton.Size = New-Object System.Drawing.Size(145,32)
$form.Controls.Add($denyAllButton)

$startupButton = New-Object System.Windows.Forms.Button
$startupButton.Text = 'تشغيل مع Windows كمسؤول'
$startupButton.Location = New-Object System.Drawing.Point(345,540)
$startupButton.Size = New-Object System.Drawing.Size(145,32)
$form.Controls.Add($startupButton)

$saveButton = New-Object System.Windows.Forms.Button
$saveButton.Text = 'حفظ'
$saveButton.Location = New-Object System.Drawing.Point(500,540)
$saveButton.Size = New-Object System.Drawing.Size(110,32)
$form.Controls.Add($saveButton)

$cancelButton = New-Object System.Windows.Forms.Button
$cancelButton.Text = 'إلغاء'
$cancelButton.Location = New-Object System.Drawing.Point(625,540)
$cancelButton.Size = New-Object System.Drawing.Size(110,32)
$form.Controls.Add($cancelButton)

function Save-Result([string]$action) {
  $values = @{}
  foreach ($key in $checkboxes.Keys) {
    $values[$key] = [bool]$checkboxes[$key].Checked
  }
  $result = [PSCustomObject]@{
    action = $action
    permissions = $values
    savedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
  $form.Close()
}

$allowAllButton.Add_Click({
  foreach ($key in $checkboxes.Keys) {
    if ($checkboxes[$key].Enabled) { $checkboxes[$key].Checked = $true }
  }
  Save-Result 'allowAll'
})

$denyAllButton.Add_Click({
  foreach ($key in $checkboxes.Keys) {
    if ($checkboxes[$key].Enabled) { $checkboxes[$key].Checked = $false }
  }
  Save-Result 'denyAll'
})

$startupButton.Add_Click({ Save-Result 'installStartupTask' })
$saveButton.Add_Click({ Save-Result 'save' })
$cancelButton.Add_Click({ $form.Close() })

[void]$form.ShowDialog()
''';
}
