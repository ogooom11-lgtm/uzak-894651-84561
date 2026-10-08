class AppEnvironment {
  /// Telegram Cloud Database is now the primary cloud backend.
  static const bool useFirebase = false;

  /// Default Telegram bot token & chat id for Cloud Database (can be configured in app settings).
  static const String defaultTelegramBotToken =
      '8151486801:AAF-hVj-h5R1R7E7m1a8YwZ64X5o5K4w_9o';
  static const String defaultTelegramChatId = '';

  /// Temporary local user id used for local indexing.
  static const String demoUserId = 'local_demo_user';

  static const Duration connectionTimeout = Duration(seconds: 10);
}

