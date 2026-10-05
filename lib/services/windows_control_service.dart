import 'dart:convert';
import 'dart:io';

class WindowsControlResult {
  const WindowsControlResult({
    required this.success,
    required this.message,
    this.payload = const {},
  });

  final bool success;
  final String message;
  final Map<String, dynamic> payload;
}

class WindowsControlService {
  static const String _audioPowerShell = r'''
$ErrorActionPreference = 'Stop'

if (-not ('KiomAudioEndpoint' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public enum EDataFlow {
  eRender = 0,
  eCapture = 1,
  eAll = 2
}

public enum ERole {
  eConsole = 0,
  eMultimedia = 1,
  eCommunications = 2
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
  [PreserveSig] int RegisterControlChangeNotify(IntPtr pNotify);
  [PreserveSig] int UnregisterControlChangeNotify(IntPtr pNotify);
  [PreserveSig] int GetChannelCount(out uint pnChannelCount);
  [PreserveSig] int SetMasterVolumeLevel(float fLevelDB, Guid pguidEventContext);
  [PreserveSig] int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
  [PreserveSig] int GetMasterVolumeLevel(out float pfLevelDB);
  [PreserveSig] int GetMasterVolumeLevelScalar(out float pfLevel);
  [PreserveSig] int SetChannelVolumeLevel(uint nChannel, float fLevelDB, Guid pguidEventContext);
  [PreserveSig] int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, Guid pguidEventContext);
  [PreserveSig] int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
  [PreserveSig] int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
  [PreserveSig] int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
  [PreserveSig] int GetMute(out bool pbMute);
  [PreserveSig] int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
  [PreserveSig] int VolumeStepUp(Guid pguidEventContext);
  [PreserveSig] int VolumeStepDown(Guid pguidEventContext);
  [PreserveSig] int QueryHardwareSupport(out uint pdwHardwareSupportMask);
  [PreserveSig] int GetVolumeRange(out float pflVolumeMindB, out float pflVolumeMaxdB, out float pflVolumeIncrementdB);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
  [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioEndpointVolume ppInterface);
  [PreserveSig] int OpenPropertyStore(int stgmAccess, IntPtr ppProperties);
  [PreserveSig] int GetId(IntPtr ppstrId);
  [PreserveSig] int GetState(out int pdwState);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
  [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, uint dwStateMask, IntPtr ppDevices);
  [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppDevice);
  [PreserveSig] int GetDevice(string pwstrId, out IMMDevice ppDevice);
  [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr pClient);
  [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr pClient);
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumerator {}

public class KiomAudioEndpoint {
  const int CLSCTX_ALL = 23;

  static IAudioEndpointVolume Endpoint() {
    IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
    IMMDevice device;
    int hr = enumerator.GetDefaultAudioEndpoint(EDataFlow.eRender, ERole.eMultimedia, out device);
    Marshal.ThrowExceptionForHR(hr);

    Guid iid = typeof(IAudioEndpointVolume).GUID;
    IAudioEndpointVolume endpoint;
    hr = device.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out endpoint);
    Marshal.ThrowExceptionForHR(hr);

    Marshal.ReleaseComObject(device);
    Marshal.ReleaseComObject(enumerator);
    return endpoint;
  }

  public static void SetVolume(double value) {
    IAudioEndpointVolume endpoint = Endpoint();
    try {
      float clamped = (float)Math.Max(0.0, Math.Min(1.0, value));
      Marshal.ThrowExceptionForHR(endpoint.SetMasterVolumeLevelScalar(clamped, Guid.Empty));
      Marshal.ThrowExceptionForHR(endpoint.SetMute(false, Guid.Empty));
    } finally {
      Marshal.ReleaseComObject(endpoint);
    }
  }

  public static void StepUp() {
    IAudioEndpointVolume endpoint = Endpoint();
    try {
      Marshal.ThrowExceptionForHR(endpoint.VolumeStepUp(Guid.Empty));
      Marshal.ThrowExceptionForHR(endpoint.SetMute(false, Guid.Empty));
    } finally {
      Marshal.ReleaseComObject(endpoint);
    }
  }

  public static void StepDown() {
    IAudioEndpointVolume endpoint = Endpoint();
    try {
      Marshal.ThrowExceptionForHR(endpoint.VolumeStepDown(Guid.Empty));
    } finally {
      Marshal.ReleaseComObject(endpoint);
    }
  }

  public static void SetMuted(bool muted) {
    IAudioEndpointVolume endpoint = Endpoint();
    try {
      Marshal.ThrowExceptionForHR(endpoint.SetMute(muted, Guid.Empty));
    } finally {
      Marshal.ReleaseComObject(endpoint);
    }
  }

  public static string StateJson() {
    IAudioEndpointVolume endpoint = Endpoint();
    try {
      float volume;
      bool muted;
      Marshal.ThrowExceptionForHR(endpoint.GetMasterVolumeLevelScalar(out volume));
      Marshal.ThrowExceptionForHR(endpoint.GetMute(out muted));
      int percent = (int)Math.Round(volume * 100.0);
      return "{\"volume\":" + percent + ",\"muted\":" + (muted ? "true" : "false") + "}";
    } finally {
      Marshal.ReleaseComObject(endpoint);
    }
  }
}
"@
}
''';

  Future<WindowsControlResult> setWifi(bool enable) async {
    final script = '''
\$ErrorActionPreference = 'Stop'
Start-Service WlanSvc -ErrorAction SilentlyContinue
if (${enable ? r'$true' : r'$false'}) {
  \$adapters = Get-NetAdapter | Where-Object {
    \$_.Name -match 'Wi-?Fi|Wireless|WLAN' -or
    \$_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\\.11'
  }
  foreach (\$adapter in \$adapters) {
    if (\$adapter.Status -eq 'Disabled') {
      Enable-NetAdapter -Name \$adapter.Name -Confirm:\$false
    }
  }
  Start-Sleep -Milliseconds 800
  netsh wlan show interfaces | Out-String
} else {
  netsh wlan disconnect | Out-String
}
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable ? 'تم تشغيل WiFi' : 'تم فصل اتصال WiFi الحالي')
          : 'تعذر تغيير حالة WiFi: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setBluetooth(bool enable) async {
    final script = '''
\$ErrorActionPreference = 'Stop'
if (${enable ? r'$true' : r'$false'}) {
  Set-Service bthserv -StartupType Manual -ErrorAction SilentlyContinue
  Start-Service bthserv -ErrorAction SilentlyContinue
} else {
  Stop-Service bthserv -Force -ErrorAction SilentlyContinue
}
Get-Service bthserv | Select-Object Name, Status, StartType | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable ? 'تم تشغيل Bluetooth' : 'تم إيقاف Bluetooth')
          : 'تعذر تغيير حالة Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setInternetAdapters(bool enable) async {
    final script = '''
\$ErrorActionPreference = 'Stop'
\$adapters = Get-NetAdapter -Physical | Where-Object {
  \$_.InterfaceDescription -notmatch 'Bluetooth' -and
  \$_.Name -notmatch 'Loopback|vEthernet|VMware|VirtualBox'
}
if (-not \$adapters) { throw 'لم يتم العثور على كروت شبكة فعلية قابلة للتحكم.' }
foreach (\$adapter in \$adapters) {
  if (${enable ? r'$true' : r'$false'}) {
    Enable-NetAdapter -Name \$adapter.Name -Confirm:\$false
  } else {
    Disable-NetAdapter -Name \$adapter.Name -Confirm:\$false
  }
}
\$adapters | Select-Object Name, Status, InterfaceDescription | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable
              ? 'تم تشغيل كروت الإنترنت'
              : 'تم إيقاف الإنترنت نهائياً بتعطيل كروت الشبكة')
          : 'تعذر تغيير حالة الإنترنت النهائية: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> listBluetoothDevices() async {
    final result = await _runPowerShell(r'''
$ErrorActionPreference = 'SilentlyContinue'
$devices = Get-PnpDevice -Class Bluetooth | Where-Object {
  $_.FriendlyName -and $_.InstanceId -notmatch '^BTHENUM'
} | Select-Object FriendlyName, Status, InstanceId
if (-not $devices) { @() | ConvertTo-Json -Compress } else { $devices | ConvertTo-Json -Compress }
''');
    final payload = _payload(result);
    payload['devices'] = _decodePowerShellJsonList(result.stdout.toString());
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم جلب أجهزة Bluetooth'
          : 'تعذر جلب أجهزة Bluetooth: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> openBluetoothReceive({String? savePath}) async {
    final savePathJson = jsonEncode((savePath ?? '').trim());
    final script = '''
\$ErrorActionPreference = 'Stop'
\$savePath = $savePathJson
if (\$savePath -ne '') {
  New-Item -ItemType Directory -Path \$savePath -Force | Out-Null
  Start-Process explorer.exe -ArgumentList \$savePath
}
Start-Process fsquirt.exe -ArgumentList '-receive'
Write-Output '{"mode":"receive","savePath":' + (\$savePath | ConvertTo-Json -Compress) + '}'
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم فتح نافذة تلقي ملف عبر Bluetooth على الكمبيوتر'
          : 'تعذر فتح تلقي Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> sendBluetoothFile({
    required String path,
    String? deviceName,
  }) async {
    final pathJson = jsonEncode(path.trim());
    final deviceNameJson = jsonEncode((deviceName ?? '').trim());
    final script = '''
\$ErrorActionPreference = 'Stop'
\$path = $pathJson
\$deviceName = $deviceNameJson
if (-not (Test-Path -LiteralPath \$path)) { throw "الملف غير موجود: \$path" }
Start-Process explorer.exe -ArgumentList "/select,`"\$path`""
Start-Process fsquirt.exe -ArgumentList '-send'
[pscustomobject]@{ mode = 'send'; path = \$path; requestedDevice = \$deviceName } | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script);
    final payload = _payload(result);
    payload['requestedDevice'] = deviceName ?? '';
    payload['path'] = path;
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم فتح معالج إرسال Bluetooth على الكمبيوتر'
          : 'تعذر فتح إرسال Bluetooth: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> power(String action) async {
    late final ProcessResult result;
    switch (action) {
      case 'shutdown_pc':
      case 'shutdown':
        result = await Process.run('shutdown.exe', ['/s', '/t', '0']);
        break;
      case 'restart_pc':
      case 'restart':
        result = await Process.run('shutdown.exe', ['/r', '/t', '0']);
        break;
      case 'logout_user':
      case 'logout':
        result = await Process.run('shutdown.exe', ['/l']);
        break;
      default:
        throw StateError('أمر طاقة غير معروف: $action');
    }

    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم تنفيذ أمر الطاقة: $action'
          : 'تعذر تنفيذ أمر الطاقة: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setVolume(int volume) async {
    final clamped = volume.clamp(0, 100).toInt();
    final scalar = (clamped / 100).toStringAsFixed(3);
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::SetVolume($scalar)
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم ضبط الصوت إلى $clamped%',
      failureMessage: 'تعذر ضبط الصوت',
    );
  }

  Future<WindowsControlResult> volumeUp() async {
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::StepUp()
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم رفع الصوت',
      failureMessage: 'تعذر رفع الصوت',
    );
  }

  Future<WindowsControlResult> volumeDown() async {
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::StepDown()
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم خفض الصوت',
      failureMessage: 'تعذر خفض الصوت',
    );
  }

  Future<WindowsControlResult> setMuted(bool muted) async {
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::SetMuted(${muted ? r'$true' : r'$false'})
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: muted ? 'تم كتم الصوت' : 'تم إلغاء كتم الصوت',
      failureMessage: muted ? 'تعذر كتم الصوت' : 'تعذر إلغاء كتم الصوت',
    );
  }

  Future<ProcessResult> _runPowerShell(String script) {
    return Process.run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      runInShell: false,
    );
  }

  Map<String, dynamic> _payload(ProcessResult result) => {
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
      };

  WindowsControlResult _audioResult(
    ProcessResult result, {
    required String successMessage,
    required String failureMessage,
  }) {
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) {
          payload.addAll(decoded.cast<String, dynamic>());
        }
      } catch (_) {}
    }

    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? successMessage
          : '$failureMessage: ${_clean(result)}',
      payload: payload,
    );
  }

  String _clean(ProcessResult result) {
    final out = result.stdout.toString().trim();
    final err = result.stderr.toString().trim();
    final text = [out, err].where((e) => e.isNotEmpty).join(' | ');
    return text.isEmpty ? 'Exit code ${result.exitCode}' : text;
  }

  List<Map<String, dynamic>> _decodePowerShellJsonList(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
      }
      if (decoded is Map) return [decoded.cast<String, dynamic>()];
    } catch (_) {}
    return const [];
  }
}
