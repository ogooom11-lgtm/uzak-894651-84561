class SelfSetupConfig {
  /// When true, the development/background agent will open an elevated
  /// PowerShell installer automatically if the Windows scheduled task is missing.
  /// Keep it false by default to avoid surprise UAC windows or startup clutter; use
  /// the app button "تشغيل مع Windows" when the user wants it.
  static const bool autoLaunchInstallerOnStart = false;

  /// Recommended: after launching the elevated installer, close the current
  /// debug/background process to avoid running two agents at the same time.
  static const bool exitCurrentProcessAfterLaunchingInstaller = true;

  static const String scheduledTaskName = 'KIOM PC Agent';
}
