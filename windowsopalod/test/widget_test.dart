import 'package:flutter_test/flutter_test.dart';
import 'package:kiom_pc_agent/models/open_app_info.dart';

void main() {
  test('open app info serializes browser metadata', () {
    final app = OpenAppInfo(
      processId: 10,
      appName: 'chrome.exe',
      appPath: r'C:\Program Files\Google\Chrome\Application\chrome.exe',
      title: 'Inbox - Gmail - Google Chrome',
      openedAt: DateTime(2026, 5, 17, 8),
      iconKey: 'chrome',
      browserName: 'Chrome',
      pageTitle: 'Inbox - Gmail',
      siteName: 'Gmail',
    );

    final map = app.toMap();
    expect(map['processId'], 10);
    expect(map['browserName'], 'Chrome');
    expect(map['pageTitle'], 'Inbox - Gmail');
  });
}
