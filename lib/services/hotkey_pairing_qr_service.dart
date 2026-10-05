import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:qr/qr.dart';

import '../utils/json_file_store.dart';
import 'device_identity_service.dart';
import 'firestore_rest_client.dart';

class HotkeyPairingQrService {
  final String deviceId;
  final JsonFileStore store;
  final DeviceIdentityService identity;
  final FirestoreRestClient firestore;

  Timer? _timer;
  DateTime? _holdStartedAt;
  bool _alreadyTriggeredForThisHold = false;
  bool _isShowingQr = false;
  bool _printedHoldStarted = false;
  DateTime? _lastFileTriggerCheck;

  static const int _vkControl = 0x11;
  static const int _vkShift = 0x10;
  static const int _vkQ = 0x51;
  static const int _vkR = 0x52;
  static const int _vkOemPlus = 0xBB;
  static const int _vkNumpadPlus = 0x6B;

  final int Function(int vKey) _getAsyncKeyState =
      DynamicLibrary.open('user32.dll')
          .lookupFunction<Int16 Function(Int32), int Function(int)>(
              'GetAsyncKeyState');

  HotkeyPairingQrService({
    required this.deviceId,
    required this.store,
    required this.identity,
    required this.firestore,
  });

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    final message =
        'QR hotkey active: hold Ctrl + Shift + Q + R for 3 seconds. Optional: include +.';
    stdout.writeln(message);
    store.appendLog('qr_hotkey_start', message);
  }

  void stop() => _timer?.cancel();

  bool _isPressed(int virtualKey) {
    return (_getAsyncKeyState(virtualKey) & 0x8000) != 0;
  }

  void _tick() {
    _checkFileTrigger();

    final mainCombo = _isPressed(_vkControl) &&
        _isPressed(_vkShift) &&
        _isPressed(_vkQ) &&
        _isPressed(_vkR);

    final plusCombo =
        mainCombo && (_isPressed(_vkOemPlus) || _isPressed(_vkNumpadPlus));

    final pressed = mainCombo;

    if (!pressed) {
      _holdStartedAt = null;
      _alreadyTriggeredForThisHold = false;
      _printedHoldStarted = false;
      return;
    }

    _holdStartedAt ??= DateTime.now();

    if (!_printedHoldStarted) {
      _printedHoldStarted = true;
      final comboName = plusCombo ? 'Ctrl+Shift+++Q+R' : 'Ctrl+Shift+Q+R';
      stdout.writeln('QR hotkey hold detected: $comboName');
      store.appendLog('qr_hotkey_hold_detected', 'تم التقاط ضغط الاختصار',
          {'combo': comboName});
    }

    final needed = const Duration(seconds: 3);
    final heldFor = DateTime.now().difference(_holdStartedAt!);

    if (heldFor >= needed && !_alreadyTriggeredForThisHold) {
      _alreadyTriggeredForThisHold = true;
      stdout.writeln('QR hotkey triggered. Showing QR...');
      _showPairingQr();
    }
  }

  void _checkFileTrigger() {
    final now = DateTime.now();
    if (_lastFileTriggerCheck != null &&
        now.difference(_lastFileTriggerCheck!).inMilliseconds < 700) {
      return;
    }
    _lastFileTriggerCheck = now;

    final trigger = File('${store.dir.path}\\show_qr_now.txt');
    if (!trigger.existsSync()) return;

    try {
      trigger.deleteSync();
    } catch (_) {}

    stdout.writeln('QR file trigger detected. Showing QR...');
    store.appendLog(
        'qr_file_trigger', 'تم طلب إظهار QR عبر ملف show_qr_now.txt');
    _showPairingQr();
  }

  Future<void> _showPairingQr() async {
    if (_isShowingQr) return;
    _isShowingQr = true;

    try {
      final payload = await identity.createPairingPayload();
      var pairingTokenUploaded = false;

      try {
        await firestore.createPairingToken(
          token: payload['pairingToken'].toString(),
          deviceId: deviceId,
          securityKey: payload['securityKey'].toString(),
          expiresAt: DateTime.parse(payload['expiresAt'].toString()),
        );
        pairingTokenUploaded = true;
      } catch (e, st) {
        await store.appendLog('qr_pairing_token_upload_error', e.toString(), {
          'deviceId': deviceId,
          'stack': st.toString(),
          'note': 'سيتم عرض QR محلياً حتى لو فشل رفع token إلى Firebase.',
        });
      }

      payload['pairingTokenUploaded'] = pairingTokenUploaded;
      payload['pairingMode'] = 'direct_or_cloud';
      await store.set('lastPairingPayload', payload);

      final payloadJson = const JsonEncoder.withIndent('  ').convert(payload);
      final qrPath = '${store.dir.path}\\pairing_qr.png';
      await _writeQrPng(payloadJson, qrPath);

      stdout.writeln('PAIRING_QR_FILE=$qrPath');
      stdout.writeln(
          'PAIRING_PAYLOAD_FILE=${store.dir.path}\\pairing_payload.json');

      await store.appendLog('qr_hotkey_show', 'تم إظهار QR للربط', {
        'deviceId': deviceId,
        'token': payload['pairingToken'],
        'qrPath': qrPath,
        'payloadFile': '${store.dir.path}\\pairing_payload.json',
      });

      await _showQrWindow(qrImagePath: qrPath, visibleSeconds: 45);
    } catch (e, st) {
      stdout.writeln('QR_ERROR=$e');
      await store
          .appendLog('qr_hotkey_error', e.toString(), {'stack': st.toString()});
    } finally {
      _isShowingQr = false;
    }
  }

  Future<void> _writeQrPng(String data, String outputPath) async {
    final qrCode = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    final qrImage = QrImage(qrCode);

    const moduleSize = 10;
    const quietZone = 4;
    final modules = qrImage.moduleCount;
    final size = (modules + quietZone * 2) * moduleSize;

    final image = img.Image(width: size, height: size);
    img.fill(image, color: img.ColorRgb8(255, 255, 255));

    for (var y = 0; y < modules; y++) {
      for (var x = 0; x < modules; x++) {
        if (qrImage.isDark(y, x)) {
          img.fillRect(
            image,
            x1: (x + quietZone) * moduleSize,
            y1: (y + quietZone) * moduleSize,
            x2: (x + quietZone + 1) * moduleSize - 1,
            y2: (y + quietZone + 1) * moduleSize - 1,
            color: img.ColorRgb8(0, 0, 0),
          );
        }
      }
    }

    await File(outputPath).writeAsBytes(img.encodePng(image));
  }

  Future<void> _showQrWindow({
    required String qrImagePath,
    required int visibleSeconds,
  }) async {
    final imagePathJson = jsonEncode(qrImagePath);
    final payloadPathJson =
        jsonEncode('${store.dir.path}\\pairing_payload.json');
    final visibleMs = visibleSeconds * 1000;

    final script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$imagePath = __IMAGE_PATH__
$payloadPath = __PAYLOAD_PATH__
$visibleMs = __VISIBLE_MS__

$form = New-Object System.Windows.Forms.Form
$form.Text = 'KIOM Pairing QR'
$form.Size = New-Object System.Drawing.Size(460, 560)
$form.StartPosition = 'CenterScreen'
$form.TopMost = $true
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Scan this QR from the phone app'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(80, 15)
$form.Controls.Add($title)

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(50, 55)
$picture.Size = New-Object System.Drawing.Size(350, 350)
$picture.SizeMode = 'Zoom'
$picture.Image = [System.Drawing.Image]::FromFile($imagePath)
$form.Controls.Add($picture)

$info = New-Object System.Windows.Forms.Label
$info.Text = "Auto close after $([int]($visibleMs / 1000)) seconds.`r`nManual pairing file:`r`n$payloadPath"
$info.AutoSize = $false
$info.Size = New-Object System.Drawing.Size(390, 80)
$info.Location = New-Object System.Drawing.Point(25, 420)
$form.Controls.Add($info)

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = $visibleMs
$timer.Add_Tick({
  $timer.Stop()
  $form.Close()
})

$form.Add_Shown({
  $form.Activate()
  $timer.Start()
})
$form.Add_FormClosed({
  if ($picture.Image -ne $null) {
    $picture.Image.Dispose()
  }
})

[void]$form.ShowDialog()
'''
        .replaceAll('__IMAGE_PATH__', imagePathJson)
        .replaceAll('__PAYLOAD_PATH__', payloadPathJson)
        .replaceAll('__VISIBLE_MS__', visibleMs.toString());

    await Process.run(
      'powershell.exe',
      [
        '-NoProfile',
        '-Sta',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      runInShell: false,
    );
  }
}
