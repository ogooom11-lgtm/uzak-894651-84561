import 'dart:async';
import 'dart:io';

import '../utils/json_file_store.dart';
import 'telegram_notifier_service.dart';

class ConnectivityNotifierService {
  ConnectivityNotifierService({
    required this.deviceId,
    required this.deviceName,
    required this.store,
    required this.telegram,
    this.interval = const Duration(seconds: 30),
  });

  final String deviceId;
  final String deviceName;
  final JsonFileStore store;
  final TelegramNotifierService telegram;
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

    final sent = await telegram.sendMessage(
      'KIOM: الآن متصل\nالجهاز: $deviceName\nالمعرف: $deviceId',
    );
    if (sent) {
      await store.set('lastTelegramOnlineAt', now.toIso8601String());
    }
  }
}
