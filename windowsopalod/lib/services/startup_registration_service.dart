import 'dart:io';

import '../utils/process_runner.dart';

class StartupRegistrationService {
  Future<void> registerCurrentExecutable() async {
    final exe = Platform.resolvedExecutable;
    final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    await SafeProcessRunner.run(
      'reg.exe',
      [
        'add',
        key,
        '/v',
        'KiomPcAgent',
        '/t',
        'REG_SZ',
        '/d',
        '"$exe"',
        '/f',
      ],
      timeout: SafeProcessRunner.shortTimeout,
    );
  }
}
