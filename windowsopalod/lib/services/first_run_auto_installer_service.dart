import 'dart:io';

/// First-run installer for KIOM PC Agent.
///
/// What it does:
/// - Checks whether the Windows Scheduled Task "KIOM PC Agent" already exists.
/// - If not installed, writes a temporary CMD installer under %APPDATA%\KiomPcAgent.
/// - Opens CMD with Administrator approval through Windows UAC.
/// - The CMD installer builds Flutter Windows release, copies files to Program Files,
///   creates a Scheduled Task with highest privileges, and runs it.
///
/// Important:
/// Windows will always ask for Administrator approval the first time. This is normal.
/// After the scheduled task is created, the agent can start with Windows as admin
/// without asking every time.
class FirstRunAutoInstallerService {
  FirstRunAutoInstallerService({
    this.taskName = 'KIOM PC Agent',
    this.installDir = r'C:\Program Files\KIOM\PC Agent',
  });

  final String taskName;
  final String installDir;

  Future<void> ensureInstalledOrLaunchSetup() async {
    if (!Platform.isWindows) return;

    if (Platform.environment['KIOM_DISABLE_SELF_SETUP'] == '1') {
      _logSync('Self setup disabled by KIOM_DISABLE_SELF_SETUP=1');
      return;
    }

    if (_isRunningFromInstallDir()) {
      _logSync('Running from install directory. Self setup skipped.');
      return;
    }

    final installed = await _scheduledTaskExists();
    if (installed) {
      _logSync('Scheduled task already exists. Self setup skipped.');
      return;
    }

    _logSync(
        'Scheduled task not found. Launching first-run admin installer...');
    await _launchElevatedCmdInstaller();
  }

  bool _isRunningFromInstallDir() {
    final exe = Platform.resolvedExecutable.toLowerCase().replaceAll('/', r'\');
    final dir = installDir.toLowerCase().replaceAll('/', r'\');
    return exe.startsWith(dir);
  }

  Future<bool> _scheduledTaskExists() async {
    try {
      final result = await Process.run(
        'schtasks.exe',
        ['/Query', '/TN', taskName],
        runInShell: true,
      );
      return result.exitCode == 0;
    } catch (e) {
      _logSync('Failed to query scheduled task: $e');
      return false;
    }
  }

  Future<void> _launchElevatedCmdInstaller() async {
    final appData =
        Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    final workDir = Directory('$appData\\KiomPcAgent');
    if (!workDir.existsSync()) {
      workDir.createSync(recursive: true);
    }

    final batPath = '${workDir.path}\\kiom_first_run_install.cmd';
    final vbsPath = '${workDir.path}\\kiom_first_run_elevate.vbs';
    final projectDir = Directory.current.absolute.path;

    File(batPath).writeAsStringSync(_buildInstallerCmd(projectDir));
    File(vbsPath).writeAsStringSync(_buildElevateVbs(batPath));

    _logSync('Installer CMD written to: $batPath');
    _logSync('Elevate VBS written to: $vbsPath');

    try {
      final result = await Process.start(
        'wscript.exe',
        [vbsPath],
        mode: ProcessStartMode.detached,
        runInShell: true,
      );
      _logSync('wscript elevated installer launched. pid=${result.pid}');
    } catch (e) {
      _logSync('wscript failed: $e');
      try {
        final mshtaCommand =
            'vbscript:CreateObject("Shell.Application").ShellExecute("cmd.exe","/c ""$batPath""","","runas",1)(window.close)';
        final result = await Process.start(
          'mshta.exe',
          [mshtaCommand],
          mode: ProcessStartMode.detached,
          runInShell: true,
        );
        _logSync('mshta elevated installer launched. pid=${result.pid}');
      } catch (e2) {
        _logSync('mshta failed too: $e2');
      }
    }
  }

  String _buildElevateVbs(String batPath) {
    final escaped = batPath.replaceAll('"', '""');
    return '''
Set shell = CreateObject("Shell.Application")
shell.ShellExecute "cmd.exe", "/c ""$escaped""", "", "runas", 1
''';
  }

  String _buildInstallerCmd(String projectDir) {
    final escapedProjectDir = projectDir.replaceAll('%', '%%');
    final escapedTaskName = taskName.replaceAll('%', '%%');
    final escapedInstallDir = installDir.replaceAll('%', '%%');

    return '''
@echo off
setlocal EnableExtensions EnableDelayedExpansion

title KIOM PC Agent First Run Installer

set "PROJECT_DIR=$escapedProjectDir"
set "INSTALL_DIR=$escapedInstallDir"
set "TASK_NAME=$escapedTaskName"
set "LOG_DIR=%APPDATA%\\KiomPcAgent"
set "LOG_FILE=%LOG_DIR%\\self_setup.log"

if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

echo.>> "%LOG_FILE%"
echo ===============================>> "%LOG_FILE%"
echo KIOM first-run installer started at %DATE% %TIME%>> "%LOG_FILE%"
echo PROJECT_DIR=%PROJECT_DIR%>> "%LOG_FILE%"
echo INSTALL_DIR=%INSTALL_DIR%>> "%LOG_FILE%"

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo ERROR: This installer did not get Administrator permission.>> "%LOG_FILE%"
  echo Please approve the Administrator permission window.>> "%LOG_FILE%"
  pause
  exit /b 1
)

cd /d "%PROJECT_DIR%"
if %errorlevel% neq 0 (
  echo ERROR: Cannot open project directory: %PROJECT_DIR%>> "%LOG_FILE%"
  pause
  exit /b 1
)

if not exist "pubspec.yaml" (
  echo ERROR: pubspec.yaml not found. This must run from the Flutter project root.>> "%LOG_FILE%"
  pause
  exit /b 1
)

echo Building Flutter Windows release...>> "%LOG_FILE%"
flutter build windows >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 (
  echo ERROR: flutter build windows failed.>> "%LOG_FILE%"
  echo Flutter build failed. Check: %LOG_FILE%
  pause
  exit /b 1
)

set "RELEASE_DIR=%PROJECT_DIR%\\build\\windows\\x64\\runner\\Release"
if not exist "%RELEASE_DIR%" (
  echo ERROR: Release folder not found: %RELEASE_DIR%>> "%LOG_FILE%"
  pause
  exit /b 1
)

set "EXE_NAME="
for %%F in ("%RELEASE_DIR%\\*.exe") do set "EXE_NAME=%%~nxF"
if "%EXE_NAME%"=="" (
  echo ERROR: No EXE found in release folder.>> "%LOG_FILE%"
  pause
  exit /b 1
)

echo Found EXE: %EXE_NAME%>> "%LOG_FILE%"

echo Copying files...>> "%LOG_FILE%"
mkdir "%INSTALL_DIR%" 2>nul
xcopy "%RELEASE_DIR%\\*" "%INSTALL_DIR%\\" /E /I /Y >> "%LOG_FILE%" 2>&1
if %errorlevel% geq 4 (
  echo ERROR: Failed to copy release files.>> "%LOG_FILE%"
  pause
  exit /b 1
)

if exist "%PROJECT_DIR%\\config" (
  mkdir "%INSTALL_DIR%\\config" 2>nul
  xcopy "%PROJECT_DIR%\\config\\*" "%INSTALL_DIR%\\config\\" /E /I /Y >> "%LOG_FILE%" 2>&1
)

set "EXE_PATH=%INSTALL_DIR%\\%EXE_NAME%"
if not exist "%EXE_PATH%" (
  echo ERROR: Installed EXE not found: %EXE_PATH%>> "%LOG_FILE%"
  pause
  exit /b 1
)

echo Creating Scheduled Task...>> "%LOG_FILE%"
schtasks /Create /TN "%TASK_NAME%" /TR "\\"%EXE_PATH%\\" --background" /SC ONLOGON /RL HIGHEST /F >> "%LOG_FILE%" 2>&1
if %errorlevel% neq 0 (
  echo ERROR: Failed to create scheduled task.>> "%LOG_FILE%"
  pause
  exit /b 1
)

echo Starting Scheduled Task...>> "%LOG_FILE%"
schtasks /Run /TN "%TASK_NAME%" >> "%LOG_FILE%" 2>&1

echo KIOM PC Agent installed successfully.>> "%LOG_FILE%"
echo Installed successfully. You can close this window.
echo Log file: %LOG_FILE%
timeout /t 3 >nul
exit /b 0
''';
  }

  void _logSync(String message) {
    try {
      final appData =
          Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
      final dir = Directory('$appData\\KiomPcAgent');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final log = File('${dir.path}\\self_setup.log');
      log.writeAsStringSync(
        '[${DateTime.now().toIso8601String()}] $message\n',
        mode: FileMode.append,
      );
    } catch (_) {}
  }
}
