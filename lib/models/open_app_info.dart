class OpenAppInfo {
  final int processId;
  final String appName;
  final String appPath;
  final String title;
  final DateTime openedAt;
  final String status;
  final String iconKey;
  final String? browserName;
  final String? pageTitle;
  final String? url;
  final String? siteName;

  const OpenAppInfo({
    required this.processId,
    required this.appName,
    required this.appPath,
    required this.title,
    required this.openedAt,
    this.status = 'running',
    this.iconKey = 'default',
    this.browserName,
    this.pageTitle,
    this.url,
    this.siteName,
  });

  Map<String, dynamic> toMap() => {
        'processId': processId,
        'appName': appName,
        'appPath': appPath,
        'title': title,
        'windowTitle': title,
        'openedAt': openedAt.toIso8601String(),
        'status': status,
        'iconKey': iconKey,
        if (browserName != null && browserName!.isNotEmpty)
          'browserName': browserName,
        if (pageTitle != null && pageTitle!.isNotEmpty) 'pageTitle': pageTitle,
        if (url != null && url!.isNotEmpty) 'url': url,
        if (siteName != null && siteName!.isNotEmpty) 'siteName': siteName,
        'lastUpdated': DateTime.now().toIso8601String(),
      };
}
