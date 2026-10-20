import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../services/local_lan_server_service.dart';
import '../services/telegram_notifier_service.dart';
import '../utils/json_file_store.dart';

class ClipboardMonitorService {
  ClipboardMonitorService({
    required this.store,
    this.telegram,
    this.lanServer,
    this.checkInterval = const Duration(milliseconds: 900),
  });

  final JsonFileStore store;
  final TelegramNotifierService? telegram;
  final LocalLanServerService? lanServer;
  final Duration checkInterval;

  Timer? _timer;
  bool _running = false;
  String _lastContentHash = '';

  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(checkInterval, (_) => _checkClipboard());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkClipboard() async {
    if (!Platform.isWindows) return;
    try {
      final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms

$hasText = [System.Windows.Forms.Clipboard]::ContainsText()
$hasFile = [System.Windows.Forms.Clipboard]::ContainsFileDropList()
$hasImage = [System.Windows.Forms.Clipboard]::ContainsImage()

if (-not $hasText -and -not $hasFile -and -not $hasImage) {
  exit 0
}

$type = 'text'
$content = ''
$files = @()

if ($hasFile) {
  $type = 'files'
  $fileList = [System.Windows.Forms.Clipboard]::GetFileDropList()
  $files = @($fileList)
  $content = ($files -join "`n")
} elseif ($hasText) {
  $type = 'text'
  $content = [System.Windows.Forms.Clipboard]::GetText()
} elseif ($hasImage) {
  $type = 'image'
  $content = '[صورة في الحافظة]'
}

if ([string]::IsNullOrWhiteSpace($content)) {
  exit 0
}

# Inspect Active Foreground Window & Source App
$code = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public class WinTracker {
    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
'@
Add-Type -TypeDefinition $code -ErrorAction SilentlyContinue

$hwnd = [WinTracker]::GetForegroundWindow()
$titleBuf = New-Object System.Text.StringBuilder 1024
[WinTracker]::GetWindowText($hwnd, $titleBuf, 1024) | Out-Null
$title = $titleBuf.ToString()

$procId = 0
[WinTracker]::GetWindowThreadProcessId($hwnd, [ref]$procId) | Out-Null

$procName = ''
$procPath = ''
$sourceAppName = ''

if ($procId -gt 0) {
  $proc = Get-Process -Id $procId -ErrorAction SilentlyContinue
  if ($proc) {
    $procName = $proc.ProcessName + ".exe"
    $procPath = $proc.Path
    $sourceAppName = $proc.Description
    if ([string]::IsNullOrWhiteSpace($sourceAppName)) { $sourceAppName = $proc.ProcessName }
  }
}

# Source Path detection
$sourcePath = $procPath
if ($type -eq 'files' -and $files.Count -gt 0) {
  $sourcePath = $files[0]
}

[PSCustomObject]@{
  Type = $type
  Content = $content
  CharCount = $content.Length
  SourceApp = $procName
  SourceAppName = $sourceAppName
  SourceTitle = $title
  SourcePath = $sourcePath
} | ConvertTo-Json -Compress
''';

      final result = await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', script],
        runInShell: false,
      );

      if (result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty) {
        final out = result.stdout.toString().trim();
        final map = (jsonDecode(out) as Map).cast<String, dynamic>();

        final content = (map['Content'] ?? '').toString();
        final type = (map['Type'] ?? 'text').toString();
        final sourceApp = (map['SourceApp'] ?? '').toString();
        final sourceAppName = (map['SourceAppName'] ?? '').toString();
        final sourceTitle = (map['SourceTitle'] ?? '').toString();
        final sourcePath = (map['SourcePath'] ?? '').toString();

        if (content.isEmpty) return;

        // Hash check to avoid duplicate recordings of the same copy
        final currentHash = '$type:${content.hashCode}:${sourceApp.hashCode}';
        if (currentHash == _lastContentHash) return;
        _lastContentHash = currentHash;

        final itemId = 'clip_${DateTime.now().millisecondsSinceEpoch}';

        await store.appendClipboardEntry(
          itemId: itemId,
          type: type,
          content: content,
          charCount: content.length,
          sourceApp: sourceApp,
          sourceAppName: sourceAppName,
          sourceTitle: sourceTitle,
          sourcePath: sourcePath,
        );

        await store.appendLog(
          'clipboard_copy',
          'تم نسخ محتوى جديد من $sourceAppName ($sourceApp)',
          {
            'itemId': itemId,
            'type': type,
            'sourceApp': sourceApp,
            'sourceTitle': sourceTitle,
            'sourcePath': sourcePath,
            'length': content.length,
            'preview': content.length > 80 ? '${content.substring(0, 80)}...' : content,
          },
        );
      }
    } catch (_) {}
  }
}
