import 'dart:convert';
import 'dart:io';

class AgentConfig {
  final String projectId;
  final String apiKey;
  final String databaseId;
  final String demoUserId;
  final String appVersion;
  final int pollCommandsEverySeconds;
  final int syncOpenAppsEverySeconds;
  final int scanExplorerEverySeconds;
  final bool autoCreatePairingToken;
  final bool deleteCommandsAfterExecution;
  final bool enableStartupRegistrationFromCode;
  final bool enableDangerousPowerCommands;
  final bool enableWifiBluetoothCommands;
  final int defaultPasswordAllowMinutes;
  final String googleDriveServiceAccountJsonPath;
  final String googleDriveClientId;
  final String googleDriveClientSecret;
  final String googleDriveRefreshToken;
  final String googleDriveFolderId;
  final String telegramBotToken;
  final String telegramChatId;

  const AgentConfig({
    required this.projectId,
    required this.apiKey,
    this.databaseId = '(default)',
    this.demoUserId = 'local_demo_user',
    this.appVersion = '0.1.0',
    this.pollCommandsEverySeconds = 3,
    this.syncOpenAppsEverySeconds = 8,
    this.scanExplorerEverySeconds = 2,
    this.autoCreatePairingToken = true,
    this.deleteCommandsAfterExecution = false,
    this.enableStartupRegistrationFromCode = false,
    this.enableDangerousPowerCommands = true,
    this.enableWifiBluetoothCommands = true,
    this.defaultPasswordAllowMinutes = 10,
    this.googleDriveServiceAccountJsonPath = '',
    this.googleDriveClientId = '',
    this.googleDriveClientSecret = '',
    this.googleDriveRefreshToken = '',
    this.googleDriveFolderId = '',
    this.telegramBotToken = '',
    this.telegramChatId = '',
  });

  static Future<AgentConfig> load() async {
    final file = await _findConfigFile();
    final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    return AgentConfig(
      projectId: (map['projectId'] ?? '').toString(),
      apiKey: (map['apiKey'] ?? '').toString(),
      databaseId: (map['databaseId'] ?? '(default)').toString(),
      demoUserId: (map['demoUserId'] ?? 'local_demo_user').toString(),
      appVersion: (map['appVersion'] ?? '0.1.0').toString(),
      pollCommandsEverySeconds:
          (map['pollCommandsEverySeconds'] as num?)?.toInt() ?? 3,
      syncOpenAppsEverySeconds:
          (map['syncOpenAppsEverySeconds'] as num?)?.toInt() ?? 8,
      scanExplorerEverySeconds:
          (map['scanExplorerEverySeconds'] as num?)?.toInt() ?? 2,
      autoCreatePairingToken: map['autoCreatePairingToken'] != false,
      deleteCommandsAfterExecution: map['deleteCommandsAfterExecution'] == true,
      enableStartupRegistrationFromCode:
          map['enableStartupRegistrationFromCode'] == true,
      enableDangerousPowerCommands: map['enableDangerousPowerCommands'] != true,
      enableWifiBluetoothCommands: map['enableWifiBluetoothCommands'] != true,
      defaultPasswordAllowMinutes:
          (map['defaultPasswordAllowMinutes'] as num?)?.toInt() ?? 10,
      googleDriveServiceAccountJsonPath:
          (map['googleDriveServiceAccountJsonPath'] ?? '').toString(),
      googleDriveClientId: (map['googleDriveClientId'] ?? '').toString(),
      googleDriveClientSecret:
          (map['googleDriveClientSecret'] ?? '').toString(),
      googleDriveRefreshToken:
          (map['googleDriveRefreshToken'] ?? '').toString(),
      googleDriveFolderId: (map['googleDriveFolderId'] ?? '').toString(),
      telegramBotToken: (map['telegramBotToken'] ?? '').toString(),
      telegramChatId: (map['telegramChatId'] ?? '').toString(),
    );
  }

  static Future<File> _findConfigFile() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    final appData = Platform.environment['APPDATA'];
    final programData = Platform.environment['ProgramData'];

    final candidates = <File>[
      File('$exeDir\\config\\firebase_config.json'),
      File('$currentDir\\config\\firebase_config.json'),
      if (appData != null) File('$appData\\KiomPcAgent\\firebase_config.json'),
      if (appData != null)
        File('$appData\\KiomPcAgent\\config\\firebase_config.json'),
      if (programData != null)
        File('$programData\\KiomPcAgent\\firebase_config.json'),
      if (programData != null)
        File('$programData\\KiomPcAgent\\config\\firebase_config.json'),
    ];

    for (final file in candidates) {
      if (await file.exists()) return file;
    }

    throw StateError(
      'ملف الإعدادات غير موجود: firebase_config.json\n'
      'ضع الملف في واحد من هذه المسارات:\n'
      '${candidates.map((f) => f.path).join('\n')}\n\n'
      'عند تشغيل ملف exe مباشرة يجب أن يكون بجانبه مجلد config وفيه firebase_config.json.',
    );
  }
}
