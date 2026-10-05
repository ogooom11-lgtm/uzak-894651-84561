import 'dart:async';
import 'dart:io';

import '../utils/json_file_store.dart';

class DesktopLockService {
  DesktopLockService({required this.store});

  final JsonFileStore store;

  Timer? _timer;
  DateTime? _lastLockAttemptAt;

  void start() {
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 5), (_) => enforceLockWindow());
    enforceLockWindow();
  }

  void stop() => _timer?.cancel();

  Future<void> lockNow({String reason = 'manual'}) async {
    await _lockWorkStation(reason: reason);
  }

  Future<DateTime> lockFor(Duration duration) async {
    final until = DateTime.now().add(duration);
    await store.set('desktopLockUntil', until.toIso8601String());
    await store.appendLog(
        'desktop_lock_started', 'تم تفعيل قفل الكمبيوتر لمدة محددة', {
      'until': until.toIso8601String(),
      'durationSeconds': duration.inSeconds,
    });
    await _lockWorkStation(reason: 'lock_for_duration');
    return until;
  }

  Future<void> clearTimedLock() async {
    await store.set('desktopLockUntil', null);
    await store.appendLog(
        'desktop_lock_cleared', 'تم إيقاف إعادة قفل الكمبيوتر');
  }

  Future<void> enforceLockWindow() async {
    final untilText = store.get<String>('desktopLockUntil');
    if (untilText == null || untilText.trim().isEmpty) return;

    final until = DateTime.tryParse(untilText);
    if (until == null || !until.isAfter(DateTime.now())) {
      await clearTimedLock();
      return;
    }

    final now = DateTime.now();
    if (_lastLockAttemptAt != null &&
        now.difference(_lastLockAttemptAt!).inSeconds < 15) {
      return;
    }
    await _lockWorkStation(reason: 'timed_lock_enforcement');
  }

  Future<void> _lockWorkStation({required String reason}) async {
    _lastLockAttemptAt = DateTime.now();
    final result =
        await Process.run('rundll32.exe', ['user32.dll,LockWorkStation']);
    await store.appendLog(
      result.exitCode == 0 ? 'desktop_locked' : 'desktop_lock_error',
      result.exitCode == 0 ? 'تم قفل شاشة Windows' : 'تعذر قفل شاشة Windows',
      {
        'reason': reason,
        'exitCode': result.exitCode,
        'stdout': result.stdout.toString(),
        'stderr': result.stderr.toString(),
      },
    );
    if (result.exitCode != 0) {
      throw StateError(
          'تعذر قفل شاشة Windows: ${result.stderr}${result.stdout}');
    }
  }
}
