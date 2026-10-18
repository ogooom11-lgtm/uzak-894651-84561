import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../models/open_app_info.dart';
import '../utils/json_file_store.dart';
import '../utils/process_runner.dart';
import 'process_monitor_service.dart';
import 'telegram_notifier_service.dart';

class ApplicationBlockerService {
  ApplicationBlockerService({
    required this.store,
    ProcessMonitorService? monitor,
    this.telegram,
  }) : monitor = monitor ?? ProcessMonitorService();

  final JsonFileStore store;
  final ProcessMonitorService monitor;
  final TelegramNotifierService? telegram;

  Timer? _timer;
  bool _tickInProgress = false;
  final Map<int, DateTime> _recentKillAttempts = {};
  String? _lastHostsFingerprint;
  String? _lastFailedHostsFingerprint;
  DateTime? _lastHostsWriteFailureAt;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick();
  }

  void stop() => _timer?.cancel();

  Future<void> _tick() async {
    if (_tickInProgress) return;
    _tickInProgress = true;
    try {
      await enforceBlockedApps();
      await enforceBlockedSites();
      await _rewriteHostsFile();
    } finally {
      _tickInProgress = false;
    }
  }

  Future<void> enforceBlockedSites() async {
    final sites = blockedSites().where((s) => !_isTemporarilyAllowed(s)).toList();
    if (sites.isEmpty) return;

    final keywords = <String>{};
    for (final s in sites) {
      final domain = (s['domain'] ?? '').toString();
      final brand = _extractBrandName(domain);
      if (brand.isNotEmpty && brand.length >= 2) {
        keywords.add(brand.toLowerCase());
      }
      final clean = _normalizeDomain(domain);
      if (clean.isNotEmpty) {
        keywords.add(clean.toLowerCase());
      }
    }

    if (keywords.isEmpty) return;

    final keywordList = keywords.map((k) => "'$k'").join(',');
    final script = '''
\$ErrorActionPreference = 'SilentlyContinue'
\$keywords = @($keywordList)

\$code = @"
using System;
using System.Runtime.InteropServices;

public class KiomTabCloser {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, int dwExtraInfo);

    public static void CloseTab(IntPtr hWnd) {
        try {
            SetForegroundWindow(hWnd);
            System.Threading.Thread.Sleep(50);
            keybd_event(0x11, 0, 0, 0);
            keybd_event(0x57, 0, 0, 0);
            keybd_event(0x57, 0, 2, 0);
            keybd_event(0x11, 0, 2, 0);
        } catch {}
    }
}
"@
if (-not ('KiomTabCloser' -as [type])) {
    Add-Type -TypeDefinition \$code
}

\$browsers = Get-Process -Name chrome, msedge, firefox, brave, opera, vivaldi -ErrorAction SilentlyContinue |
  Where-Object { \$_.MainWindowTitle }

foreach (\$b in \$browsers) {
  \$title = \$b.MainWindowTitle.ToLower()
  foreach (\$k in \$keywords) {
    if (\$title -like "*\$k*") {
      [KiomTabCloser]::CloseTab(\$b.MainWindowHandle)
      Start-Sleep -Milliseconds 100
      break
    }
  }
}
''';
    try {
      await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 4));
    } catch (_) {}
  }

  List<Map<String, dynamic>> blockedApps() {
    return store
        .list('blockedApps')
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => (item['target'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> blockedSites() {
    return store
        .list('blockedSites')
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) => (item['domain'] ?? '').toString().trim().isNotEmpty)
        .toList();
  }

  List<Map<String, dynamic>> cloudItems() {
    return [
      for (final item in blockedApps())
        {
          'id': _safeId('app_${item['target']}'),
          'type': 'app',
          'target': item['target'],
          'label': item['appName'] ?? item['target'],
          'appPath': item['appPath'] ?? '',
          'allowedUntil': item['allowedUntil'],
          'createdAt': item['createdAt'] ?? DateTime.now().toIso8601String(),
        },
      for (final item in blockedSites())
        {
          'id': _safeId('site_${item['domain']}'),
          'type': 'site',
          'target': item['domain'],
          'label': item['domain'],
          'lockType': item['lockType'] ?? 'blocked',
          'allowedUntil': item['allowedUntil'],
          'createdAt': item['createdAt'] ?? DateTime.now().toIso8601String(),
        },
    ];
  }

  Future<void> blockApp({
    required String target,
    String? appName,
    String? appPath,
  }) async {
    final normalized = _normalizeTarget(target);
    final blocked = blockedApps()
      ..removeWhere((item) => _isSameAppRule(item, normalized, appPath));
    blocked.add({
      'target': normalized,
      'appName': appName ?? target,
      'appPath': appPath ?? '',
      'allowedUntil': null,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.set('blockedApps', blocked);
    await store.appendLog('app_blocked', 'تم منع تطبيق من العمل', {
      'target': normalized,
      'appName': appName,
      'appPath': appPath,
    });
    await enforceBlockedApps();
  }

  Future<void> allowApp(String target, {Duration? duration}) async {
    final normalized = _normalizeTarget(target);
    final blocked = blockedApps();
    if (duration == null) {
      blocked.removeWhere((item) => _isSameAppRule(item, normalized, null));
    } else {
      final until = DateTime.now().add(duration).toIso8601String();
      for (final item in blocked) {
        if (_isSameAppRule(item, normalized, null)) {
          item['allowedUntil'] = until;
        }
      }
    }
    await store.set('blockedApps', blocked);
    await store.appendLog(
      duration == null ? 'app_allowed' : 'app_allowed_temporarily',
      duration == null
          ? 'تم إلغاء منع تطبيق بنجاح'
          : 'تم السماح المؤقت لتطبيق ممنوع',
      {
        'target': normalized,
        'durationSeconds': duration?.inSeconds,
      },
    );
  }

  Future<void> blockSite(
    String domain, {
    String lockType = 'blocked',
    String? password,
    String? passwordHash,
  }) async {
    final normalized = _normalizeDomain(domain);
    if (normalized.isEmpty) throw StateError('domain غير صالح');
    final effectivePasswordHash =
        passwordHash?.trim().isNotEmpty == true ? passwordHash!.trim() : null;
    final blocked = blockedSites()
      ..removeWhere((item) => item['domain'] == normalized);
    blocked.add({
      'domain': normalized,
      'lockType': lockType,
      if (effectivePasswordHash != null)
        'passwordHash': effectivePasswordHash
      else if (password != null && password.isNotEmpty)
        'passwordHash': sha256.convert(utf8.encode(password)).toString(),
      'allowedUntil': null,
      'createdAt': DateTime.now().toIso8601String(),
    });
    await store.set('blockedSites', blocked);
    _lastHostsFingerprint = null; // force rewrite
    await _rewriteHostsFile();
    await _enforceFirewallRule(normalized, block: true);
    await store.appendLog('site_blocked', 'تم حظر موقع بنجاح', {
      'domain': normalized,
      'lockType': lockType,
    });
  }

  Future<void> allowSite(String domain, {Duration? duration}) async {
    final normalized = _normalizeDomain(domain);
    if (normalized.isEmpty) throw StateError('domain غير صالح');
    final brand = _extractBrandName(normalized);
    final blocked = blockedSites();
    if (duration == null) {
      blocked.removeWhere((item) {
        final d = item['domain'].toString();
        return d == normalized || (brand.isNotEmpty && _extractBrandName(d) == brand);
      });
    } else {
      final until = DateTime.now().add(duration).toIso8601String();
      for (final item in blocked) {
        final d = item['domain'].toString();
        if (d == normalized || (brand.isNotEmpty && _extractBrandName(d) == brand)) {
          item['allowedUntil'] = until;
        }
      }
    }
    await store.set('blockedSites', blocked);
    _lastHostsFingerprint = null; // force rewrite
    await _rewriteHostsFile();
    if (duration == null) {
      await _enforceFirewallRule(normalized, block: false);
    }
    await store.appendLog(
        duration == null ? 'site_allowed' : 'site_allowed_temporarily',
        duration == null
            ? 'تم إلغاء حظر الموقع بنجاح'
            : 'تم السماح المؤقت لموقع محظور',
        {
          'domain': normalized,
          'durationSeconds': duration?.inSeconds,
        });
  }

  Future<void> _enforceFirewallRule(String domain, {required bool block}) async {
    final clean = _normalizeDomain(domain);
    if (clean.isEmpty) return;
    final brand = _extractBrandName(clean);
    final ruleName = 'KIOM_BLOCK_SITE_${brand.isNotEmpty ? brand : clean.replaceAll('.', '_')}';
    final script = block
        ? '''
\$ErrorActionPreference = 'SilentlyContinue'
# Disable DoH in Registry so browsers strictly obey hosts sinkhole
New-Item -Path "HKLM:\\SOFTWARE\\Policies\\Google\\Chrome" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKLM:\\SOFTWARE\\Policies\\Google\\Chrome" -Name "DnsOverHttpsMode" -Value "off" -ErrorAction SilentlyContinue
New-Item -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge" -Force -ErrorAction SilentlyContinue | Out-Null
Set-ItemProperty -Path "HKLM:\\SOFTWARE\\Policies\\Microsoft\\Edge" -Name "DnsOverHttpsMode" -Value "off" -ErrorAction SilentlyContinue

# Flush DNS
ipconfig /flushdns | Out-Null
'''
        : '''
\$ErrorActionPreference = 'SilentlyContinue'
# Remove any outbound firewall rules for this domain
netsh advfirewall firewall delete rule name="$ruleName" 2>&1 | Out-Null
ipconfig /flushdns | Out-Null
''';
    try {
      await SafeProcessRunner.powershell(script, timeout: const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> enforceBlockedApps() async {
    final rules = blockedApps();
    if (rules.isEmpty) return;

    final apps = await monitor.getOpenApps();
    for (final app in apps) {
      final rule = _matchingRule(app, rules);
      if (rule == null) continue;
      if (_isTemporarilyAllowed(rule)) continue;
      if (_recentlyTried(app.processId)) continue;

      final result = await SafeProcessRunner.run(
        'taskkill.exe',
        ['/PID', app.processId.toString(), '/F'],
        timeout: SafeProcessRunner.shortTimeout,
      );
      await store.appendLog(
        result.exitCode == 0 ? 'blocked_app_closed' : 'blocked_app_close_error',
        result.exitCode == 0
            ? 'تم إغلاق تطبيق ممنوع تلقائياً'
            : 'تعذر إغلاق تطبيق ممنوع',
        {
          'processId': app.processId,
          'appName': app.appName,
          'appPath': app.appPath,
          'title': app.title,
          'rule': rule,
          'exitCode': result.exitCode,
          'stdout': result.stdout.toString(),
          'stderr': result.stderr.toString(),
        },
      );
      if (result.exitCode == 0) {
        await telegram?.sendMessage(
          'KIOM: تم إغلاق تطبيق ممنوع\n'
          'التطبيق: ${app.appName}\n'
          'العنوان: ${app.title}\n'
          'الجهاز: ${Platform.localHostname}',
        );
      }
    }
  }

  bool _isTemporarilyAllowed(Map<String, dynamic> rule) {
    final until = DateTime.tryParse((rule['allowedUntil'] ?? '').toString());
    return until != null && until.isAfter(DateTime.now());
  }

  Map<String, dynamic>? _matchingRule(
    OpenAppInfo app,
    List<Map<String, dynamic>> rules,
  ) {
    final appName = _normalizeTarget(app.appName);
    final processName = _normalizeTarget(app.appName.replaceAll('.exe', ''));
    final appPath = app.appPath.toLowerCase();

    for (final rule in rules) {
      final target = _normalizeTarget(rule['target'].toString());
      final rulePath = (rule['appPath'] ?? '').toString().toLowerCase();
      final targetBase = target.replaceAll('.exe', '');
      final appBase = appName.replaceAll('.exe', '');
      if (target == appName || target == processName) {
        return rule;
      }
      if (targetBase.contains(appBase) || appBase.contains(targetBase)) {
        return rule;
      }
      if (rulePath.isNotEmpty &&
          (appPath == rulePath || appPath.startsWith(rulePath))) {
        return rule;
      }
      if (appPath.isNotEmpty && appPath.endsWith('\\$target')) return rule;
      if (appPath.isNotEmpty && appPath.endsWith('\\$target.exe')) return rule;
    }
    return null;
  }

  bool _recentlyTried(int processId) {
    final now = DateTime.now();
    _recentKillAttempts.removeWhere(
      (_, at) => now.difference(at).inSeconds > 30,
    );
    final last = _recentKillAttempts[processId];
    _recentKillAttempts[processId] = now;
    return last != null && now.difference(last).inSeconds < 3;
  }

  bool _isSameAppRule(
    Map<String, dynamic> item,
    String normalizedTarget,
    String? appPath,
  ) {
    final target = _normalizeTarget(item['target'].toString());
    final targetBase = target.replaceAll('.exe', '');
    final requestedBase = normalizedTarget.replaceAll('.exe', '');
    if (target == normalizedTarget ||
        targetBase.contains(requestedBase) ||
        requestedBase.contains(targetBase)) {
      return true;
    }

    final rulePath = (item['appPath'] ?? '').toString().toLowerCase();
    final requestedPath = (appPath ?? '').toLowerCase();
    return rulePath.isNotEmpty &&
        requestedPath.isNotEmpty &&
        (rulePath == requestedPath ||
            rulePath.startsWith(requestedPath) ||
            requestedPath.startsWith(rulePath));
  }

  String _normalizeTarget(String value) {
    var text = value.trim().toLowerCase().replaceAll('/', r'\');
    if (text.contains(r'\')) {
      text = text.split(r'\').last;
    }
    if (!text.endsWith('.exe')) {
      text = '$text.exe';
    }
    return text;
  }

  String _normalizeDomain(String value) {
    var text = value.trim().toLowerCase();
    final mdMatch = RegExp(r'\[([^\]]+)\]\([^)]+\)').firstMatch(text);
    if (mdMatch != null) {
      text = mdMatch.group(1) ?? text;
    }
    text = text.replaceAll(RegExp(r'''[\[\]()<>"'`]'''), '').trim();
    if (text.startsWith('http://') || text.startsWith('https://')) {
      text = Uri.tryParse(text)?.host ?? text;
    }
    text = text.replaceAll(RegExp(r'^www\.'), '');
    text = text.split('/').first;
    text = text.split(':').first;
    text = text.split('?').first;
    return text.trim();
  }

  String _extractBrandName(String value) {
    var text = _normalizeDomain(value);
    if (text.isEmpty) return '';

    const compoundTlds = [
      '.com.tr', '.co.tr', '.net.tr', '.org.tr', '.gov.tr', '.edu.tr',
      '.co.uk', '.org.uk', '.me.uk', '.net.uk', '.ltd.uk', '.plc.uk',
      '.com.sa', '.net.sa', '.org.sa', '.edu.sa', '.gov.sa',
      '.com.eg', '.net.eg', '.org.eg', '.edu.eg', '.gov.eg',
      '.com.ae', '.net.ae', '.org.ae', '.gov.ae',
      '.com.qa', '.net.qa', '.org.qa', '.gov.qa',
      '.com.kw', '.net.kw', '.org.kw', '.gov.kw',
      '.com.om', '.net.om', '.org.om', '.gov.om',
      '.com.bh', '.net.bh', '.org.bh', '.gov.bh',
      '.com.jo', '.net.jo', '.org.jo', '.gov.jo',
      '.com.lb', '.net.lb', '.org.lb', '.gov.lb',
      '.com.iq', '.net.iq', '.org.iq', '.gov.iq',
      '.com.ye', '.net.ye', '.org.ye', '.gov.ye',
      '.com.ru', '.net.ru', '.org.ru', '.pp.ru',
      '.com.au', '.net.au', '.org.au', '.edu.au',
      '.co.nz', '.net.nz', '.org.nz',
      '.co.in', '.net.in', '.org.in', '.gen.in',
      '.com.br', '.net.br', '.org.br',
      '.com.mx', '.net.mx', '.org.mx',
      '.com.ar', '.net.ar', '.org.ar',
      '.co.za', '.net.za', '.org.za',
      '.com.ng', '.net.ng', '.org.ng',
      '.co.id', '.net.id', '.or.id',
      '.com.ph', '.net.ph', '.org.ph',
      '.com.my', '.net.my', '.org.my',
      '.com.sg', '.net.sg', '.org.sg',
      '.co.th', '.net.th', '.or.th',
      '.com.vn', '.net.vn', '.org.vn',
      '.co.jp', '.ne.jp', '.or.jp',
      '.co.kr', '.ne.kr', '.or.kr',
      '.com.tw', '.net.tw', '.org.tw',
      '.com.hk', '.net.hk', '.org.hk',
      '.com.cn', '.net.cn', '.org.cn',
      '.com.ge', '.com.am', '.com.ua', '.net.ua', '.org.ua',
      '.co.il', '.org.il', '.net.il',
    ];

    for (final ctld in compoundTlds) {
      if (text.endsWith(ctld)) {
        text = text.substring(0, text.length - ctld.length);
        break;
      }
    }

    final parts = text.split('.');
    if (parts.length > 1) {
      parts.removeLast();
      text = parts.join('.');
    }

    final subParts = text.split('.');
    return subParts.last.trim();
  }

  Set<String> _expandDomainVariants(String rawDomain) {
    final clean = _normalizeDomain(rawDomain);
    if (clean.isEmpty) return const {};

    final brand = _extractBrandName(clean);
    final results = <String>{clean, 'www.$clean', 'm.$clean'};

    if (brand.isNotEmpty && brand.length >= 2) {
      const allTlds = [
        '.com', '.com.tr', '.tr', '.ru', '.by', '.kz', '.uz', '.ua', '.az',
        '.net', '.org', '.info', '.biz', '.co', '.io', '.app', '.ai', '.me',
        '.tv', '.cc', '.site', '.online', '.store', '.club', '.top', '.xyz',
        '.dev', '.tech', '.eu', '.fr', '.de', '.es', '.it', '.nl', '.be',
        '.ch', '.at', '.se', '.no', '.dk', '.fi', '.pt', '.ie', '.pl',
        '.ro', '.hu', '.cz', '.gr', '.bg', '.rs', '.ee', '.lt', '.lv',
        '.com.sa', '.sa', '.com.eg', '.eg', '.ae', '.com.ae', '.qa',
        '.com.qa', '.kw', '.com.kw', '.om', '.com.om', '.bh', '.com.bh',
        '.jo', '.com.jo', '.lb', '.com.lb', '.iq', '.com.iq', '.ye',
        '.com.ye', '.dz', '.tn', '.ma', '.ly', '.sd', '.co.uk', '.uk',
        '.com.au', '.au', '.co.nz', '.nz', '.ca', '.in', '.co.in',
        '.com.br', '.br', '.com.mx', '.mx', '.com.ar', '.co.za', '.za',
        '.com.ng', '.co.id', '.com.ph', '.com.my', '.com.sg', '.co.th',
        '.com.vn', '.co.jp', '.jp', '.co.kr', '.kr', '.com.tw', '.com.hk',
        '.com.cn', '.cn', '.com.ge', '.com.am', '.co.il',
      ];

      for (final tld in allTlds) {
        final d = '$brand$tld';
        results.add(d);
        results.add('www.$d');
        results.add('m.$d');
        results.add('mobile.$d');
        results.add('mail.$d');
        results.add('disk.$d');
        results.add('music.$d');
        results.add('video.$d');
        results.add('maps.$d');
        results.add('news.$d');
        results.add('translate.$d');
        results.add('direct.$d');
        results.add('passport.$d');
        results.add('login.$d');
        results.add('auth.$d');
        results.add('api.$d');
        results.add('cdn.$d');
        results.add('app.$d');
        results.add('web.$d');
      }

      // Brand-specific Ecosystem Clusters
      if (brand == 'yandex' || brand == 'ya') {
        const yandexAliases = [
          'ya.ru', 'www.ya.ru', 'm.ya.ru', 'yastatic.net', 'dzen.ru',
          'zen.yandex.ru', 'kinopoisk.ru', 'auto.ru', 'clck.ru', 'turbopages.org',
          'yabs.yandex.ru', 'an.yandex.ru', 'mc.yandex.ru', 'adfox.ru',
          'yandexcloud.net', 'eda.yandex.ru', 'market.yandex.ru', 'yango.com',
          'yango.tech', 'music.yandex.ru', 'disk.yandex.ru', 'mail.yandex.ru',
          'yandex.com.tr', 'www.yandex.com.tr', 'm.yandex.com.tr',
        ];
        results.addAll(yandexAliases);
      } else if (brand == 'youtube' || brand == 'youtu') {
        const ytAliases = [
          'youtube.com', 'youtu.be', 'youtube-nocookie.com', 'ytimg.com',
          'googlevideo.com', 'youtubei.googleapis.com', 'yt.be',
          'music.youtube.com', 'gaming.youtube.com', 'studio.youtube.com',
        ];
        results.addAll(ytAliases);
      } else if (brand == 'google') {
        const gAliases = [
          'googlevideo.com', 'googleusercontent.com', 'gstatic.com',
          'googleapis.com', 'google-analytics.com', 'googletagmanager.com',
          'g.co', 'goo.gl', '1e100.net',
        ];
        results.addAll(gAliases);
      } else if (brand == 'facebook' || brand == 'fb') {
        const fbAliases = [
          'facebook.com', 'fb.com', 'fbcdn.net', 'fbsbx.com', 'messenger.com',
          'meta.com', 'facebook.net', 'threads.net',
        ];
        results.addAll(fbAliases);
      } else if (brand == 'instagram') {
        const igAliases = [
          'instagram.com', 'cdninstagram.com', 'ig.me', 'instagr.am',
        ];
        results.addAll(igAliases);
      } else if (brand == 'tiktok') {
        const ttAliases = [
          'tiktok.com', 'tiktokcdn.com', 'tiktokv.com', 'musical.ly',
          'byteoversea.com', 'ibytedtos.com',
        ];
        results.addAll(ttAliases);
      } else if (brand == 'twitter' || brand == 'x') {
        const twAliases = [
          'twitter.com', 'x.com', 'twimg.com', 't.co', 'tweetdeck.com',
          'periscope.tv', 'x.ai',
        ];
        results.addAll(twAliases);
      } else if (brand == 'reddit') {
        const rdAliases = [
          'reddit.com', 'redd.it', 'redditmedia.com', 'redditstatic.com',
        ];
        results.addAll(rdAliases);
      } else if (brand == 'telegram') {
        const tgAliases = [
          'telegram.org', 'web.telegram.org', 't.me', 'telesco.pe', 'telegram.me',
        ];
        results.addAll(tgAliases);
      } else if (brand == 'whatsapp') {
        const waAliases = [
          'whatsapp.com', 'web.whatsapp.com', 'whatsapp.net',
        ];
        results.addAll(waAliases);
      }
    }

    return results;
  }

  String _safeId(String value) {
    final safe = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_-]+'), '_');
    return safe.isEmpty
        ? 'item'
        : safe.substring(0, safe.length > 90 ? 90 : safe.length);
  }

  Future<void> _rewriteHostsFile() async {
    final hosts = File(r'C:\Windows\System32\drivers\etc\hosts');
    const start = '# KIOM_BLOCK_START';
    const end = '# KIOM_BLOCK_END';
    final activeDomains = blockedSites()
        .where((item) => !_isTemporarilyAllowed(item))
        .map((item) => item['domain'].toString())
        .where((domain) => domain.trim().isNotEmpty)
        .toSet();
    final fingerprint = (activeDomains.toList()..sort()).join('|');
    if (fingerprint == _lastHostsFingerprint) return;
    final lastFailureAt = _lastHostsWriteFailureAt;
    if (fingerprint == _lastFailedHostsFingerprint &&
        lastFailureAt != null &&
        DateTime.now().difference(lastFailureAt).inSeconds < 30) {
      return;
    }

    final hostEntries = <String>[];
    for (final domain in activeDomains) {
      final variants = _expandDomainVariants(domain);
      for (final v in variants) {
        hostEntries.add('0.0.0.0 $v');
        hostEntries.add('127.0.0.1 $v');
        hostEntries.add('::1 $v');
      }
    }

    final generated = activeDomains.isEmpty
        ? ''
        : <String>[
            start,
            ...hostEntries,
            end,
          ].join('\r\n');

    try {
      final original = await hosts.readAsString();
      final cleaned = original
          .replaceAll(
            RegExp('$start[\\s\\S]*?$end\\r?\\n?', multiLine: true),
            '',
          )
          .trimRight();
      final newContent = activeDomains.isEmpty ? cleaned : '$cleaned\r\n$generated\r\n';
      await hosts.writeAsString(newContent);
      await SafeProcessRunner.run(
        'ipconfig.exe',
        ['/flushdns'],
        timeout: SafeProcessRunner.shortTimeout,
      );
      _lastHostsFingerprint = fingerprint;
      _lastFailedHostsFingerprint = null;
      _lastHostsWriteFailureAt = null;
    } catch (e) {
      try {
        final psCommand = [
          "\$p = 'C:\\Windows\\System32\\drivers\\etc\\hosts'",
          "\$c = [System.IO.File]::ReadAllText(\$p)",
          "\$c = \$c -replace '(?s)# KIOM_BLOCK_START.*?# KIOM_BLOCK_END', ''",
          if (activeDomains.isNotEmpty) ...[
            "\$c = \$c.TrimEnd() + \"`r`n\" + @'",
            generated,
            "'@",
          ],
          "[System.IO.File]::WriteAllText(\$p, \$c.TrimEnd())",
          "ipconfig /flushdns"
        ].join("`n");
        await Process.run('powershell', ['-NoProfile', '-Command', psCommand]);
        _lastHostsFingerprint = fingerprint;
        _lastFailedHostsFingerprint = null;
        _lastHostsWriteFailureAt = null;
      } catch (_) {}
    }
  }
}
