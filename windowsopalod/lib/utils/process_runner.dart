import 'dart:async';
import 'dart:io';

/// Small process wrapper used by the Windows agent.
///
/// The old code used [Process.run] directly from many timers. If PowerShell,
/// taskkill, wmic, or a Windows COM call hangs, the agent can keep waiting and
/// later timer ticks pile up. This wrapper gives every native command a hard
/// timeout and terminates the child process before returning a synthetic result.
class SafeProcessRunner {
  const SafeProcessRunner._();

  static const Duration defaultTimeout = Duration(seconds: 12);
  static const Duration shortTimeout = Duration(seconds: 5);
  static const Duration longTimeout = Duration(seconds: 30);

  static Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = defaultTimeout,
    bool runInShell = false,
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    late final Process process;
    try {
      process = await Process.start(
        executable,
        arguments,
        runInShell: runInShell,
        workingDirectory: workingDirectory,
        environment: environment,
      );
    } catch (e) {
      return ProcessResult(
        -1,
        -1,
        '',
        'تعذر تشغيل الأمر $executable: $e',
      );
    }

    final stdoutFuture = process.stdout.transform(systemEncoding.decoder).join();
    final stderrFuture = process.stderr.transform(systemEncoding.decoder).join();

    var timedOut = false;
    int exitCode;
    try {
      exitCode = await process.exitCode.timeout(timeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      try {
        exitCode = await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        exitCode = -1;
      }
    }

    final stdoutText = await _safeText(stdoutFuture);
    final stderrText = await _safeText(stderrFuture);
    final timeoutMessage = timedOut
        ? 'انتهت مهلة الأمر بعد ${timeout.inSeconds} ثانية: $executable ${arguments.join(' ')}'
        : '';

    return ProcessResult(
      process.pid,
      timedOut && exitCode == 0 ? -1 : exitCode,
      stdoutText,
      [stderrText, timeoutMessage]
          .where((part) => part.trim().isNotEmpty)
          .join('\n'),
    );
  }

  static Future<ProcessResult> powershell(
    String script, {
    Duration timeout = defaultTimeout,
  }) {
    return run(
      'powershell.exe',
      ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', script],
      runInShell: false,
      timeout: timeout,
    );
  }

  static Future<String> _safeText(Future<String> future) async {
    try {
      return await future.timeout(const Duration(seconds: 2));
    } catch (_) {
      return '';
    }
  }
}
