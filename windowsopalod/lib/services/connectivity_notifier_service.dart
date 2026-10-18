import 'dart:async';
import 'dart:io';

import '../utils/json_file_store.dart';
import 'telegram_notifier_service.dart';
import 'windows_control_service.dart';

class ConnectivityNotifierService {
  ConnectivityNotifierService({
    required this.deviceId,
    required this.deviceName,
    required this.store,
    required this.telegram,
    WindowsControlService? windowsControl,
    this.interval = const Duration(seconds: 30),
  }) : windowsControl = windowsControl ?? WindowsControlService();

  final String deviceId;
  final String deviceName;
  final JsonFileStore store;
  final TelegramNotifierService telegram;
  final WindowsControlService windowsControl;
  final Duration interval;

  Timer? _timer;
  bool? _wasOnline;

  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _tick());
    _tick();
  }

  void stop() => _timer?.cancel();

  Future<void> _tick() async {
    final online = await _hasInternet();
    if (online && _wasOnline != true) {
      await _notifyOnline();
    }
    _wasOnline = online;
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup('api.telegram.org')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _notifyOnline() async {
    if (!telegram.isConfigured) return;
    final now = DateTime.now();
    final last = DateTime.tryParse(
      (store.get<String>('lastTelegramOnlineAt') ?? '').toString(),
    );
    if (last != null && now.difference(last).inMinutes < 10) return;

    final net = await windowsControl.getNetworkDetails();
    final isp = (net['Isp'] ?? '').trim();
    final ssid = (net['Ssid'] ?? net['ProfileName'] ?? '').trim();
    final publicIp = (net['PublicIp'] ?? '').trim();
    final localIp = (net['LocalIp'] ?? '').trim();
    final location = [net['City'], net['Country']].where((s) => s != null && s.isNotEmpty).join(', ');

    final buffer = StringBuffer();
    buffer.writeln('🟢 <b>الكمبيوتر متصل الآن بالإنترنت</b>\n');
    buffer.writeln('🖥️ <b>الجهاز:</b> $deviceName');
    buffer.writeln('🆔 <b>المعرف:</b> <code>$deviceId</code>');
    if (isp.isNotEmpty) {
      buffer.writeln('🏢 <b>الشركة ومزود الإنترنت:</b> <b>$isp</b>');
    }
    if (ssid.isNotEmpty) {
      buffer.writeln('📶 <b>الشبكة / WiFi:</b> $ssid');
    }
    if (localIp.isNotEmpty || publicIp.isNotEmpty) {
      final ipText = [
        if (localIp.isNotEmpty) 'محلي: $localIp',
        if (publicIp.isNotEmpty) 'خارجي: $publicIp${location.isNotEmpty ? ' ($location)' : ''}',
      ].join(' | ');
      buffer.writeln('🌐 <b>عناوين IP:</b> <code>$ipText</code>');
    }
    buffer.writeln('⏱️ <b>التوقيت:</b> ${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');

    final sent = await telegram.sendMessage(buffer.toString().trim());
    if (sent) {
      await store.set('lastTelegramOnlineAt', now.toIso8601String());
    }
  }
}
