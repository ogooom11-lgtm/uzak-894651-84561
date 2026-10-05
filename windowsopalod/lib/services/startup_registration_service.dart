import 'dart:io';

class StartupRegistrationService {
  Future<void> registerCurrentExecutable() async {
    final exe = Platform.resolvedExecutable;
    final key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    await Process.run('reg.exe', [
      'add',
      key,
      '/v',
      'KiomPcAgent',
      '/t',
      'REG_SZ',
      '/d',
      '"$exe"',
      '/f'
    ]);
  }
}
