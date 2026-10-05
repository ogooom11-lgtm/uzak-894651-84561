import 'dart:convert';
import 'dart:io';

class SelfSetupCmdFallbackService {
  static const String taskName = 'KIOM PC Agent';
  static const String installDir = r'C:\Program Files\KIOM\PC Agent';
  static const bool enabledByDefault = true;

  Future<void> ensureInstalled() async {
    if (!enabledByDefault || !Platform.isWindows) return;

    final disabled = Platform.environment['KIOM_DISABLE_SELF_SETUP'];
    if (disabled == '1' || disabled?.toLowerCase() == 'true') {
      _log('SELF_SETUP: disabled by KIOM_DISABLE_SELF_SETUP.');
      return;
    }

    if (_isRunningFromInstallDir()) {
      _log('SELF_SETUP: skipped; already running from install dir.');
      return;
    }

    if (await _isScheduledTaskInstalled()) {
      _log('SELF_SETUP: scheduled task already installed.');
      return;
    }

    if (await _recentlyAttempted()) {
      _log('SELF_SETUP: skipped; attempted recently.');
      return;
    }

    await _markAttempted();

    final projectDir = Directory.current.path;
    final toolsDir = Directory(_join(projectDir, 'tools'));
    if (!toolsDir.existsSync()) toolsDir.createSync(recursive: true);

    final batPath = _join(toolsDir.path, 'kiom_install_agent_cmd_fallback.bat');
    final vbsPath = _join(toolsDir.path, 'kiom_run_installer_as_admin.vbs');

    await File(batPath)
        .writeAsString(_buildInstallBat(projectDir), encoding: utf8);
    await File(vbsPath)
        .writeAsString(_buildElevateVbs(batPath), encoding: utf8);

    _log('SELF_SETUP: trying elevated CMD through wscript.');
    if (await _startElevatedThroughVbs(vbsPath)) {
      _log('SELF_SETUP: installer requested. Windows may show UAC.');
      return;
    }

    _log('SELF_SETUP: wscript failed. Trying direct CMD.');
    if (await _startDirectCmd(batPath)) {
      _log('SELF_SETUP: direct CMD started. It may need Administrator.');
      return;
    }

    _log('SELF_SETUP: failed. Manual command: cmd.exe /c "$batPath"');
  }

  bool _isRunningFromInstallDir() {
    try {
      return Platform.resolvedExecutable
          .toLowerCase()
          .startsWith(installDir.toLowerCase());
    } catch (_) {
      return false;
    }
  }

  Future<bool> _isScheduledTaskInstalled() async {
    try {
      final result =
          await Process.run('schtasks.exe', ['/Query', '/TN', taskName]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _recentlyAttempted() async {
    try {
      final file = File(_join(_appDataDir().path, 'self_setup_attempt.json'));
      if (!file.existsSync()) return false;
      final data =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final attemptedAt =
          DateTime.tryParse(data['attemptedAt']?.toString() ?? '');
      if (attemptedAt == null) return false;
      return DateTime.now().toUtc().difference(attemptedAt.toUtc()).inMinutes <
          10;
    } catch (_) {
      return false;
    }
  }

  Future<void> _markAttempted() async {
    final file = File(_join(_appDataDir().path, 'self_setup_attempt.json'));
    file.parent.createSync(recursive: true);
    await file.writeAsString(
      jsonEncode({'attemptedAt': DateTime.now().toUtc().toIso8601String()}),
      encoding: utf8,
    );
  }

  Directory _appDataDir() {
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.trim().isNotEmpty) {
      return Directory(_join(appData, 'KiomPcAgent'));
    }
    return Directory(_join(Directory.current.path, 'KiomPcAgentData'));
  }

  Future<bool> _startElevatedThroughVbs(String vbsPath) async {
    try {
      final process = await Process.start(
        'wscript.exe',
        [vbsPath],
        mode: ProcessStartMode.detached,
        runInShell: false,
      );
      return process.pid > 0;
    } catch (e) {
      _log('SELF_SETUP: wscript failed: $e');
      return false;
    }
  }

  Future<bool> _startDirectCmd(String batPath) async {
    try {
      final process = await Process.start(
        'cmd.exe',
        ['/k', '"$batPath"'],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      return process.pid > 0;
    } catch (e) {
      _log('SELF_SETUP: cmd failed: $e');
      return false;
    }
  }

  String _buildElevateVbs(String batPath) {
    final safeBat = batPath.replaceAll('"', '""');
    return 'Set shell = CreateObject("Shell.Application")\r\n'
        'shell.ShellExecute "cmd.exe", "/k ""$safeBat""", "", "runas", 1\r\n';
  }

  String _buildInstallBat(String projectDir) {
    final safeProject = projectDir.replaceAll('"', '');
    return r"""
@echo off
chcp 65001 >nul
setlocal enabledelayedexpansion

set "PROJECT_DIR=__PROJECT_DIR__"
set "INSTALL_DIR=C:\Program Files\KIOM\PC Agent"
set "TASK_NAME=KIOM PC Agent"

echo.
echo ===============================
echo KIOM PC Agent Installer
echo ===============================
echo Project: "%PROJECT_DIR%"
echo Install: "%INSTALL_DIR%"
echo.

cd /d "%PROJECT_DIR%" || (
  echo [ERROR] Cannot open project directory.
  pause
  exit /b 1
)

echo [1/6] Building Flutter Windows release...
flutter build windows
if errorlevel 1 (
  echo [ERROR] flutter build windows failed.
  pause
  exit /b 1
)

set "RELEASE_DIR=%PROJECT_DIR%\build\windows\x64\runner\Release"
if not exist "%RELEASE_DIR%" (
  echo [ERROR] Release folder not found:
  echo "%RELEASE_DIR%"
  pause
  exit /b 1
)

set "EXE_NAME="
for %%F in ("%RELEASE_DIR%\*.exe") do (
  set "EXE_NAME=%%~nxF"
)

if "%EXE_NAME%"=="" (
  echo [ERROR] No EXE file found in Release folder.
  pause
  exit /b 1
)

echo Found EXE: %EXE_NAME%

echo [2/6] Creating install directory...
mkdir "%INSTALL_DIR%" 2>nul

echo [3/6] Copying release files...
xcopy "%RELEASE_DIR%\*" "%INSTALL_DIR%\" /E /I /Y >nul
if errorlevel 1 (
  echo [ERROR] Failed to copy release files. Make sure this CMD is running as Administrator.
  pause
  exit /b 1
)

if exist "%PROJECT_DIR%\config" (
  echo Copying config...
  mkdir "%INSTALL_DIR%\config" 2>nul
  xcopy "%PROJECT_DIR%\config\*" "%INSTALL_DIR%\config\" /E /I /Y >nul
)

echo [4/6] Creating scheduled task...
schtasks /Create /TN "%TASK_NAME%" /TR "\"%INSTALL_DIR%\%EXE_NAME%\" --background" /SC ONLOGON /RL HIGHEST /F
if errorlevel 1 (
  echo [ERROR] Failed to create scheduled task. Make sure this CMD is running as Administrator.
  pause
  exit /b 1
)

echo [5/6] Starting scheduled task...
schtasks /Run /TN "%TASK_NAME%"

echo [6/6] Done.
echo.
echo KIOM PC Agent installed successfully.
echo EXE: "%INSTALL_DIR%\%EXE_NAME%"
echo Task: "%TASK_NAME%"
echo.
pause
exit /b 0
"""
        .replaceAll('__PROJECT_DIR__', safeProject);
  }

  String _join(String a, String b) {
    if (a.endsWith(r'\') || a.endsWith('/')) return '$a$b';
    return '$a\\$b';
  }

  void _log(String message) {
    final line = '[${DateTime.now().toIso8601String()}] $message';
    // ignore: avoid_print
    print(line);
    try {
      final file = File(_join(_appDataDir().path, 'self_setup.log'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\r\n',
          mode: FileMode.append, encoding: utf8);
    } catch (_) {}
  }
}
