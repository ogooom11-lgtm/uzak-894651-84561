import '../core/date_mapper.dart';

class OpenApp {
  const OpenApp({
    required this.id,
    required this.processId,
    required this.appName,
    required this.appPath,
    required this.openedAt,
    required this.status,
    this.iconKey,
    this.lastUpdated,
    this.windowTitle,
    this.pageTitle,
    this.url,
    this.siteName,
    this.browserName,
  });

  final String id;
  final String processId;
  final String appName;
  final String appPath;
  final DateTime openedAt;
  final String status;
  final String? iconKey;
  final DateTime? lastUpdated;
  final String? windowTitle;
  final String? pageTitle;
  final String? url;
  final String? siteName;
  final String? browserName;

  bool get isBrowserItem {
    final lower =
        '${appName.toLowerCase()} ${browserName?.toLowerCase() ?? ''} ${appPath.toLowerCase()}';
    return url != null && url!.isNotEmpty ||
        lower.contains('chrome') ||
        lower.contains('edge') ||
        lower.contains('firefox') ||
        lower.contains('brave') ||
        lower.contains('opera') ||
        lower.contains('browser');
  }

  String get title {
    final candidates = [pageTitle, windowTitle, siteName, appName];
    for (final value in candidates) {
      final text = (value ?? '').trim();
      if (text.isNotEmpty) return text;
    }
    return 'Application';
  }

  String get subtitle {
    if ((url ?? '').isNotEmpty) return url!;
    if ((siteName ?? '').isNotEmpty && siteName != title) return siteName!;
    return appPath;
  }

  String get effectiveIconKey {
    final parts = [iconKey, siteName, url, browserName, appName, appPath]
        .where((e) => e != null && e.trim().isNotEmpty)
        .join(' ')
        .toLowerCase();
    return parts;
  }

  factory OpenApp.fromMap(String id, Map<String, dynamic> map) {
    return OpenApp(
      id: id,
      processId: (map['processId'] ?? map['pid'] ?? id).toString(),
      appName:
          (map['appName'] ?? map['name'] ?? map['processName'] ?? 'Application')
              .toString(),
      appPath: (map['appPath'] ?? map['path'] ?? '').toString(),
      openedAt: dateFromAny(map['openedAt'] ?? map['createdAt']),
      status: (map['status'] ?? 'running').toString(),
      iconKey: map['iconKey']?.toString(),
      lastUpdated:
          map['lastUpdated'] == null ? null : dateFromAny(map['lastUpdated']),
      windowTitle: (map['windowTitle'] ?? map['title'])?.toString(),
      pageTitle: (map['pageTitle'] ?? map['tabTitle'] ?? map['browserTitle'])
          ?.toString(),
      url: map['url']?.toString(),
      siteName:
          (map['siteName'] ?? map['domain'] ?? map['website'])?.toString(),
      browserName: (map['browserName'] ?? map['browser'])?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'processId': processId,
      'appName': appName,
      'appPath': appPath,
      'openedAt': dateToFirestore(openedAt),
      'status': status,
      'iconKey': iconKey,
      'lastUpdated': nullableDateToFirestore(lastUpdated),
      'windowTitle': windowTitle,
      'pageTitle': pageTitle,
      'url': url,
      'siteName': siteName,
      'browserName': browserName,
    };
  }
}
