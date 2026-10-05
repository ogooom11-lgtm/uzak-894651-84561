import 'dart:convert';
import '../models/open_app_info.dart';
import '../utils/process_runner.dart';

class ProcessMonitorService {
  Future<List<OpenAppInfo>> getOpenApps() async {
    final script = r'''
$ErrorActionPreference = 'SilentlyContinue'
$items = Get-Process | Where-Object { $_.MainWindowTitle -ne $null -and $_.MainWindowTitle.Trim() -ne '' } | ForEach-Object {
  [PSCustomObject]@{
    Id = $_.Id
    ProcessName = $_.ProcessName
    Path = $_.Path
    StartTime = if ($_.StartTime) { $_.StartTime.ToString('o') } else { '' }
    MainWindowTitle = $_.MainWindowTitle
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
}
