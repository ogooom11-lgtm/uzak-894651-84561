class AppEnvironment {
  /// Telegram Cloud Database is now the primary cloud backend.
  static const bool useFirebase = false;

  /// Default Telegram bot token & chat id for Cloud Database (Group channel).
  static const String defaultTelegramBotToken =
      '8919370396:AAHQrNYtJzy7yVPGIWQSsQjbcaAJ1Q8cWGw';
  static const String defaultTelegramChatId = '-1004449817252';

  /// Default User Control Bot & Chat ID for direct Telegram control & screenshots.
  static const String defaultUserBotToken =
      '8465366644:AAEMXtYGEl5Qo5BwNwiUdqmWml_vO-meliM';
  static const String defaultUserChatId = '8597783492';

  /// Temporary local user id used for local indexing.
  static const String demoUserId = 'local_demo_user';

  static const Duration connectionTimeout = Duration(seconds: 10);
}
