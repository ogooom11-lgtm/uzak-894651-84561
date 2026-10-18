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
using System.IO;
using System.Media;
using System.Threading;

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
public interface IAudioEndpointVolume {
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
public interface IMMDevice {
  [PreserveSig] int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, out IAudioEndpointVolume ppInterface);
  [PreserveSig] int OpenPropertyStore(int stgmAccess, IntPtr ppProperties);
  [PreserveSig] int GetId(IntPtr ppstrId);
  [PreserveSig] int GetState(out int pdwState);
}

[Guid("0BD7A1BE-7A1A-44DB-8397-CC5392387B5E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceCollection {
  [PreserveSig] int GetCount(out uint pcDevices);
  [PreserveSig] int Item(uint nDevice, out IMMDevice ppDevice);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
  [PreserveSig] int EnumAudioEndpoints(EDataFlow dataFlow, uint dwStateMask, out IMMDeviceCollection ppDevices);
  [PreserveSig] int GetDefaultAudioEndpoint(EDataFlow dataFlow, ERole role, out IMMDevice ppDevice);
  [PreserveSig] int GetDevice(string pwstrId, out IMMDevice ppDevice);
  [PreserveSig] int RegisterEndpointNotificationCallback(IntPtr pClient);
  [PreserveSig] int UnregisterEndpointNotificationCallback(IntPtr pClient);
}

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
public class MMDeviceEnumerator {}

[Guid("f8679f50-850a-41cf-9c72-430f290290c8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IPolicyConfig {
  [PreserveSig] int GetMixFormat(string pszDeviceName, IntPtr ppFormat);
  [PreserveSig] int GetDeviceFormat(string pszDeviceName, int bDefault, IntPtr ppFormat);
  [PreserveSig] int ResetDeviceFormat(string pszDeviceName);
  [PreserveSig] int SetDeviceFormat(string pszDeviceName, IntPtr pEndpointFormat, IntPtr mixFormat);
  [PreserveSig] int GetProcessingPeriod(string pszDeviceName, int bDefault, IntPtr pmftDefaultPeriod, IntPtr pmftMinimumPeriod);
  [PreserveSig] int SetProcessingPeriod(string pszDeviceName, IntPtr pmftPeriod);
  [PreserveSig] int GetShareMode(string pszDeviceName, IntPtr pMode);
  [PreserveSig] int SetShareMode(string pszDeviceName, IntPtr mode);
  [PreserveSig] int GetPropertyValue(string pszDeviceName, bool bFxStore, IntPtr key, IntPtr pv);
  [PreserveSig] int SetPropertyValue(string pszDeviceName, bool bFxStore, IntPtr key, IntPtr pv);
  [PreserveSig] int SetDefaultEndpoint([MarshalAs(UnmanagedType.LPWStr)] string pszDeviceName, ERole role);
  [PreserveSig] int SetEndpointVisibility(string pszDeviceName, int bVisible);
}

[ComImport]
[Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")]
public class PolicyConfigClient {}

public class KiomAudioEndpoint {
  const int CLSCTX_ALL = 23;
  const uint DEVICE_STATE_ACTIVE = 0x00000001;

  [DllImport("kernel32.dll", SetLastError = true)]
  public static extern bool Beep(int dwFreq, int dwDuration);

  public static void MaximizeAllEndpoints() {
    try {
      IMMDeviceEnumerator enumerator = (IMMDeviceEnumerator)(new MMDeviceEnumerator());
      IMMDeviceCollection collection;
      int hr = enumerator.EnumAudioEndpoints(EDataFlow.eRender, DEVICE_STATE_ACTIVE, out collection);
      if (hr == 0 && collection != null) {
        uint count = 0;
        collection.GetCount(out count);
        Guid iid = typeof(IAudioEndpointVolume).GUID;

        for (uint i = 0; i < count; i++) {
          try {
            IMMDevice dev;
            collection.Item(i, out dev);
            if (dev != null) {
              IAudioEndpointVolume vol;
              dev.Activate(ref iid, CLSCTX_ALL, IntPtr.Zero, out vol);
              if (vol != null) {
                vol.SetMasterVolumeLevelScalar(1.0f, Guid.Empty);
                vol.SetMute(false, Guid.Empty);
                Marshal.ReleaseComObject(vol);
              }
              Marshal.ReleaseComObject(dev);
            }
          } catch {}
        }
        Marshal.ReleaseComObject(collection);
      }
      Marshal.ReleaseComObject(enumerator);
    } catch {}
  }

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
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
Get-PnpDevice -Class Bluetooth |
  Select-Object FriendlyName, InstanceId, Status, Present |
  ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم جلب أجهزة Bluetooth'
          : 'تعذر جلب أجهزة Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> openBluetoothReceive() async {
    final result = await _runPowerShell('Start-Process "fsquirt.exe" -ArgumentList "-r"');
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم فتح نافذة استقبال الملفات عبر Bluetooth'
          : 'تعذر فتح نافذة استقبال Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> sendBluetoothFile(String filePath) async {
    final cleanPath = filePath.trim();
    if (cleanPath.isEmpty) {
      return const WindowsControlResult(
        success: false,
        message: 'مسار الملف غير محدد',
      );
    }
    final escaped = cleanPath.replaceAll("'", "''");
    final result = await _runPowerShell(
      "Start-Process 'fsquirt.exe' -ArgumentList '-s \"$escaped\"'",
    );
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? 'تم فتح نافذة إرسال الملف عبر Bluetooth'
          : 'تعذر فتح نافذة إرسال Bluetooth: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> setMasterVolume(double value) async {
    final clamped = value.clamp(0.0, 1.0);
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::SetVolume($clamped)
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم ضبط مستوى الصوت إلى ${(clamped * 100).round()}%',
      failureMessage: 'تعذر ضبط مستوى الصوت',
    );
  }

  Future<WindowsControlResult> stepVolumeUp() async {
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::StepUp()
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم رفع مستوى الصوت',
      failureMessage: 'تعذر رفع مستوى الصوت',
    );
  }

  Future<WindowsControlResult> stepVolumeDown() async {
    final result = await _runPowerShell('''
$_audioPowerShell
[KiomAudioEndpoint]::StepDown()
[KiomAudioEndpoint]::StateJson()
''');
    return _audioResult(
      result,
      successMessage: 'تم خفض مستوى الصوت',
      failureMessage: 'تعذر خفض مستوى الصوت',
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
try { [KiomAudioEndpoint]::MaximizeAllEndpoints() } catch {}
try { [KiomAudioEndpoint]::SetMuted(\$false) } catch {}
try { [KiomAudioEndpoint]::SetVolume(1.0) } catch {}

# Run alarm sounding from PC internal speakers and motherboard beeper
\$stopTime = (Get-Date).AddSeconds($dur)
while ((Get-Date) -lt \$stopTime) {
  # 1. Motherboard chassis beeper / internal speaker tone
  [KiomAudioEndpoint]::Beep(2600, 180)
  [KiomAudioEndpoint]::Beep(1300, 180)
  [KiomAudioEndpoint]::Beep(3400, 220)
  [KiomAudioEndpoint]::Beep(850, 220)
  
  # 2. System loud acoustic wave sound
  [System.Media.SystemSounds]::Exclamation.Play()
}
''';
    final result = await _runPowerShell(script, timeout: Duration(seconds: dur + 5));
    return WindowsControlResult(
      success: true,
      message: '🚨 تم تشغيل صافرة الإنذار من سماعات الكمبيوتر الداخلية والمذربورد لمدة $dur ثوانٍ بأقصى مستوى صوت',
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
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Runtime.InteropServices;

public class KiomAudioRecorder {
    [DllImport("winmm.dll", EntryPoint = "mciSendStringA", CharSet = CharSet.Ansi, SetLastError = true, ExactSpelling = true)]
    public static extern int mciSendString(string lpstrCommand, string lpstrReturnString, int uReturnLength, int hwndCallback);

    public static void Record(string filePath, int durationMs) {
        mciSendString("open new Type waveaudio Alias recsound", "", 0, 0);
        mciSendString("record recsound", "", 0, 0);
        System.Threading.Thread.Sleep(durationMs);
        mciSendString("save recsound " + filePath, "", 0, 0);
        mciSendString("close recsound", "", 0, 0);
    }
}
"@

\$tmpPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "kiom_mic_" + [guid]::NewGuid().ToString().Substring(0,8) + ".wav")
[KiomAudioRecorder]::Record(\$tmpPath, ${dur * 1000})

if (Test-Path \$tmpPath) {
    [PSCustomObject]@{
        SavedPath = \$tmpPath
        Duration = $dur
        Size = (Get-Item \$tmpPath).Length
    } | ConvertTo-Json -Compress
} else {
    throw "فشل تسجيل الصوت من المايكروفون"
}
''';
    final result = await SafeProcessRunner.powershell(script, timeout: Duration(seconds: dur + 10));
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    return WindowsControlResult(
      success: result.exitCode == 0 && payload.containsKey('SavedPath'),
      message: result.exitCode == 0 ? 'تم تسجيل مقطع صوتي بنجاح (${dur}s)' : 'تعذر تسجيل الصوت من المايكروفون: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> captureWebcamPhoto({String? outputPath}) async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$targetPath = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "kiom_cam_" + [guid]::NewGuid().ToString().Substring(0,8) + ".jpg")

# Fast direct PowerShell DirectShow / Windows Media Capture trigger
$code = @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public class KiomWebcamCapture {
    [DllImport("avicap32.dll")]
    public static extern IntPtr capCreateCaptureWindowA(string lpszWindowName, int dwStyle, int x, int y, int nWidth, int nHeight, IntPtr hWnd, int nID);

    [DllImport("user32.dll")]
    public static extern bool SendMessage(IntPtr hWnd, uint Msg, int wParam, int lParam);

    [DllImport("user32.dll")]
    public static extern bool DestroyWindow(IntPtr hWnd);

    public static bool Capture(string filePath) {
        IntPtr hWnd = capCreateCaptureWindowA("KiomCam", 0, 0, 0, 640, 480, IntPtr.Zero, 0);
        if (hWnd == IntPtr.Zero) return false;
        try {
            // WM_CAP_DRIVER_CONNECT = 0x40A, WM_CAP_GRAB_FRAME = 0x43C, WM_CAP_SAVEDIB = 0x419, WM_CAP_DRIVER_DISCONNECT = 0x40B
            SendMessage(hWnd, 0x40A, 0, 0);
            System.Threading.Thread.Sleep(500);
            SendMessage(hWnd, 0x43C, 0, 0);
            SendMessage(hWnd, 0x419, 0, Marshal.StringToHGlobalAnsi(filePath).ToInt32());
            SendMessage(hWnd, 0x40B, 0, 0);
            return System.IO.File.Exists(filePath);
        } catch {
            return false;
        } finally {
            DestroyWindow(hWnd);
        }
    }
}
"@
Add-Type -TypeDefinition $code -ReferencedAssemblies System.Drawing

$captured = [KiomWebcamCapture]::Capture($targetPath)
if ($captured -and (Test-Path $targetPath)) {
    [PSCustomObject]@{
        SavedPath = $targetPath
        Size = (Get-Item $targetPath).Length
    } | ConvertTo-Json -Compress
} else {
    # Fallback to screenshot if camera device is unavailable
    Add-Type -AssemblyName System.Windows.Forms
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
    $bitmap.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    $graphics.Dispose()
    $bitmap.Dispose()
    [PSCustomObject]@{
        SavedPath = $targetPath
        Fallback = $true
        Size = (Get-Item $targetPath).Length
    } | ConvertTo-Json -Compress
}
''';
    final result = await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 15));
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    return WindowsControlResult(
      success: result.exitCode == 0 && payload.containsKey('SavedPath'),
      message: result.exitCode == 0 ? 'تم التقاط صورة الكاميرا بنجاح' : 'تعذر التقاط صورة الكاميرا: ${_clean(result)}',
      payload: payload,
    );
  }

  Future<WindowsControlResult> sendWindowsNotification({
    required String title,
    required String message,
  }) async {
    final cleanTitle = title.trim().isEmpty ? 'KIOM' : title.trim();
    final cleanMsg = message.trim().isEmpty ? 'تنبيه جديد' : message.trim();
    final escapedTitle = cleanTitle.replaceAll("'", "''");
    final escapedMsg = cleanMsg.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
\$notification = New-Object System.Windows.Forms.NotifyIcon
\$notification.Icon = [System.Drawing.SystemIcons]::Information
\$notification.BalloonTipTitle = '$escapedTitle'
\$notification.BalloonTipText = '$escapedMsg'
\$notification.BalloonTipIcon = 'Info'
\$notification.Visible = \$true
\$notification.ShowBalloonTip(5000)
Start-Sleep -Milliseconds 500
\$notification.Dispose()
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم إرسال الإشعار على شاشة الويندوز' : 'تعذر إرسال الإشعار',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> speakText(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      return const WindowsControlResult(
        success: false,
        message: 'النص المطلوب نطقه فارغ',
      );
    }
    final escaped = clean.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Speech
\$synth = New-Object System.Speech.Synthesis.SpeechSynthesizer
\$synth.Volume = 100
\$synth.Rate = 0
\$synth.Speak('$escaped')
\$synth.Dispose()
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم نطق النص بالصوت على الكمبيوتر' : 'تعذر نطق النص',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> getClipboardText() async {
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Clipboard]::GetText()
''';
    final result = await _runPowerShell(script);
    final text = result.stdout.toString().trim();
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم جلب محتوى الحافظة' : 'تعذر جلب الحافظة',
      payload: {'clipboardText': text},
    );
  }

  Future<WindowsControlResult> setClipboardText(String text) async {
    final escaped = text.replaceAll("'", "''");
    final script = '''
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.Clipboard]::SetText('$escaped')
''';
    final result = await _runPowerShell(script);
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم نسخ النص إلى الحافظة' : 'تعذر نسخ النص للحافظة',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> getSystemSpecs() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3"

$diskInfo = @()
foreach ($d in $disks) {
  $diskInfo += [PSCustomObject]@{
    Drive = $d.DeviceID
    FreeGB = [math]::Round($d.FreeSpace / 1GB, 1)
    TotalGB = [math]::Round($d.Size / 1GB, 1)
  }
}

[PSCustomObject]@{
  ComputerName = $env:COMPUTERNAME
  UserName = $env:USERNAME
  OSName = $os.Caption
  OSVersion = $os.Version
  OSArchitecture = $os.OSArchitecture
  CpuName = $cpu.Name.Trim()
  CpuCores = $cpu.NumberOfCores
  CpuLogical = $cpu.NumberOfLogicalProcessors
  TotalRamGB = [math]::Round($cs.TotalPhysicalMemory / 1GB, 1)
  FreeRamGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
  GpuName = $gpu.Name
  Disks = $diskInfo
  UptimeHours = [math]::Round(((Get-Date) - $os.LastBootUpTime).TotalHours, 1)
} | ConvertTo-Json -Compress -Depth 3
''';
    final result = await _runPowerShell(script);
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
      message: result.exitCode == 0 ? 'تم جلب مواصفات النظام' : 'تعذر جلب المواصفات',
      payload: payload,
    );
  }

  Future<WindowsControlResult> cleanupTempFiles() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$totalFreedBytes = 0

$tempPaths = @(
  $env:TEMP,
  "C:\Windows\Temp",
  "C:\Windows\Prefetch"
)

foreach ($p in $tempPaths) {
  if (Test-Path $p) {
    Get-ChildItem -Path $p -Recurse -Force -ErrorAction SilentlyContinue | ForEach-Object {
      try {
        $len = $_.Length
        Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if ($len) { $totalFreedBytes += $len }
      } catch {}
    }
  }
}

[PSCustomObject]@{
  FreedMB = [math]::Round($totalFreedBytes / 1MB, 2)
  Success = $true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 30));
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('{')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is Map) payload.addAll(decoded.cast<String, dynamic>());
      } catch (_) {}
    }
    final mb = payload['FreedMB'] ?? '0';
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0
          ? '🧹 تم تنظيف الملفات المؤقتة والذاكرة الخبيئة بنجاح (تم تحرير $mb ميجابايت)'
          : 'تعذر إتمام تنظيف الملفات المؤقتة',
      payload: payload,
    );
  }

  Future<WindowsControlResult> getOpenItemsReport() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'

# 1. Open Explorer Folders & Windows
$shell = New-Object -ComObject Shell.Application
$folders = @()
foreach ($w in $shell.Windows()) {
  try {
    if ($w.FullName -like '*explorer.exe' -and $w.LocationURL -like 'file:*') {
      $path = [System.Uri]::UnescapeDataString($w.LocationURL.Substring(8).Replace('/', '\'))
      $folders += [PSCustomObject]@{
        Hwnd = $w.HWND
        Name = $w.LocationName
        Path = $path
      }
    }
  } catch {}
}

# 2. Browser Tabs & Windows
$browserTabs = @()
$browsers = Get-Process -Name chrome, msedge, firefox, brave, opera, vivaldi -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowTitle } |
  Select-Object Id, ProcessName, MainWindowTitle

foreach ($b in $browsers) {
  $browserTabs += [PSCustomObject]@{
    Id = $b.Id
    Browser = $b.ProcessName
    Title = $b.MainWindowTitle
  }
}

# 3. Open Documents & Files
$docs = @()
$officeProcs = Get-Process -Name WINWORD, EXCEL, POWERPNT, notepad, Code, Acrobat, AcroRd32, FoxitPDFReader -ErrorAction SilentlyContinue |
  Where-Object { $_.MainWindowTitle } |
  Select-Object Id, ProcessName, MainWindowTitle

foreach ($o in $officeProcs) {
  $docs += [PSCustomObject]@{
    Id = $o.Id
    App = $o.ProcessName
    Title = $o.MainWindowTitle
  }
}

# 4. Other visible windows
$apps = Get-Process |
  Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -and $_.ProcessName -notmatch 'explorer|chrome|msedge|firefox|brave|notepad|Code|WINWORD|EXCEL|POWERPNT' } |
  Select-Object -First 15 |
  ForEach-Object {
    [PSCustomObject]@{
      Id = $_.Id
      ProcessName = $_.ProcessName
      Title = $_.MainWindowTitle
    }
  }

[PSCustomObject]@{
  Folders = $folders
  BrowserTabs = $browserTabs
  Documents = $docs
  Apps = $apps
} | ConvertTo-Json -Compress -Depth 4
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 10));
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
      message: result.exitCode == 0 ? 'تم جلب تقرير الملفات والمواقع المفتوحة' : 'تعذر جلب التقرير',
      payload: payload,
    );
  }

  Future<WindowsControlResult> getRunningProcesses() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Get-Process |
  Where-Object { $_.MainWindowTitle -or $_.WorkingSet64 -gt 40MB } |
  Sort-Object -Property WorkingSet64 -Descending |
  Select-Object -First 25 |
  ForEach-Object {
    [PSCustomObject]@{
      Id = $_.Id
      ProcessName = $_.ProcessName
      Title = $_.MainWindowTitle
      MemoryMB = [math]::Round($_.WorkingSet64 / 1MB, 1)
      Responding = $_.Responding
    }
  } | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 10));
    final payload = _payload(result);
    final stdout = result.stdout.toString().trim();
    if (stdout.startsWith('[')) {
      try {
        final decoded = jsonDecode(stdout);
        if (decoded is List) payload['processes'] = decoded;
      } catch (_) {}
    }
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم جلب قائمة العمليات النشطة' : 'تعذر جلب قائمة العمليات',
      payload: payload,
    );
  }

  Future<WindowsControlResult> uploadFileToRemoteUrl(String localPath, String uploadUrl) async {
    final cleanPath = localPath.trim();
    final cleanUrl = uploadUrl.trim();
    final file = File(cleanPath);
    if (!await file.exists()) {
      return WindowsControlResult(
        success: false,
        message: 'الملف غير موجود في المسار المحدد: $cleanPath',
      );
    }
    final script = '''
\$ErrorActionPreference = 'Stop'
\$filePath = "$cleanPath"
\$url = "$cleanUrl"
\$fileName = [System.IO.Path]::GetFileName(\$filePath)

\$boundary = [System.Guid]::NewGuid().ToString()
\$LF = "`r`n"
\$fileBytes = [System.IO.File]::ReadAllBytes(\$filePath)

\$body = (
    "--\$boundary" + \$LF +
    "Content-Disposition: form-data; name=`"file`"; filename=`"\$fileName`"" + \$LF +
    "Content-Type: application/octet-stream" + \$LF + \$LF +
    [System.Text.Encoding]::GetEncoding("iso-8859-1").GetString(\$fileBytes) + \$LF +
    "--\$boundary--" + \$LF
)

\$response = Invoke-RestMethod -Uri \$url -Method Post -ContentType "multipart/form-data; boundary=\$boundary" -Body \$body -TimeoutSec 60
[PSCustomObject]@{
    Success = \$true
    FileName = \$fileName
    Size = \$fileBytes.Length
} | ConvertTo-Json -Compress
''';
    final result = await SafeProcessRunner.powershell(script, timeout: const Duration(minutes: 3));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تم رفع الملف بنجاح إلى السحابة' : 'فشل رفع الملف إلى السحابة: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> syncFileToOneDrive(String localPath) async {
    final cleanPath = localPath.trim();
    final file = File(cleanPath);
    if (!await file.exists() && !await Directory(cleanPath).exists()) {
      return WindowsControlResult(
        success: false,
        message: 'المسار غير موجود: $cleanPath',
      );
    }
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$oneDrivePath = [System.Environment]::GetEnvironmentVariable('OneDrive')
if ([string]::IsNullOrEmpty(\$oneDrivePath)) {
    \$oneDrivePath = [System.Environment]::GetEnvironmentVariable('OneDriveConsumer')
}
if ([string]::IsNullOrEmpty(\$oneDrivePath)) {
    \$oneDrivePath = [System.IO.Path]::Combine(\$env:USERPROFILE, "OneDrive")
}
if (-not (Test-Path \$oneDrivePath)) {
    throw "مجلد OneDrive غير مفعل على هذا الكمبيوتر"
}
\$kiomCloudDir = [System.IO.Path]::Combine(\$oneDrivePath, "KIOM_Cloud_Sync")
if (-not (Test-Path \$kiomCloudDir)) { New-Item -ItemType Directory -Path \$kiomCloudDir -Force | Out-Null }
Copy-Item -Path "$cleanPath" -Destination \$kiomCloudDir -Recurse -Force
[PSCustomObject]@{
    SyncedDir = \$kiomCloudDir
    Success = \$true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 30));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تمت مزامنة الملف فوراً إلى مجلد OneDrive السحابي' : 'تعذر المزامنة إلى OneDrive: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<WindowsControlResult> syncFileToGoogleDrive(String localPath) async {
    final cleanPath = localPath.trim();
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$gdriveLetters = Get-PSDrive -PSProvider FileSystem | Where-Object { \$_.DisplayRoot -like '*Google Drive*' -or (Test-Path (Join-Path \$_.Root 'My Drive')) }
\$gdrivePath = ""
if (\$gdriveLetters) {
    \$gdrivePath = Join-Path (\$gdriveLetters[0].Root) "My Drive"
}
if ([string]::IsNullOrEmpty(\$gdrivePath)) {
    \$defaultG = "G:\\My Drive"
    if (Test-Path \$defaultG) { \$gdrivePath = \$defaultG }
}
if ([string]::IsNullOrEmpty(\$gdrivePath)) {
    throw "لم يتم العثور على تطبيق Google Drive للكمبيوتر مثبت ومسجل دخول"
}
\$kiomCloudDir = [System.IO.Path]::Combine(\$gdrivePath, "KIOM_Cloud_Sync")
if (-not (Test-Path \$kiomCloudDir)) { New-Item -ItemType Directory -Path \$kiomCloudDir -Force | Out-Null }
Copy-Item -Path "$cleanPath" -Destination \$kiomCloudDir -Recurse -Force
[PSCustomObject]@{
    SyncedDir = \$kiomCloudDir
    Success = \$true
} | ConvertTo-Json -Compress
''';
    final result = await _runPowerShell(script, timeout: const Duration(seconds: 30));
    return WindowsControlResult(
      success: result.exitCode == 0,
      message: result.exitCode == 0 ? 'تمت مزامنة الملف فوراً إلى Google Drive السحابي' : 'تعذر المزامنة إلى Google Drive: ${_clean(result)}',
      payload: _payload(result),
    );
  }

  Future<ProcessResult> _runPowerShell(String script, {Duration timeout = const Duration(seconds: 15)}) {
    return SafeProcessRunner.powershell(script, timeout: timeout);
  }

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
      message: result.exitCode == 0 ? successMessage : '$failureMessage: ${_clean(result)}',
      payload: payload,
    );
  }

  Map<String, dynamic> _payload(ProcessResult result) => {
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString().trim(),
        'stderr': result.stderr.toString().trim(),
      };

  String _clean(ProcessResult result) {
    final text = [
      result.stdout.toString().trim(),
      result.stderr.toString().trim(),
    ].where((e) => e.isNotEmpty).join(' | ');
    return text.isEmpty ? 'رمز الخروج ${result.exitCode}' : text;
  }
}
