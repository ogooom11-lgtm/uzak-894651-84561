import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../utils/json_file_store.dart';
import 'firestore_rest_client.dart';

class LocalLogsCenterHotkeyService {
  LocalLogsCenterHotkeyService({
    required this.store,
    this.deviceId,
    this.firestore,
  });

  static const _deletePassword = '1494922';
  static const _vkControl = 0x11;
  static const _vkShift = 0x10;
  static const _vkH = 0x48;
  static const _vkT = 0x54;

  final JsonFileStore store;
  final String? deviceId;
  final FirestoreRestClient? firestore;

  final int Function(int vKey) _getAsyncKeyState =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<Int16 Function(Int32), int Function(int)>(
              'GetAsyncKeyState');

  Timer? _timer;
  DateTime? _holdStartedAt;
  bool _triggeredForHold = false;
  bool _isShowing = false;

  void start() {
    if (!Platform.isWindows) return;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 120), (_) => _tick());
  }

  void stop() => _timer?.cancel();

  bool _isPressed(int virtualKey) =>
      (_getAsyncKeyState(virtualKey) & 0x8000) != 0;

  void _tick() {
    final pressed = _isPressed(_vkControl) &&
        _isPressed(_vkShift) &&
        _isPressed(_vkH) &&
        _isPressed(_vkT);

    if (!pressed) {
      _holdStartedAt = null;
      _triggeredForHold = false;
      return;
    }

    _holdStartedAt ??= DateTime.now();
    final heldFor = DateTime.now().difference(_holdStartedAt!);
    if (heldFor >= const Duration(seconds: 3) && !_triggeredForHold) {
      _triggeredForHold = true;
      unawaited(showLogsCenter());
    }
  }

  Future<void> showLogsCenter() async {
    if (_isShowing) return;
    _isShowing = true;
    try {
      final stateFile = File('${store.dir.path}\\logs_center_state.json');
      final outputFile = File('${store.dir.path}\\logs_center_result.json');
      final scriptFile = File('${store.dir.path}\\show_logs_center.ps1');
      if (await outputFile.exists()) {
        await outputFile.delete();
      }

      final logs = store
          .list('logs')
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final dataUsageBytes = await _directorySize(store.dir);
      final state = {
        'generatedAt': DateTime.now().toIso8601String(),
        'logs': logs,
        'logsCount': logs.length,
        'dataUsageBytes': dataUsageBytes,
        'dataUsageLabel': _formatBytes(dataUsageBytes),
      };
      await stateFile
          .writeAsString(const JsonEncoder.withIndent('  ').convert(state));
      await scriptFile.writeAsString(_powerShellScript);

      await store.appendLog('logs_center_open', 'فتح مركز السجلات المحلي', {
        'logsCount': logs.length,
        'dataUsageBytes': dataUsageBytes,
      });

      await Process.run(
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

      if (!await outputFile.exists()) return;
      final output =
          jsonDecode(await outputFile.readAsString()) as Map<String, dynamic>;
      if (output['action'] == 'delete') {
        await _deleteLogs(output.cast<String, dynamic>());
      } else if (output['action'] == 'stopAllCommands') {
        await _stopAllCommands();
      }
    } catch (e, st) {
      await store.appendLog('logs_center_error', e.toString(), {
        'stack': st.toString(),
      });
    } finally {
      _isShowing = false;
    }
  }

  Future<void> _deleteLogs(Map<String, dynamic> request) async {
    if ((request['password'] ?? '').toString() != _deletePassword) {
      await store.appendLog(
          'logs_delete_rejected', 'كلمة مرور حذف السجلات خاطئة');
      return;
    }

    final from = DateTime.tryParse((request['from'] ?? '').toString()) ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final to = DateTime.tryParse((request['to'] ?? '').toString()) ??
        DateTime.now().add(const Duration(days: 1));
    final type = (request['type'] ?? 'all').toString();
    final keyword = (request['keyword'] ?? '').toString().trim().toLowerCase();
    final logs = store.list('logs');
    final before = logs.length;

    logs.removeWhere((item) {
      if (item is! Map) return false;
      final map = item.cast<String, dynamic>();
      final createdAt = DateTime.tryParse((map['createdAt'] ?? '').toString());
      if (createdAt == null ||
          createdAt.isBefore(from) ||
          createdAt.isAfter(to)) {
        return false;
      }
      if (type != 'all' && (map['type'] ?? '').toString() != type) return false;
      if (keyword.isNotEmpty &&
          !jsonEncode(map).toLowerCase().contains(keyword)) {
        return false;
      }
      return true;
    });

    final removed = before - logs.length;
    await store.save();
    await store.appendLog('logs_deleted_local', 'تم حذف سجلات محلية', {
      'removed': removed,
      'from': from.toIso8601String(),
      'to': to.toIso8601String(),
      'type': type,
      'keyword': keyword,
    });
  }

  Future<void> _stopAllCommands() async {
    await store.set(
        'stopAllCommandsRequestedAt', DateTime.now().toIso8601String());
    await store.set('scheduledCommands', <dynamic>[]);

    var cloudDeleted = 0;
    final currentDeviceId = deviceId;
    final client = firestore;
    if (currentDeviceId != null && client != null) {
      try {
        final docs =
            await client.listDocuments('commands/$currentDeviceId/items');
        for (final doc in docs) {
          await client
              .deleteDocument('commands/$currentDeviceId/items/${doc['id']}');
          cloudDeleted++;
        }
      } catch (e) {
        await store.appendLog('commands_stop_cloud_error', e.toString());
      }
    }

    await store.appendLog(
      'commands_stopped_and_deleted',
      'تم إيقاف وحذف الأوامر المعلقة والمجدولة',
      {
        'cloudDeleted': cloudDeleted,
        'requestedAt': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<int> _directorySize(Directory dir) async {
    var total = 0;
    if (!await dir.exists()) return 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {}
      }
    }
    return total;
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
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
$allLogs = @($state.logs)

$form = New-Object System.Windows.Forms.Form
$form.Text = 'KIOM - السجلات المحلية'
$form.Size = New-Object System.Drawing.Size(1060,720)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes
$form.RightToLeftLayout = $true

$title = New-Object System.Windows.Forms.Label
$title.Text = 'مركز السجلات'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 16, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(20,15)
$title.Size = New-Object System.Drawing.Size(300,32)
$form.Controls.Add($title)

$usage = New-Object System.Windows.Forms.Label
$usage.Text = "عدد السجلات: $($state.logsCount)   |   حجم البيانات المحلية: $($state.dataUsageLabel)"
$usage.Font = New-Object System.Drawing.Font('Segoe UI', 9)
$usage.Location = New-Object System.Drawing.Point(20,50)
$usage.Size = New-Object System.Drawing.Size(980,24)
$form.Controls.Add($usage)

$typeBox = New-Object System.Windows.Forms.ComboBox
$typeBox.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$typeBox.Location = New-Object System.Drawing.Point(20,92)
$typeBox.Size = New-Object System.Drawing.Size(180,28)
[void]$typeBox.Items.Add('all')
@($allLogs | ForEach-Object { $_.type } | Where-Object { $_ } | Sort-Object -Unique) | ForEach-Object { [void]$typeBox.Items.Add($_) }
$typeBox.SelectedIndex = 0
$form.Controls.Add($typeBox)

$fromPicker = New-Object System.Windows.Forms.DateTimePicker
$fromPicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$fromPicker.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$fromPicker.Value = (Get-Date).AddDays(-7)
$fromPicker.Location = New-Object System.Drawing.Point(220,92)
$fromPicker.Size = New-Object System.Drawing.Size(190,28)
$form.Controls.Add($fromPicker)

$toPicker = New-Object System.Windows.Forms.DateTimePicker
$toPicker.Format = [System.Windows.Forms.DateTimePickerFormat]::Custom
$toPicker.CustomFormat = 'yyyy-MM-dd HH:mm:ss'
$toPicker.Value = Get-Date
$toPicker.Location = New-Object System.Drawing.Point(430,92)
$toPicker.Size = New-Object System.Drawing.Size(190,28)
$form.Controls.Add($toPicker)

$keywordBox = New-Object System.Windows.Forms.TextBox
$keywordBox.Location = New-Object System.Drawing.Point(640,92)
$keywordBox.Size = New-Object System.Drawing.Size(190,28)
$keywordBox.PlaceholderText = 'بحث'
$form.Controls.Add($keywordBox)

$applyButton = New-Object System.Windows.Forms.Button
$applyButton.Text = 'فلترة'
$applyButton.Location = New-Object System.Drawing.Point(850,91)
$applyButton.Size = New-Object System.Drawing.Size(80,30)
$form.Controls.Add($applyButton)

$deleteButton = New-Object System.Windows.Forms.Button
$deleteButton.Text = 'حذف المحدد'
$deleteButton.Location = New-Object System.Drawing.Point(940,91)
$deleteButton.Size = New-Object System.Drawing.Size(90,30)
$deleteButton.BackColor = [System.Drawing.Color]::MistyRose
$form.Controls.Add($deleteButton)

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(20,135)
$grid.Size = New-Object System.Drawing.Size(1010,500)
$grid.ReadOnly = $true
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$form.Controls.Add($grid)

$openPathButton = New-Object System.Windows.Forms.Button
$openPathButton.Text = 'فتح المسار'
$openPathButton.Location = New-Object System.Drawing.Point(20,645)
$openPathButton.Size = New-Object System.Drawing.Size(120,32)
$form.Controls.Add($openPathButton)

$stopCommandsButton = New-Object System.Windows.Forms.Button
$stopCommandsButton.Text = 'إيقاف وحذف الأوامر'
$stopCommandsButton.Location = New-Object System.Drawing.Point(155,645)
$stopCommandsButton.Size = New-Object System.Drawing.Size(160,32)
$stopCommandsButton.BackColor = [System.Drawing.Color]::MistyRose
$form.Controls.Add($stopCommandsButton)

$closeButton = New-Object System.Windows.Forms.Button
$closeButton.Text = 'إغلاق'
$closeButton.Location = New-Object System.Drawing.Point(910,645)
$closeButton.Size = New-Object System.Drawing.Size(120,32)
$form.Controls.Add($closeButton)

function Get-TargetText($log) {
  if ($log.extra -and $log.extra.path) { return [string]$log.extra.path }
  if ($log.extra -and $log.extra.openedPath) { return [string]$log.extra.openedPath }
  if ($log.extra -and $log.extra.appName) { return [string]$log.extra.appName }
  if ($log.extra -and $log.extra.target) { return [string]$log.extra.target }
  return ''
}

function To-ExtraJson($log) {
  try { return ($log.extra | ConvertTo-Json -Compress -Depth 8) } catch { return '' }
}

function Get-SelectedTarget {
  if ($grid.CurrentRow -eq $null) { return '' }
  $value = $grid.CurrentRow.Cells['الهدف'].Value
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Open-SelectedPath {
  $target = Get-SelectedTarget
  if ([string]::IsNullOrWhiteSpace($target)) {
    [System.Windows.Forms.MessageBox]::Show('لا يوجد مسار واضح في السجل المحدد.', 'فتح المسار') | Out-Null
    return
  }
  try {
    if (Test-Path -LiteralPath $target -PathType Container) {
      Start-Process explorer.exe -ArgumentList @($target)
    } elseif (Test-Path -LiteralPath $target -PathType Leaf) {
      Start-Process explorer.exe -ArgumentList @('/select,', $target)
    } else {
      Start-Process explorer.exe -ArgumentList @($target)
    }
  } catch {
    [System.Windows.Forms.MessageBox]::Show("تعذر فتح المسار:`n$target", 'فتح المسار') | Out-Null
  }
}

function Get-FilteredLogs {
  $type = [string]$typeBox.SelectedItem
  $from = $fromPicker.Value
  $to = $toPicker.Value
  $keyword = $keywordBox.Text.Trim().ToLowerInvariant()
  $filtered = @()
  foreach ($log in $allLogs) {
    $created = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$log.createdAt, [ref]$created)) { continue }
    if ($created -lt $from -or $created -gt $to) { continue }
    if ($type -ne 'all' -and [string]$log.type -ne $type) { continue }
    $blob = ($log | ConvertTo-Json -Compress -Depth 8).ToLowerInvariant()
    if ($keyword -and -not $blob.Contains($keyword)) { continue }
    $filtered += $log
  }
  return $filtered
}

function Refresh-Grid {
  $table = New-Object System.Data.DataTable
  [void]$table.Columns.Add('الوقت')
  [void]$table.Columns.Add('النوع')
  [void]$table.Columns.Add('الرسالة')
  [void]$table.Columns.Add('الهدف')
  [void]$table.Columns.Add('التفاصيل')
  foreach ($log in Get-FilteredLogs) {
    [void]$table.Rows.Add($log.createdAt, $log.type, $log.message, (Get-TargetText $log), (To-ExtraJson $log))
  }
  $grid.DataSource = $table
  $usage.Text = "عدد النتائج: $($table.Rows.Count) من $($state.logsCount)   |   حجم البيانات المحلية: $($state.dataUsageLabel)"
}

function Ask-Password {
  $dialog = New-Object System.Windows.Forms.Form
  $dialog.Text = 'كلمة مرور حذف السجلات'
  $dialog.Size = New-Object System.Drawing.Size(360,160)
  $dialog.StartPosition = 'CenterParent'
  $dialog.RightToLeft = [System.Windows.Forms.RightToLeft]::Yes
  $dialog.RightToLeftLayout = $true

  $label = New-Object System.Windows.Forms.Label
  $label.Text = 'أدخل كلمة المرور لتأكيد الحذف'
  $label.Location = New-Object System.Drawing.Point(20,16)
  $label.Size = New-Object System.Drawing.Size(300,24)
  $dialog.Controls.Add($label)

  $box = New-Object System.Windows.Forms.TextBox
  $box.UseSystemPasswordChar = $true
  $box.Location = New-Object System.Drawing.Point(20,45)
  $box.Size = New-Object System.Drawing.Size(300,24)
  $dialog.Controls.Add($box)

  $ok = New-Object System.Windows.Forms.Button
  $ok.Text = 'حذف'
  $ok.Location = New-Object System.Drawing.Point(150,82)
  $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
  $dialog.Controls.Add($ok)

  $cancel = New-Object System.Windows.Forms.Button
  $cancel.Text = 'إلغاء'
  $cancel.Location = New-Object System.Drawing.Point(245,82)
  $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
  $dialog.Controls.Add($cancel)
  $dialog.AcceptButton = $ok
  $dialog.CancelButton = $cancel

  $result = $dialog.ShowDialog($form)
  if ($result -eq [System.Windows.Forms.DialogResult]::OK) { return $box.Text }
  return $null
}

$applyButton.Add_Click({ Refresh-Grid })
$openPathButton.Add_Click({ Open-SelectedPath })
$closeButton.Add_Click({ $form.Close() })
$grid.Add_CellDoubleClick({
  if ($grid.CurrentRow -ne $null) {
    $text = ''
    foreach ($cell in $grid.CurrentRow.Cells) { $text += "$($cell.OwningColumn.HeaderText): $($cell.Value)`n" }
    [System.Windows.Forms.MessageBox]::Show($text, 'تفاصيل السجل') | Out-Null
  }
})

$deleteButton.Add_Click({
  $password = Ask-Password
  if ($null -eq $password) { return }
  if ($password -ne '1494922') {
    [System.Windows.Forms.MessageBox]::Show('كلمة المرور غير صحيحة.', 'رفض الحذف') | Out-Null
    return
  }
  $confirm = [System.Windows.Forms.MessageBox]::Show('سيتم حذف السجلات المطابقة للفلترة الحالية. هل تريد المتابعة؟', 'تأكيد الحذف', 'YesNo', 'Warning')
  if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $result = [PSCustomObject]@{
    action = 'delete'
    password = $password
    type = [string]$typeBox.SelectedItem
    from = $fromPicker.Value.ToUniversalTime().ToString('o')
    to = $toPicker.Value.ToUniversalTime().ToString('o')
    keyword = $keywordBox.Text
  }
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
  $form.Close()
})

$stopCommandsButton.Add_Click({
  $confirm = [System.Windows.Forms.MessageBox]::Show('سيتم إيقاف الأوامر المعلقة والمجدولة وحذفها. هل تريد المتابعة؟', 'إيقاف كل الأوامر', 'YesNo', 'Warning')
  if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
  $result = [PSCustomObject]@{
    action = 'stopAllCommands'
    requestedAt = (Get-Date).ToUniversalTime().ToString('o')
  }
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
  $form.Close()
})

Refresh-Grid
[void]$form.ShowDialog()
''';
}
