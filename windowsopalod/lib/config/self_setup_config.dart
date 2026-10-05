class SelfSetupConfig {
  /// When true, the development/background agent will open an elevated
  /// PowerShell installer automatically if the Windows scheduled task is missing.
  static const bool autoLaunchInstallerOnStart = true;

  /// Recommended: after launching the elevated installer, close the current
  /// debug/background process to avoid running two agents at the same time.
  static const bool exitCurrentProcessAfterLaunchingInstaller = true;

  static const String scheduledTaskName = 'KIOM PC Agent';
}
