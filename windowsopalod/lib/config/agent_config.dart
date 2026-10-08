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
    this.syncOpenAppsEverySeconds = 10,
    this.scanExplorerEverySeconds = 5,
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
          _readSeconds(map['pollCommandsEverySeconds'], fallback: 3, min: 2),
      syncOpenAppsEverySeconds:
          _readSeconds(map['syncOpenAppsEverySeconds'], fallback: 10, min: 6),
      scanExplorerEverySeconds:
          _readSeconds(map['scanExplorerEverySeconds'], fallback: 5, min: 3),
      autoCreatePairingToken: map['autoCreatePairingToken'] != false,
      deleteCommandsAfterExecution: map['deleteCommandsAfterExecution'] == true,
      enableStartupRegistrationFromCode:
          map['enableStartupRegistrationFromCode'] == true,
      enableDangerousPowerCommands: map['enableDangerousPowerCommands'] != false,
      enableWifiBluetoothCommands: map['enableWifiBluetoothCommands'] != false,
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

  static int _readSeconds(
    dynamic value, {
    required int fallback,
    required int min,
  }) {
    final seconds = value is num
        ? value.toInt()
        : int.tryParse((value ?? '').toString()) ?? fallback;
    if (seconds < min) return min;
    return seconds;
  }

  static Future<File> _findConfigFile() async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final currentDir = Directory.current.path;
    final appData = Platform.environment['APPDATA'];
    final programData = Platform.environment['ProgramData'];

    // Primary location: %APPDATA%\KiomPcAgent\agent_config.json
    final appDataConfigFile = appData != null
        ? File('$appData\\KiomPcAgent\\agent_config.json')
        : null;

    if (appDataConfigFile != null && await appDataConfigFile.exists()) {
      return appDataConfigFile;
    }

    final candidates = <File>[
      if (appDataConfigFile != null) appDataConfigFile,
      File('$currentDir\\config\\agent_config.json'),
      File('$exeDir\\config\\agent_config.json'),
      if (appData != null) File('$appData\\KiomPcAgent\\firebase_config.json'),
      File('$currentDir\\config\\firebase_config.json'),
      File('$exeDir\\config\\firebase_config.json'),
      if (appData != null)
        File('$appData\\KiomPcAgent\\config\\agent_config.json'),
      if (programData != null)
        File('$programData\\KiomPcAgent\\agent_config.json'),
    ];

    for (final file in candidates) {
      if (await file.exists()) {
        // Also mirror it to %APPDATA%\KiomPcAgent\agent_config.json for easy access
        if (appDataConfigFile != null && !await appDataConfigFile.exists()) {
          try {
            await appDataConfigFile.parent.create(recursive: true);
            await file.copy(appDataConfigFile.path);
          } catch (_) {}
        }
        return file;
      }
    }

    // Auto-create default agent_config.json if none exists
    final targetDir = appData != null
        ? Directory('$appData\\KiomPcAgent')
        : Directory('$currentDir\\config');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    final defaultFile = File('${targetDir.path}\\agent_config.json');
    final defaultJson = const JsonEncoder.withIndent('  ').convert({
      'telegramBotToken': '8151486801:AAF-hVj-h5R1R7E7m1a8YwZ64X5o5K4w_9o',
      'telegramChatId': '',
      'pollCommandsEverySeconds': 3,
      'syncOpenAppsEverySeconds': 10,
      'scanExplorerEverySeconds': 5,
      'enableDangerousPowerCommands': true,
      'enableWifiBluetoothCommands': true,
      'defaultPasswordAllowMinutes': 10,
    });
    await defaultFile.writeAsString(defaultJson);
    return defaultFile;
  }
}
