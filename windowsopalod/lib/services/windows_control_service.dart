import 'dart:convert';
import 'dart:io';

import '../utils/process_runner.dart';

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
\$ErrorActionPreference = 'SilentlyContinue'
Start-Service WlanSvc -ErrorAction SilentlyContinue
if (${enable ? r'$true' : r'$false'}) {
  \$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
    \$_.Name -match 'Wi-?Fi|Wireless|WLAN' -or
    \$_.InterfaceDescription -match 'Wi-?Fi|Wireless|WLAN|802\\.11'
  }
  foreach (\$adapter in \$adapters) {
    netsh interface set interface name="\$(\$adapter.Name)" admin=ENABLED 2>&1 | Out-Null
    Enable-NetAdapter -Name \$adapter.Name -Confirm:\$false -ErrorAction SilentlyContinue
  }
  Start-Sleep -Milliseconds 400
  netsh wlan show interfaces | Out-String
} else {
  netsh wlan disconnect 2>&1 | Out-String
}
[PSCustomObject]@{
  Enabled = ${enable ? r'$true' : r'$false'}
  Success = \$true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 8));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable ? 'تم تشغيل وتفعيل WiFi بنجاح' : 'تم فصل اتصال WiFi الحالي بنجاح')
          : 'تعذر تغيير حالة WiFi: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setBluetooth(bool enable) async {
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'

# 1. Native Windows WinRT Radio switch
try {
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    \$asTaskGeneric = [System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
        \$_.Name -eq 'AsTask' -and \$_.GetParameters().Count -eq 1 -and \$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
    } | Select-Object -First 1

    [Windows.Devices.Radios.Radio,Windows.System.Devices,ContentType=WindowsRuntime] | Out-Null
    \$op = [Windows.Devices.Radios.Radio]::GetRadiosAsync()
    \$task = \$asTaskGeneric.MakeGenericMethod([System.Collections.Generic.IReadOnlyList[Windows.Devices.Radios.Radio]]).Invoke(\$null, @(\$op))
    \$task.Wait(1500)
    \$radios = \$task.Result
    \$bt = \$radios | Where-Object { \$_.Kind -eq [Windows.Devices.Radios.RadioKind]::Bluetooth }
    if (\$bt) {
        \$targetState = if (${enable ? r'$true' : r'$false'}) { [Windows.Devices.Radios.RadioState]::On } else { [Windows.Devices.Radios.RadioState]::Off }
        \$setOp = \$bt.SetStateAsync(\$targetState)
        \$setTask = [System.WindowsRuntimeSystemExtensions]::AsTask(\$setOp)
        \$setTask.Wait(1500)
    }
} catch {}

# 2. Service level toggle as fallback (non-blocking)
if (${enable ? r'$true' : r'$false'}) {
    sc.exe config bthserv start= demand 2>&1 | Out-Null
    net start bthserv 2>&1 | Out-Null
} else {
    net stop bthserv /y 2>&1 | Out-Null
}

[PSCustomObject]@{
    Enabled = ${enable ? r'$true' : r'$false'}
    Success = \$true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 8));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable ? 'تم تشغيل Bluetooth بنجاح' : 'تم إيقاف Bluetooth بنجاح')
          : 'تعذر تغيير حالة Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setInternetAdapters(bool enable) async {
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'

# 1. Fast method using netsh (instantaneous execution)
\$adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object {
    \$_.InterfaceDescription -notmatch 'Bluetooth' -and
    \$_.Name -notmatch 'Loopback|vEthernet|VMware|VirtualBox'
}

if (-not \$adapters -or \$adapters.Count -eq 0) {
    \$adapters = Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
        \$_.InterfaceDescription -notmatch 'Bluetooth'
    }
}

\$action = if (${enable ? r'$true' : r'$false'}) { "enable" } else { "disable" }
\$adminState = if (${enable ? r'$true' : r'$false'}) { "ENABLED" } else { "DISABLED" }

foreach (\$adapter in \$adapters) {
    netsh interface set interface name="\$(\$adapter.Name)" admin=\$adminState 2>&1 | Out-Null
    if (${enable ? r'$true' : r'$false'}) {
        Enable-NetAdapter -Name \$adapter.Name -Confirm:\$false -ErrorAction SilentlyContinue
    } else {
        Disable-NetAdapter -Name \$adapter.Name -Confirm:\$false -ErrorAction SilentlyContinue
    }
}

[PSCustomObject]@{
    Action = \$action
    AdaptersCount = if (\$adapters) { \$adapters.Count } else { 0 }
    Success = \$true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 8));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? (enable
              ? 'تم تشغيل كروت الإنترنت والشبكة بنجاح'
              : 'تم إيقاف الإنترنت نهائياً بتعطيل كروت الشبكة بنجاح')
          : 'تعذر تغيير حالة الإنترنت: ${_clean(result)}',
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

  Future<WindowsControlResult> systemHealth() async {
    final result = await _runPowerShell(r'''
$ErrorActionPreference = 'SilentlyContinue'
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
  [PSCustomObject]@{
    name = $_.DeviceID
    label = $_.VolumeName
    totalBytes = [Int64]$_.Size
    freeBytes = [Int64]$_.FreeSpace
    usedPercent = if ($_.Size) { [Math]::Round((($_.Size - $_.FreeSpace) / $_.Size) * 100, 1) } else { 0 }
  }
}
$battery = Get-CimInstance Win32_Battery | Select-Object -First 1
$batteryInfo = $null
if ($battery) {
  $batteryInfo = [PSCustomObject]@{
    percent = [int]$battery.EstimatedChargeRemaining
    status = [int]$battery.BatteryStatus
  }
}
$uptime = if ($os.LastBootUpTime) { [int]((Get-Date) - $os.LastBootUpTime).TotalMinutes } else { 0 }
$totalMemory = [Int64]$os.TotalVisibleMemorySize * 1024
$freeMemory = [Int64]$os.FreePhysicalMemory * 1024
$usedMemory = $totalMemory - $freeMemory
$memoryUsedPercent = if ($totalMemory) { [Math]::Round(($usedMemory / $totalMemory) * 100, 1) } else { 0 }
[PSCustomObject]@{
  computerName = $env:COMPUTERNAME
  windowsUser = $env:USERNAME
  os = $os.Caption
  uptimeMinutes = $uptime
  cpuLoadPercent = [int]($cpu.LoadPercentage)
  memory = [PSCustomObject]@{
    totalBytes = $totalMemory
    freeBytes = $freeMemory
    usedBytes = $usedMemory
    usedPercent = $memoryUsedPercent
  }
  battery = $batteryInfo
  disks = @($disks)
  checkedAt = (Get-Date).ToString('o')
} | ConvertTo-Json -Compress -Depth 5
''');

    final payload = _payload(result);
    final text = result.stdout.toString().trim();
    if (text.startsWith('{')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }

    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم جلب صحة الجهاز'
          : 'تعذر جلب صحة الجهاز: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> power(String action) async {
    late final ProcessResult result;
    switch (action) {
      case 'shutdown_pc':
      case 'shutdown':
        result = await SafeProcessRunner.run(
          'shutdown.exe',
          ['/s', '/t', '0'],
          timeout: SafeProcessRunner.shortTimeout,
        );
        break;
      case 'restart_pc':
      case 'restart':
        result = await SafeProcessRunner.run(
          'shutdown.exe',
          ['/r', '/t', '0'],
          timeout: SafeProcessRunner.shortTimeout,
        );
        break;
      case 'logout_user':
      case 'logout':
        result = await SafeProcessRunner.run(
          'shutdown.exe',
          ['/l'],
          timeout: SafeProcessRunner.shortTimeout,
        );
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

  Future<WindowsControlResult> openBrowserUrl(String url) async {
    final cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      return const WindowsControlResult(
        success: false,
        message: 'يجب أن يبدأ الرابط بـ http:// أو https://',
      );
    }
    final escaped = cleanUrl.replaceAll("'", "''");
    final result = await _runPowerShell("Start-Process '$escaped'");
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم فتح الرابط في المتصفح' : 'تعذر فتح الرابط',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> triggerSirenAlarm({int seconds = 8}) async {
    final dur = seconds.clamp(2, 30);
    final script = '''
$_audioPowerShell
[KiomAudioEndpoint]::SetMuted(\$false)
[KiomAudioEndpoint]::SetVolume(1.0)
\$stopTime = (Get-Date).AddSeconds($dur)
while ((Get-Date) -lt \$stopTime) {
  [console]::beep(2000, 300)
  [console]::beep(1200, 300)
}
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: true,
      message: 'تم تشغيل صافرة الإنذار لمدة $dur ثوانٍ بأقصى مستوى صوت',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> simulateKeyPress(String keys) async {
    final clean = keys.trim();
    if (clean.isEmpty) {
      return const WindowsControlResult(
        success: false,
        message: 'مفتاح غير صالح',
      );
    }
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait('$clean')
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تمت محاكاة ضغطة المفتاح: $clean' : 'تعذر إرسال ضغطة المفتاح',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> downloadRemoteFile(String url, {String? targetFolder}) async {
    final cleanUrl = url.trim();
    if (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://')) {
      return const WindowsControlResult(
        success: false,
        message: 'الرابط غير صالح',
      );
    }
    final folder = targetFolder?.trim().isNotEmpty == true
        ? targetFolder!.trim()
        : r'$env:USERPROFILE\Downloads';
    final script = '''
\$destDir = "$folder"
if (-not (Test-Path \$destDir)) { New-Item -ItemType Directory -Path \$destDir -Force | Out-Null }
\$uri = [System.Uri]"$cleanUrl"
\$fileName = [System.IO.Path]::GetFileName(\$uri.LocalPath)
if ([string]::IsNullOrWhiteSpace(\$fileName)) { \$fileName = "download_" + [guid]::NewGuid().ToString().Substring(0,8) + ".dat" }
\$destPath = Join-Path \$destDir \$fileName
Start-BitsTransfer -Source "$cleanUrl" -Destination \$destPath -ErrorAction SilentlyContinue
if (-not (Test-Path \$destPath)) {
  Invoke-WebRequest -Uri "$cleanUrl" -OutFile \$destPath -UseBasicParsing
}
[PSCustomObject]@{
  SavedPath = \$destPath
  FileName = \$fileName
  Size = (Get-Item \$destPath).Length
} | ConvertTo-Json -Compress
''';
    final result = await SafeProcessRunner.powershell(script, timeout: const Duration(minutes: 5));
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم تنزيل الملف بنجاح إلى: ${payload['SavedPath'] ?? folder}' : 'فشل تنزيل الملف',
      payload: payload,
    );
  }

  Future<WindowsControlResult> recordMicrophoneAudio({
    int seconds = 8,
    String? outputPath,
  }) async {
    final dur = seconds.clamp(2, 30);
    final target = outputPath ??
        '${Directory.systemTemp.path}\\kiom_mic_${DateTime.now().millisecondsSinceEpoch}.wav';
    final script = '''
\$ErrorActionPreference = 'Stop'
\$target = '$target'

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Threading;

public class KiomAudioRecorder {
    [DllImport("winmm.dll", EntryPoint = "mciSendStringA", CharSet = CharSet.Ansi, SetLastError = true, ExactSpelling = true)]
    private static extern int mciSendString(string lpstrCommand, string lpstrReturnString, int uReturnLength, int hwndCallback);

    public static bool Record(string path, int durationSeconds) {
        try {
            mciSendString("close recsound", "", 0, 0);
            mciSendString("open new Type waveaudio Alias recsound", "", 0, 0);
            mciSendString("record recsound", "", 0, 0);
            Thread.Sleep(durationSeconds * 1000);
            mciSendString("save recsound \\"" + path + "\\"", "", 0, 0);
            mciSendString("close recsound", "", 0, 0);
            return System.IO.File.Exists(path) && (new System.IO.FileInfo(path)).Length > 100;
        } catch {
            return false;
        }
    }
}
"@ -ErrorAction SilentlyContinue

\$res = [KiomAudioRecorder]::Record(\$target, $dur)
if (\$res -and (Test-Path \$target)) {
    [PSCustomObject]@{
        Success = \$true
        Path = \$target
        Size = (Get-Item \$target).Length
    } | ConvertTo-Json -Compress
} else {
    throw "Failed to record audio from microphone"
}
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: Duration(seconds: dur + 10),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    final file = File(target);
    final exists = await file.exists();
    return WindowsControlResult(
      success: exists && (await file.length()) > 100,
      message: exists ? 'تم تسجيل الصوت بنجاح' : 'تعذر تسجيل الصوت من الميكروفون',
      payload: {...payload, 'filePath': target},
    );
  }

  Future<WindowsControlResult> captureWebcamPhoto({String? outputPath}) async {
    final target = outputPath ??
        '${Directory.systemTemp.path}\\kiom_cam_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final script = '''
\$ErrorActionPreference = 'Stop'
\$target = '$target'

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Drawing;
using System.Drawing.Imaging;

public class KiomWebcam {
    [DllImport("avicap32.dll")]
    public static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWnd, int nID);

    [DllImport("user32.dll", EntryPoint = "SendMessage")]
    public static extern int SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);

    [DllImport("user32.dll", EntryPoint = "SendMessage")]
    public static extern int SendMessageString(IntPtr hWnd, uint Msg, int wParam, string lParam);

    [DllImport("user32.dll")]
    public static extern bool DestroyWindow(IntPtr hWnd);

    public const int WM_CAP_CONNECT = 0x40A;
    public const int WM_CAP_DISCONNECT = 0x40B;
    public const int WM_CAP_GRAB_FRAME = 0x43C;
    public const int WM_CAP_SAVEDIB = 0x419;

    public static bool Capture(string path) {
        IntPtr hWnd = capCreateCaptureWindowA("KiomCam", 0, 0, 0, 640, 480, IntPtr.Zero, 0);
        if (hWnd == IntPtr.Zero) return false;
        try {
            if (SendMessage(hWnd, WM_CAP_CONNECT, 0, 0) != 0) {
                System.Threading.Thread.Sleep(500);
                SendMessage(hWnd, WM_CAP_GRAB_FRAME, 0, 0);
                string bmpPath = path + ".bmp";
                SendMessageString(hWnd, WM_CAP_SAVEDIB, 0, bmpPath);
                SendMessage(hWnd, WM_CAP_DISCONNECT, 0, 0);
                DestroyWindow(hWnd);

                if (System.IO.File.Exists(bmpPath)) {
                    using (Image img = Image.FromFile(bmpPath)) {
                        img.Save(path, ImageFormat.Jpeg);
                    }
                    System.IO.File.Delete(bmpPath);
                    return true;
                }
            }
        } catch {}
        if (hWnd != IntPtr.Zero) DestroyWindow(hWnd);
        return false;
    }
}
"@ -ErrorAction SilentlyContinue

\$res = [KiomWebcam]::Capture(\$target)
if (\$res -and (Test-Path \$target)) {
    [PSCustomObject]@{
        Success = \$true
        Path = \$target
        Size = (Get-Item \$target).Length
    } | ConvertTo-Json -Compress
} else {
    throw "No webcam connected or failed to capture frame"
}
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(seconds: 15),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    final file = File(target);
    final exists = await file.exists();
    return WindowsControlResult(
      success: exists && (await file.length()) > 100,
      message: exists ? 'تم التقاط صورة من كاميرا الويب بنجاح' : 'تعذر التقاط صورة (تأكد من توصيل الكاميرا)',
      payload: {...payload, 'filePath': target},
    );
  }

  Future<WindowsControlResult> uploadFileToCloudUrl(String localPath, String uploadUrl) async {
    final cleanPath = localPath.trim();
    final cleanUrl = uploadUrl.trim();

    final script = '''
\$ErrorActionPreference = 'Stop'
\$path = "$cleanPath"
\$url = "$cleanUrl"

if (-not (Test-Path \$path)) { throw "File or folder does not exist: \$path" }

\$uploadFile = \$path
\$isDir = (Get-Item \$path) -is [System.IO.DirectoryInfo]
if (\$isDir) {
    \$zipPath = Join-Path \$env:TEMP ("kiom_cloud_" + [guid]::NewGuid().ToString().Substring(0,8) + ".zip")
    Compress-Archive -Path "\$path\\*" -DestinationPath \$zipPath -Force
    \$uploadFile = \$zipPath
}

\$fileBytes = [System.IO.File]::ReadAllBytes(\$uploadFile)
\$fileName = [System.IO.Path]::GetFileName(\$uploadFile)

\$headers = @{
    "User-Agent" = "KiomCloudUploader/1.0"
}

try {
    # Attempt PUT upload first (Common for OneDrive / Google Drive / S3 pre-signed upload URLs)
    \$resp = Invoke-RestMethod -Uri \$url -Method Put -Body \$fileBytes -Headers \$headers -ContentType "application/octet-stream" -ErrorAction Stop
    [PSCustomObject]@{
        Success = \$true
        Method = "PUT"
        File = \$fileName
        Response = (\$resp | Out-String).Trim()
    } | ConvertTo-Json -Compress
} catch {
    # Fallback to POST multipart upload (Webhooks / Form upload endpoints)
    \$resp = Invoke-RestMethod -Uri \$url -Method Post -InFile \$uploadFile -Headers \$headers -ErrorAction Stop
    [PSCustomObject]@{
        Success = \$true
        Method = "POST"
        File = \$fileName
        Response = (\$resp | Out-String).Trim()
    } | ConvertTo-Json -Compress
}
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(minutes: 10),
    );
    final payload = _payload(result);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم رفع الملف بنجاح إلى الرابط السحابي'
          : 'تعذر رفع الملف إلى الرابط: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> copyToCloudSyncFolder(String localPath, {String provider = 'onedrive'}) async {
    final cleanPath = localPath.trim();
    final script = '''
\$ErrorActionPreference = 'Stop'
\$src = "$cleanPath"
if (-not (Test-Path \$src)) { throw "File or folder does not exist: \$src" }

\$provider = "$provider".ToLower()
\$targetDir = ""

if (\$provider -eq "onedrive") {
    \$candidates = @(
        \$env:OneDrive,
        (Join-Path \$env:USERPROFILE "OneDrive"),
        (Join-Path \$env:USERPROFILE "OneDrive - Personal")
    )
    foreach (\$c in \$candidates) {
        if (\$c -and (Test-Path \$c)) { \$targetDir = Join-Path \$c "KiomUploads"; break }
    }
} else {
    \$candidates = @(
        "G:\\My Drive",
        "G:\\Drive",
        (Join-Path \$env:USERPROFILE "Google Drive"),
        (Join-Path \$env:USERPROFILE "GoogleDrive")
    )
    foreach (\$c in \$candidates) {
        if (\$c -and (Test-Path \$c)) { \$targetDir = Join-Path \$c "KiomUploads"; break }
    }
}

if (-not \$targetDir) {
    throw "Cloud folder for '\$provider' is not configured or not found on this PC."
}

if (-not (Test-Path \$targetDir)) {
    New-Item -ItemType Directory -Path \$targetDir -Force | Out-Null
}

Copy-Item -Path \$src -Destination \$targetDir -Recurse -Force
[PSCustomObject]@{
    Provider = \$provider
    Destination = \$targetDir
    FileName = [System.IO.Path]::GetFileName(\$src)
} | ConvertTo-Json -Compress
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(minutes: 2),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم نسخ الملف إلى مجلد $provider السحابي (${payload['Destination'] ?? ''})، وسيقوم بالمزامنة تلقائياً في الخلفية.'
          : 'تعذر النسخ: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> uploadToFastCloud(String localPath) async {
    final cleanPath = localPath.trim();
    final script = '''
\$ErrorActionPreference = 'Stop'
\$path = "$cleanPath"
if (-not (Test-Path \$path)) { throw "File or folder does not exist: \$path" }

\$uploadFile = \$path
\$isDir = (Get-Item \$path) -is [System.IO.DirectoryInfo]
if (\$isDir) {
    \$zipPath = Join-Path \$env:TEMP ("kiom_cloud_" + [guid]::NewGuid().ToString().Substring(0,8) + ".zip")
    Compress-Archive -Path "\$path\\*" -DestinationPath \$zipPath -Force
    \$uploadFile = \$zipPath
}

# Upload to tmpfiles.org
try {
    \$resp = Invoke-RestMethod -Uri "https://tmpfiles.org/api/v1/upload" -Method Post -InFile \$uploadFile -Form @{ file = (Get-Item \$uploadFile) } -ErrorAction Stop
    \$url = \$resp.data.url
    # Convert view URL to direct download URL
    if (\$url -match "tmpfiles.org/(.+)") {
        \$directUrl = "https://tmpfiles.org/dl/" + \$matches[1]
    } else {
        \$directUrl = \$url
    }
    [PSCustomObject]@{
        Success = \$true
        DirectUrl = \$directUrl
        ViewUrl = \$url
        FileName = [System.IO.Path]::GetFileName(\$uploadFile)
    } | ConvertTo-Json -Compress
} catch {
    # Fallback to transfer.sh
    \$fileName = [System.IO.Path]::GetFileName(\$uploadFile)
    \$resp = Invoke-RestMethod -Uri ("https://transfer.sh/" + \$fileName) -Method Put -InFile \$uploadFile -ErrorAction Stop
    [PSCustomObject]@{
        Success = \$true
        DirectUrl = \$resp.ToString().Trim()
        FileName = \$fileName
    } | ConvertTo-Json -Compress
}
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(minutes: 5),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    final directUrl = payload['DirectUrl'] ?? '';
    return WindowsControlResult(
      success: result.exitCode == 0 && directUrl.toString().isNotEmpty,
      message: result.exitCode == 0
          ? 'تم رفع الملف بنجاح! الرابط السحابي:\n$directUrl'
          : 'فشل الرفع السحابي: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> cleanupSystemTempFiles() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$initialFree = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like 'C:*' }).Free

Remove-Item -Path "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

$finalFree = (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -like 'C:*' }).Free
$freedBytes = [Math]::Max(0, ($finalFree - $initialFree))
$freedMB = [Math]::Round($freedBytes / 1MB, 2)

[PSCustomObject]@{
    Success = $true
    FreedMB = $freedMB
    FreedBytes = $freedBytes
} | ConvertTo-Json -Compress
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(minutes: 2),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    final freedMB = payload['FreedMB'] ?? 0;
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم تنظيف الملفات المؤقتة وسلة المحذوفات بنجاح! تم تحرير حوالي $freedMB ميجابايت من المساحة.'
          : 'تعذر تنظيف بعض الملفات المؤقتة',
      payload: payload,
    );
  }

  Future<WindowsControlResult> getRunningProcessesReport() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$procs = Get-Process | Sort-Object -Property WS -Descending | Select-Object -First 15 | ForEach-Object {
    [PSCustomObject]@{
        Id = $_.Id
        Name = $_.ProcessName
        MemMB = [Math]::Round($_.WS / 1MB, 1)
        CPU = if ($_.CPU) { [Math]::Round($_.CPU, 1) } else { 0 }
        Title = if ($_.MainWindowTitle) { $_.MainWindowTitle } else { '' }
    }
}
$procs | ConvertTo-Json -Compress
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(seconds: 8),
    );
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    final items = _decodePowerShellJsonList(stdout);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم جلب تقرير استهلاك العمليات والذاكرة'
          : 'فشل جلب العمليات',
      payload: {'items': items},
    );
  }

  Future<ProcessResult> _runPowerShell(String script) {
    return SafeProcessRunner.powershell(
      script,
      timeout: SafeProcessRunner.defaultTimeout,
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
