import 'dart:convert';
import '../models/open_app_info.dart';
import '../utils/process_runner.dart';

class ProcessMonitorService {
  Future<List<OpenAppInfo>> getOpenApps() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$items = @()
Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | ForEach-Object {
  try {
    $t = ($_.MainWindowTitle).ToString().Trim()
    if ($t.Length -gt 0) {
      $p = ''
      try { $p = $_.Path } catch { $p = '' }
      $st = ''
      try { if ($_.StartTime) { $st = $_.StartTime.ToString('o') } } catch {}
      $items += [PSCustomObject]@{
        Id = $_.Id
        ProcessName = $_.ProcessName
        Path = $p
        StartTime = $st
        MainWindowTitle = $t
      }
    }
  } catch {}
}
if ($items.Count -eq 0) {
  Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
    $items += [PSCustomObject]@{
      Id = $_.Id
      ProcessName = $_.ProcessName
      Path = ''
      StartTime = ''
      MainWindowTitle = $_.ProcessName
    }
  }
}
$items | ConvertTo-Json -Compress -Depth 3
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(seconds: 8),
    );
    if (result.exitCode != 0) return [];
    final text = result.stdout.toString().trim();
    if (text.isEmpty) return [];
    final decoded = jsonDecode(text);
    final list = decoded is List ? decoded : [decoded];
    return list
        .whereType<Map>()
        .map((m) {
          final id = (m['Id'] as num?)?.toInt() ?? 0;
          final name = (m['ProcessName'] ?? 'unknown').toString();
          final path = (m['Path'] ?? '').toString();
          final start = DateTime.tryParse((m['StartTime'] ?? '').toString()) ??
              DateTime.now();
          final title = (m['MainWindowTitle'] ?? '').toString();
          final browserName = _browserName(name);
          final pageTitle =
              browserName == null ? null : _pageTitle(title, browserName);
          return OpenAppInfo(
            processId: id,
            appName: name.endsWith('.exe') ? name : '$name.exe',
            appPath: path,
            title: title,
            openedAt: start,
            iconKey: _guessIcon(name),
            browserName: browserName,
            pageTitle: pageTitle,
            siteName: _siteNameFromTitle(pageTitle),
          );
        })
        .where((app) => app.processId > 0)
        .toList();
  }

  String? _browserName(String processName) {
    final p = processName.toLowerCase();
    if (p.contains('chrome')) return 'Chrome';
    if (p.contains('msedge')) return 'Edge';
    if (p.contains('firefox')) return 'Firefox';
    if (p.contains('brave')) return 'Brave';
    if (p.contains('opera')) return 'Opera';
    if (p.contains('vivaldi')) return 'Vivaldi';
    return null;
  }

  String? _pageTitle(String title, String browserName) {
    var text = title.trim();
    if (text.isEmpty) return null;
    final suffixes = [
      ' - Google Chrome',
      ' - Microsoft Edge',
      ' - Mozilla Firefox',
      ' - Brave',
      ' - Opera',
      ' - Vivaldi',
      ' - $browserName',
    ];
    for (final suffix in suffixes) {
      if (text.toLowerCase().endsWith(suffix.toLowerCase())) {
        text = text.substring(0, text.length - suffix.length).trim();
      }
    }
    return text.isEmpty ? null : text;
  }

  String? _siteNameFromTitle(String? pageTitle) {
    final text = pageTitle?.trim();
    if (text == null || text.isEmpty) return null;
    final parts = text.split(RegExp(r'\s[-|]\s'));
    final candidate = parts.length > 1 ? parts.last.trim() : parts.first.trim();
    return candidate.isEmpty ? null : candidate;
  }

  String _guessIcon(String processName) {
    final p = processName.toLowerCase();
    if (p.contains('chrome')) return 'chrome';
    if (p.contains('msedge')) return 'edge';
    if (p.contains('firefox')) return 'firefox';
    if (p.contains('telegram')) return 'telegram';
    if (p.contains('whatsapp')) return 'whatsapp';
    if (p.contains('winword')) return 'word';
    if (p.contains('excel')) return 'excel';
    if (p.contains('powerpnt')) return 'powerpoint';
    if (p.contains('discord')) return 'discord';
    if (p.contains('steam')) return 'steam';
    return 'default';
  }

  Future<Map<String, dynamic>> getDetailedOpenItems() async {
    const script = r'''
$ErrorActionPreference = 'SilentlyContinue'

$openFolders = @()
try {
    $shell = New-Object -ComObject Shell.Application
    $windows = $shell.Windows()
    foreach ($win in $windows) {
        try {
            $name = $win.LocationName
            $url = $win.LocationURL
            if ($url -and $url.StartsWith("file:///")) {
                $path = [System.Uri]::UnescapeDataString($url.Substring(8).Replace('/', '\'))
                $openFolders += [PSCustomObject]@{
                    Name = if ($name) { $name } else { [System.IO.Path]::GetFileName($path) }
                    Path = $path
                    Type = 'folder'
                }
            }
        } catch {}
    }
} catch {}

$openWindows = @()
$browserTabs = @()
$openDocs = @()

Get-Process | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle } | ForEach-Object {
    try {
        $pName = $_.ProcessName
        $pId = $_.Id
        $t = ($_.MainWindowTitle).ToString().Trim()
        $path = ''
        try { $path = $_.Path } catch {}

        if ($t.Length -gt 0) {
            $lowP = $pName.ToLower()
            $isBrowser = $lowP -match "chrome|msedge|firefox|brave|opera|vivaldi|safari"
            $isDoc = $lowP -match "winword|excel|powerpnt|notepad|acrobat|acrord|pdf|code|devenv"

            if ($isBrowser) {
                $browserTabs += [PSCustomObject]@{
                    ProcessName = $pName
                    ProcessId = $pId
                    Title = $t
                    Browser = $pName
                    Type = 'website'
                }
            } elseif ($isDoc) {
                $openDocs += [PSCustomObject]@{
                    ProcessName = $pName
                    ProcessId = $pId
                    Title = $t
                    Path = $path
                    Type = 'document'
                }
            } else {
                $openWindows += [PSCustomObject]@{
                    ProcessName = $pName
                    ProcessId = $pId
                    Title = $t
                    Path = $path
                    Type = 'app'
                }
            }
        }
    } catch {}
}

[PSCustomObject]@{
    Folders = $openFolders
    BrowserTabs = $browserTabs
    Documents = $openDocs
    Apps = $openWindows
} | ConvertTo-Json -Compress -Depth 4
''';
    final result = await SafeProcessRunner.powershell(
      script,
      timeout: const Duration(seconds: 10),
    );
    if (result.exitCode != 0) {
      return {'folders': [], 'browserTabs': [], 'documents': [], 'apps': []};
    }
    final text = result.stdout.toString().trim();
    if (text.isEmpty) {
      return {'folders': [], 'browserTabs': [], 'documents': [], 'apps': []};
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return {
          'folders': _toList(decoded['Folders']),
          'browserTabs': _toList(decoded['BrowserTabs']),
          'documents': _toList(decoded['Documents']),
          'apps': _toList(decoded['Apps']),
        };
      }
    } catch (_) {}
    return {'folders': [], 'browserTabs': [], 'documents': [], 'apps': []};
  }

  List<Map<String, dynamic>> _toList(dynamic val) {
    if (val == null) return [];
    if (val is List) {
      return val
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();
    }
    if (val is Map) return [val.cast<String, dynamic>()];
    return [];
  }
}
